package gestudio.infra.seguridad;

import com.fasterxml.jackson.databind.ObjectMapper;
import gestudio.infra.persistencia.PostgreSqlIntegrationTest;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.Timeout;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.web.servlet.MockMvc;

import java.util.List;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
class SuperadminBootstrapPostgreSqlTest extends PostgreSqlIntegrationTest {

    private static final String PASSWORD = "clave-superadmin-segura";

    @Autowired private SuperadminBootstrapService bootstrap;
    @Autowired private JdbcTemplate jdbc;
    @Autowired private MockMvc mockMvc;
    @Autowired private ObjectMapper objectMapper;
    @Autowired private PasswordEncoder passwordEncoder;

    @Test
    @Timeout(40)
    void claimTransaccionalCreaUnSoloSuperadminPermiteLoginYAuditaSinSecretos() throws Exception {
        String suffix = UUID.randomUUID().toString();

        jdbc.update("""
                DELETE FROM rol_permisos rp
                USING roles r, permisos p
                WHERE rp.rol_id = r.id AND rp.permiso_id = p.id
                  AND r.codigo = 'SUPERADMIN' AND p.codigo = 'PERM_APP_ACCESO'
                """);
        assertThatThrownBy(() -> bootstrap.bootstrap("bootstrap-test-matriz-" + suffix, PASSWORD))
                .isInstanceOf(IllegalStateException.class)
                .hasMessage("La matriz obligatoria del rol SUPERADMIN no está disponible");
        assertThat(claims()).isZero();
        assertThat(usuariosBootstrap()).isZero();
        jdbc.update("""
                INSERT INTO rol_permisos (rol_id, permiso_id)
                SELECT r.id, p.id FROM roles r CROSS JOIN permisos p
                WHERE r.codigo = 'SUPERADMIN' AND p.codigo = 'PERM_APP_ACCESO'
                """);

        jdbc.update("UPDATE roles SET activo = FALSE WHERE codigo = 'SUPERADMIN'");
        assertThatThrownBy(() -> bootstrap.bootstrap("bootstrap-test-inactivo-" + suffix, PASSWORD))
                .isInstanceOf(IllegalStateException.class)
                .hasMessage("El rol SUPERADMIN no está disponible");
        assertThat(claims()).isZero();
        assertThat(usuariosBootstrap()).isZero();
        jdbc.update("UPDATE roles SET activo = TRUE WHERE codigo = 'SUPERADMIN'");

        Long role = jdbc.queryForObject("SELECT id FROM roles WHERE codigo = 'SUPERADMIN'", Long.class);
        String existente = "bootstrap-test-existente-" + suffix;
        jdbc.update("""
                INSERT INTO usuarios(nombre_usuario, contrasena, rol_id, activo)
                VALUES (?, 'hash', ?, true)
                """, existente, role);

        assertThatThrownBy(() -> bootstrap.bootstrap(existente.toUpperCase(), PASSWORD))
                .isInstanceOf(IllegalStateException.class).hasMessageContaining("ya existe");
        assertThat(claims()).isZero();
        jdbc.update("DELETE FROM usuarios WHERE nombre_usuario = ?", existente);

        assertThatThrownBy(() -> bootstrap.bootstrap("bootstrap-test-corta-" + suffix, "corta"))
                .isInstanceOf(IllegalStateException.class).hasMessageContaining("16 y 72");
        assertThat(claims()).isZero();

        CountDownLatch start = new CountDownLatch(1);
        ExecutorService executor = Executors.newFixedThreadPool(2);
        Future<Object> first = executor.submit(() -> ejecutar(start, "bootstrap-test-a-" + suffix));
        Future<Object> second = executor.submit(() -> ejecutar(start, "bootstrap-test-b-" + suffix));
        try {
            start.countDown();
            List<Object> resultados = List.of(first.get(20, TimeUnit.SECONDS), second.get(20, TimeUnit.SECONDS));
            assertThat(resultados.stream().filter(Long.class::isInstance)).hasSize(1);
            assertThat(resultados.stream().filter(IllegalStateException.class::isInstance)).hasSize(1);
        } finally {
            start.countDown();
            executor.shutdownNow();
            assertThat(executor.awaitTermination(5, TimeUnit.SECONDS)).isTrue();
        }

        String username = jdbc.queryForObject("""
                SELECT nombre_usuario FROM usuarios
                WHERE nombre_usuario IN (?, ?)
                """, String.class, "bootstrap-test-a-" + suffix, "bootstrap-test-b-" + suffix);

        assertThat(claims()).isOne();
        assertThat(jdbc.queryForObject("""
                SELECT count(*) FROM usuarios u JOIN roles r ON r.id = u.rol_id
                WHERE u.nombre_usuario = ? AND r.codigo = 'SUPERADMIN' AND u.activo = true
                """, Integer.class, username)).isOne();
        assertThat(jdbc.queryForObject("""
                SELECT count(*) FROM usuarios u
                JOIN usuario_roles ur ON ur.usuario_id = u.id
                JOIN roles r ON r.id = ur.rol_id
                WHERE u.nombre_usuario = ? AND r.codigo = 'SUPERADMIN'
                """, Integer.class, username)).isOne();

        String storedPassword = jdbc.queryForObject(
                "SELECT contrasena FROM usuarios WHERE nombre_usuario = ?", String.class, username);
        Long usuarioId = jdbc.queryForObject(
                "SELECT id FROM usuarios WHERE nombre_usuario = ?", Long.class, username);
        assertThat(storedPassword).isNotEqualTo(PASSWORD);
        assertThat(passwordEncoder.matches(PASSWORD, storedPassword)).isTrue();
        assertThat(jdbc.queryForObject("""
                SELECT count(*) FROM auditoria_eventos
                WHERE accion = 'SUPERADMIN_BOOTSTRAP'
                  AND entidad_id = ?
                  AND COALESCE(metadata::text, '') NOT LIKE ?
                  AND COALESCE(estado_nuevo::text, '') NOT LIKE ?
                """, Integer.class, usuarioId.toString(),
                "%" + PASSWORD + "%", "%" + PASSWORD + "%")).isOne();

        assertThatThrownBy(() -> bootstrap.bootstrap("bootstrap-test-otro-" + suffix, PASSWORD))
                .isInstanceOf(IllegalStateException.class).hasMessageContaining("deshabilite");
        assertThat(usuariosBootstrap()).isOne();

        String loginBody = objectMapper.writeValueAsString(new LoginPayload(username, PASSWORD));
        String loginResponse = mockMvc.perform(post("/api/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(loginBody))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.accessToken").isString())
                .andReturn().getResponse().getContentAsString();
        String accessToken = objectMapper.readTree(loginResponse).path("accessToken").asText();

        mockMvc.perform(get("/api/usuarios/perfil")
                        .header("Authorization", "Bearer " + accessToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.nombreUsuario").value(username))
                .andExpect(jsonPath("$.permisos.length()").value(32));

        mockMvc.perform(get("/api/salones")
                        .header("Authorization", "Bearer " + accessToken))
                .andExpect(status().isOk());
    }

    private Object ejecutar(CountDownLatch start, String username) {
        try {
            if (!start.await(5, TimeUnit.SECONDS)) throw new IllegalStateException("Timeout de inicio");
            return bootstrap.bootstrap(username, PASSWORD).getId();
        } catch (IllegalStateException e) {
            return e;
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return e;
        }
    }

    private int claims() {
        return jdbc.queryForObject("SELECT count(*) FROM bootstrap_ejecuciones WHERE tipo = 'SUPERADMIN_INICIAL'",
                Integer.class);
    }

    private int usuariosBootstrap() {
        return jdbc.queryForObject(
                "SELECT count(*) FROM usuarios WHERE nombre_usuario LIKE 'bootstrap-test-%'", Integer.class);
    }

    private record LoginPayload(String nombreUsuario, String contrasena) {
    }
}
