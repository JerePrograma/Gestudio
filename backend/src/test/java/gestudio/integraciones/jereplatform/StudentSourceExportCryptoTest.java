package gestudio.integraciones.jereplatform;

import com.fasterxml.jackson.databind.ObjectMapper;
import gestudio.integraciones.jereplatform.application.StudentSourceExport;
import gestudio.integraciones.jereplatform.application.StudentSourceExportException;
import gestudio.integraciones.jereplatform.infrastructure.StudentSourceExportProperties;
import gestudio.integraciones.jereplatform.infrastructure.StudentSourceExportSerializer;
import gestudio.integraciones.jereplatform.infrastructure.StudentSourceExportSigner;
import org.junit.jupiter.api.Test;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.Base64;
import java.util.HexFormat;
import java.util.List;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class StudentSourceExportCryptoTest {
    private static final String SECRET = runtimeSecret();
    private static final String EXPECTED_JSON = """
            {"contractVersion":1,"tenantId":"00000000-0000-0000-0000-000000000001","sourceType":"GESTUDIO_STUDENT","checkpoint":"00000000-0000-0000-0000-000000000002","nextCursor":null,"pageNumber":1,"pageCount":1,"fullSnapshot":true,"records":[{"sourceId":"42","displayName":"Synthetic Student","active":true}]}
            """.strip();

    @Test
    void serializaUnaVezConCamposMinimosYFirmaLosMismosBytes() throws Exception {
        var serializer = new StudentSourceExportSerializer(new ObjectMapper());
        var signer = new StudentSourceExportSigner(properties(SECRET));
        var export = new StudentSourceExport(
                1,
                UUID.fromString("00000000-0000-0000-0000-000000000001"),
                "GESTUDIO_STUDENT",
                "00000000-0000-0000-0000-000000000002",
                null,
                1,
                1,
                true,
                List.of(new StudentSourceExport.StudentReference(
                        "42", "Synthetic Student", true))
        );

        byte[] payload = serializer.serialize(export);
        String json = new String(payload, StandardCharsets.UTF_8);

        assertThat(json).isEqualTo(EXPECTED_JSON);
        assertThat(signer.sign(payload)).isEqualTo(independentSignature(payload));
        assertThat(signer.sign((json + " ").getBytes(StandardCharsets.UTF_8)))
                .isNotEqualTo(signer.sign(payload));

        var root = new ObjectMapper().readTree(payload);
        assertThat(fieldNames(root)).containsExactlyInAnyOrder(
                "contractVersion", "tenantId", "sourceType", "checkpoint", "nextCursor",
                "pageNumber", "pageCount", "fullSnapshot", "records");
        assertThat(fieldNames(root.path("records").get(0))).containsExactlyInAnyOrder(
                "sourceId", "displayName", "active");
        assertThat(json).doesNotContain(
                "documento", "email", "celular", "fechaNacimiento", "nombrePadres",
                "responsable", "cuota", "metadata");
    }

    @Test
    void rechazaSecretoAusenteOCorto() {
        assertThatThrownBy(() -> new StudentSourceExportSigner(properties("")).requireConfigured())
                .isInstanceOf(StudentSourceExportException.class)
                .extracting(error -> ((StudentSourceExportException) error).code())
                .isEqualTo(StudentSourceExportException.Code.SOURCE_SECRET_MISSING);
        assertThatThrownBy(() -> new StudentSourceExportSigner(properties("short")).requireConfigured())
                .isInstanceOf(StudentSourceExportException.class)
                .extracting(error -> ((StudentSourceExportException) error).code())
                .isEqualTo(StudentSourceExportException.Code.SOURCE_SECRET_TOO_SHORT);
    }

    private static StudentSourceExportProperties properties(String secret) {
        return new StudentSourceExportProperties(
                true,
                "synthetic-academy",
                "00000000-0000-0000-0000-000000000001",
                secret,
                1_000
        );
    }

    private static String independentSignature(byte[] payload) throws Exception {
        Mac mac = Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(SECRET.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
        return "sha256=" + HexFormat.of().formatHex(mac.doFinal(payload));
    }

    private static String runtimeSecret() {
        byte[] bytes = new byte[32];
        new SecureRandom().nextBytes(bytes);
        return Base64.getEncoder().encodeToString(bytes);
    }

    private static Set<String> fieldNames(com.fasterxml.jackson.databind.JsonNode node) {
        Set<String> fields = new java.util.HashSet<>();
        node.fieldNames().forEachRemaining(fields::add);
        return fields;
    }
}
