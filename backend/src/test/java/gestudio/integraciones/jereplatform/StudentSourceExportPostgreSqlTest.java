package gestudio.integraciones.jereplatform;

import com.fasterxml.jackson.databind.ObjectMapper;
import gestudio.entidades.Usuario;
import gestudio.infra.persistencia.PostgreSqlIntegrationTest;
import gestudio.integraciones.jereplatform.application.StudentSourceExportException;
import gestudio.integraciones.jereplatform.application.StudentSourceExportService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.AccessDeniedException;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.time.LocalDate;
import java.util.Base64;
import java.util.HexFormat;
import java.util.UUID;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

@SpringBootTest(
        webEnvironment = SpringBootTest.WebEnvironment.NONE,
        properties = {
                "app.jere-platform-student-export.enabled=true",
                "app.jere-platform-student-export.organization-id=synthetic-academy",
                "app.jere-platform-student-export.tenant-id=00000000-0000-0000-0000-0000000000a1",
                "app.jere-platform-student-export.page-size=2"
        }
)
class StudentSourceExportPostgreSqlTest extends PostgreSqlIntegrationTest {
    private static final String SECRET = runtimeSecret();

    @DynamicPropertySource
    static void configureExportSecret(DynamicPropertyRegistry registry) {
        registry.add("app.jere-platform-student-export.current-secret", () -> SECRET);
    }

    @Autowired private StudentSourceExportService exports;
    @Autowired private JdbcTemplate jdbc;
    @Autowired private ObjectMapper objectMapper;

    private Usuario actor;

    @BeforeEach
    void resetIntegrationData() {
        jdbc.update("DELETE FROM jere_platform_student_export_pages");
        jdbc.update("DELETE FROM jere_platform_student_export_snapshots");
        jdbc.execute("TRUNCATE TABLE alumnos CASCADE");
        actor = actor("SUPERADMIN");
    }

    @Test
    void materializaPaginasFirmadasEstablesYMinimasQueSobrevivenCambiosPosteriores() throws Exception {
        long firstId = student("Ada", "Synthetic", true, "ada@example.invalid", "11111111");
        long secondId = student("Beto", "Synthetic", false, "beto@example.invalid", "22222222");
        long thirdId = student("Cora", "Synthetic", true, "cora@example.invalid", "33333333");

        var first = exports.createSnapshot(actor);
        var replayedFirst = exports.page(first.checkpoint().toString(), null, actor);

        assertThat(first.pageNumber()).isOne();
        assertThat(first.pageCount()).isEqualTo(2);
        assertThat(first.recordCount()).isEqualTo(2);
        assertThat(first.payload()).isEqualTo(replayedFirst.payload());
        assertThat(first.signature()).isEqualTo(replayedFirst.signature());
        assertSignature(first.payload(), first.signature());

        var firstJson = objectMapper.readTree(first.payload());
        assertThat(firstJson.path("tenantId").textValue())
                .isEqualTo("00000000-0000-0000-0000-0000000000a1");
        assertThat(firstJson.path("sourceType").textValue()).isEqualTo("GESTUDIO_STUDENT");
        assertThat(firstJson.path("pageNumber").intValue()).isOne();
        assertThat(firstJson.path("pageCount").intValue()).isEqualTo(2);
        assertThat(firstJson.path("fullSnapshot").booleanValue()).isFalse();
        assertThat(firstJson.path("records").findValuesAsText("sourceId"))
                .containsExactly(Long.toString(firstId), Long.toString(secondId));
        assertMinimalPayload(first.payload());

        jdbc.update("UPDATE alumnos SET nombre = 'Changed', activo = FALSE WHERE id = ?", thirdId);
        var last = exports.page(first.checkpoint().toString(), first.nextCursor(), actor);
        var lastAgain = exports.page(first.checkpoint().toString(), first.nextCursor(), actor);

        assertThat(last.pageNumber()).isEqualTo(2);
        assertThat(last.nextCursor()).isNull();
        assertThat(last.payload()).isEqualTo(lastAgain.payload());
        assertThat(last.signature()).isEqualTo(lastAgain.signature());
        assertSignature(last.payload(), last.signature());
        var lastJson = objectMapper.readTree(last.payload());
        assertThat(lastJson.path("fullSnapshot").booleanValue()).isTrue();
        assertThat(lastJson.path("records").get(0).path("sourceId").textValue())
                .isEqualTo(Long.toString(thirdId));
        assertThat(lastJson.path("records").get(0).path("displayName").textValue())
                .isEqualTo("Cora Synthetic");
        assertThat(lastJson.path("records").get(0).path("active").booleanValue()).isTrue();
        assertMinimalPayload(last.payload());

        assertThat(jdbc.queryForObject(
                "SELECT count(*) FROM jere_platform_student_export_pages WHERE snapshot_checkpoint = ?",
                Integer.class,
                first.checkpoint()
        )).isEqualTo(2);
        assertThat(jdbc.queryForObject(
                """
                SELECT count(*) FROM auditoria_eventos
                 WHERE entidad_id = ? AND categoria = 'SISTEMA'
                   AND metadata::text NOT LIKE '%signature%'
                   AND metadata::text NOT LIKE '%payload%'
                """,
                Integer.class,
                first.checkpoint().toString()
        )).isEqualTo(4);
    }

    @Test
    void replayConcurrenteLeeLosMismosBytesPersistidos() throws Exception {
        student("Concurrent", "Synthetic", true, null, null);
        var created = exports.createSnapshot(actor);

        try (var executor = Executors.newFixedThreadPool(2)) {
            var first = executor.submit(() -> exports.page(created.checkpoint().toString(), null, actor));
            var second = executor.submit(() -> exports.page(created.checkpoint().toString(), null, actor));
            var firstPage = first.get(10, TimeUnit.SECONDS);
            var secondPage = second.get(10, TimeUnit.SECONDS);
            assertThat(firstPage.payload()).isEqualTo(secondPage.payload());
            assertThat(firstPage.signature()).isEqualTo(secondPage.signature());
        }
    }

    @Test
    void cursorManipuladoYActorSinPermisosFallanCerrado() {
        student("Secure", "Synthetic", true, null, null);
        var created = exports.createSnapshot(actor);

        assertThatThrownBy(() -> exports.page(created.checkpoint().toString(), "manipulated", actor))
                .isInstanceOf(StudentSourceExportException.class)
                .extracting(error -> ((StudentSourceExportException) error).code())
                .isEqualTo(StudentSourceExportException.Code.CURSOR_INVALID);

        Usuario unauthorized = actor("CAJA");
        assertThatThrownBy(() -> exports.createSnapshot(unauthorized))
                .isInstanceOf(AccessDeniedException.class);
        assertThat(jdbc.queryForObject(
                "SELECT count(*) FROM jere_platform_student_export_snapshots",
                Integer.class
        )).isOne();
    }

    @Test
    void referenciaInvalidaRevierteSnapshotYPaginas() {
        student("A".repeat(100), "B".repeat(100), true, null, null);

        assertThatThrownBy(() -> exports.createSnapshot(actor))
                .isInstanceOf(StudentSourceExportException.class)
                .extracting(error -> ((StudentSourceExportException) error).code())
                .isEqualTo(StudentSourceExportException.Code.STUDENT_REFERENCE_INVALID);
        assertThat(jdbc.queryForObject(
                "SELECT count(*) FROM jere_platform_student_export_snapshots",
                Integer.class
        )).isZero();
        assertThat(jdbc.queryForObject(
                "SELECT count(*) FROM jere_platform_student_export_pages",
                Integer.class
        )).isZero();
    }

    @Test
    void snapshotVacioEsUnaPaginaCompletaValida() throws Exception {
        var page = exports.createSnapshot(actor);
        var json = objectMapper.readTree(page.payload());

        assertThat(page.pageCount()).isOne();
        assertThat(page.recordCount()).isZero();
        assertThat(json.path("fullSnapshot").booleanValue()).isTrue();
        assertThat(json.path("nextCursor").isNull()).isTrue();
        assertThat(json.path("records").isEmpty()).isTrue();
    }

    @Test
    void generaArtefactosSinteticosParaSmokeCruzado() throws Exception {
        student("Synthetic", "Student One", true, null, null);
        student("Synthetic", "Student Two", false, null, null);
        student("Synthetic", "Student Three", true, null, null);

        var first = exports.createSnapshot(actor);
        var last = exports.page(first.checkpoint().toString(), first.nextCursor(), actor);
        assertThat(first.pageNumber()).isOne();
        assertThat(last.pageNumber()).isEqualTo(2);
        assertSignature(first.payload(), first.signature());
        assertSignature(last.payload(), last.signature());

        String outputValue = System.getenv("GESTUDIO_SOURCE_EXPORT_SMOKE_OUTPUT");
        if (outputValue == null || outputValue.isBlank()) {
            return;
        }
        Path output = Path.of(outputValue).toAbsolutePath().normalize();
        Files.createDirectories(output);
        writeArtifact(output, first);
        writeArtifact(output, last);
    }

    private long student(
            String firstName,
            String lastName,
            boolean active,
            String email,
            String document
    ) {
        return jdbc.queryForObject(
                """
                INSERT INTO alumnos(
                    nombre, apellido, email, documento, fecha_incorporacion, activo, version)
                VALUES (?, ?, ?, ?, ?, ?, 0)
                RETURNING id
                """,
                Long.class,
                firstName,
                lastName,
                email,
                document,
                LocalDate.of(2026, 1, 1),
                active
        );
    }

    private Usuario actor(String roleCode) {
        Long roleId = jdbc.queryForObject(
                "SELECT id FROM roles WHERE codigo = ?",
                Long.class,
                roleCode
        );
        Long userId = jdbc.queryForObject(
                """
                INSERT INTO usuarios(nombre_usuario, contrasena, rol_id, activo, auth_version, version)
                VALUES (?, 'synthetic-hash', ?, TRUE, 0, 0)
                RETURNING id
                """,
                Long.class,
                "student-export-" + roleCode.toLowerCase() + "-" + UUID.randomUUID(),
                roleId
        );
        Usuario actor = new Usuario();
        actor.setId(userId);
        return actor;
    }

    private static void assertSignature(byte[] payload, String signature) throws Exception {
        Mac mac = Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(SECRET.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
        String expected = "sha256=" + HexFormat.of().formatHex(mac.doFinal(payload));
        assertThat(signature).isEqualTo(expected);
    }

    private static void writeArtifact(
            Path output,
            gestudio.integraciones.jereplatform.application.SignedStudentSourceExportPage page
    ) throws Exception {
        String baseName = "page-%03d".formatted(page.pageNumber());
        Files.write(output.resolve(baseName + ".json"), page.payload());
        Files.writeString(
                output.resolve(baseName + ".signature"),
                page.signature(),
                StandardCharsets.US_ASCII
        );
    }

    private static String runtimeSecret() {
        String configured = System.getenv("GESTUDIO_SOURCE_EXPORT_SMOKE_SECRET");
        if (configured != null && !configured.isBlank()) {
            return configured;
        }
        byte[] bytes = new byte[32];
        new SecureRandom().nextBytes(bytes);
        return Base64.getEncoder().encodeToString(bytes);
    }

    private static void assertMinimalPayload(byte[] payload) {
        String json = new String(payload, StandardCharsets.UTF_8);
        assertThat(payload.length).isLessThanOrEqualTo(StudentSourceExportService.MAX_PAYLOAD_BYTES);
        assertThat(json).doesNotContain(
                "documento", "email", "celular", "fechaNacimiento", "nombrePadres",
                "autorizadoParaSalirSolo", "otrasNotas", "cuota", "responsable", "metadata");
    }
}
