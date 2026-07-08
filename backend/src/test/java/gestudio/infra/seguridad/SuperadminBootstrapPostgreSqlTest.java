package gestudio.infra.seguridad;

import gestudio.infra.persistencia.PostgreSqlIntegrationTest;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.Timeout;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.List;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.NONE)
class SuperadminBootstrapPostgreSqlTest extends PostgreSqlIntegrationTest {

    @Autowired private SuperadminBootstrapService bootstrap;
    @Autowired private JdbcTemplate jdbc;

    @Test
    @Timeout(40)
    void claimTransaccionalCreaUnSoloSuperadminYAuditaSinSecretos() throws Exception {
        String suffix = UUID.randomUUID().toString();
        Long role = jdbc.queryForObject("SELECT id FROM roles WHERE descripcion = 'SUPERADMIN'", Long.class);
        String existente = "existente-" + suffix;
        jdbc.update("""
                INSERT INTO usuarios(nombre_usuario, contrasena, rol_id, activo)
                VALUES (?, 'hash', ?, true)
                """, existente, role);

        assertThatThrownBy(() -> bootstrap.bootstrap(existente.toUpperCase(), "clave-superadmin-segura"))
                .isInstanceOf(IllegalStateException.class).hasMessageContaining("ya existe");
        assertThat(claims()).isZero();
        jdbc.update("DELETE FROM usuarios WHERE nombre_usuario = ?", existente);

        assertThatThrownBy(() -> bootstrap.bootstrap("root-" + suffix, "corta"))
                .isInstanceOf(IllegalStateException.class).hasMessageContaining("16 y 72");
        assertThat(claims()).isZero();

        CountDownLatch start = new CountDownLatch(1);
        ExecutorService executor = Executors.newFixedThreadPool(2);
        Future<Object> first = executor.submit(() -> ejecutar(start, "root-a-" + suffix));
        Future<Object> second = executor.submit(() -> ejecutar(start, "root-b-" + suffix));
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

        assertThat(claims()).isOne();
        assertThat(jdbc.queryForObject("""
                SELECT count(*) FROM usuarios u JOIN roles r ON r.id = u.rol_id
                WHERE u.nombre_usuario IN (?, ?) AND r.descripcion = 'SUPERADMIN' AND u.activo = true
                """, Integer.class, "root-a-" + suffix, "root-b-" + suffix)).isOne();
        assertThat(jdbc.queryForObject("""
                SELECT count(*) FROM usuarios u
                JOIN usuario_roles ur ON ur.usuario_id = u.id
                JOIN roles r ON r.id = ur.rol_id
                WHERE u.nombre_usuario IN (?, ?) AND r.codigo = 'SUPERADMIN'
                """, Integer.class, "root-a-" + suffix, "root-b-" + suffix)).isOne();
        assertThat(jdbc.queryForObject("""
                SELECT count(*) FROM auditoria_eventos
                WHERE accion = 'SUPERADMIN_BOOTSTRAP' AND metadata::text NOT LIKE '%clave-superadmin-segura%'
                """, Integer.class)).isOne();
        assertThatThrownBy(() -> bootstrap.bootstrap("otro-" + suffix, "clave-superadmin-segura"))
                .isInstanceOf(IllegalStateException.class).hasMessageContaining("deshabilite");
    }

    private Object ejecutar(CountDownLatch start, String username) {
        try {
            if (!start.await(5, TimeUnit.SECONDS)) throw new IllegalStateException("Timeout de inicio");
            return bootstrap.bootstrap(username, "clave-superadmin-segura").getId();
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
}
