package ledance.auditoria;

import ledance.auditoria.application.AuditService;
import ledance.infra.persistencia.PostgreSqlIntegrationTest;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.dao.DataAccessException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

import java.util.Map;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.NONE)
class AuditServicePostgreSqlTest extends PostgreSqlIntegrationTest {
    @Autowired private AuditService audit;
    @Autowired private JdbcTemplate jdbc;
    @Autowired private PlatformTransactionManager transactionManager;

    @Test
    void participaDeLaTransaccionYElRollbackNoDejaEvento() {
        String key = "audit-rollback:" + UUID.randomUUID();

        new TransactionTemplate(transactionManager).executeWithoutResult(status -> {
            audit.registrar("SISTEMA", "PRUEBA_ROLLBACK", "PRUEBA", "1", null, key, Map.of());
            status.setRollbackOnly();
        });

        assertThat(count(key)).isZero();
    }

    @Test
    void esAppendOnlyEIdempotenteEnPostgreSql() {
        String key = "audit-append:" + UUID.randomUUID();
        audit.registrar("SISTEMA", "PRUEBA_APPEND", "PRUEBA", "2", null, key,
                Map.of("resultado", "OK"));
        Long id = jdbc.queryForObject("SELECT id FROM auditoria_eventos WHERE idempotency_key = ?",
                Long.class, key);

        assertThatThrownBy(() -> jdbc.update(
                "UPDATE auditoria_eventos SET accion = 'ALTERADO' WHERE id = ?", id))
                .isInstanceOf(DataAccessException.class)
                .hasMessageContaining("append-only");
        assertThatThrownBy(() -> jdbc.update("DELETE FROM auditoria_eventos WHERE id = ?", id))
                .isInstanceOf(DataAccessException.class)
                .hasMessageContaining("append-only");
        assertThatThrownBy(() -> audit.registrar(
                "SISTEMA", "DUPLICADO", "PRUEBA", "2", null, key, Map.of()))
                .isInstanceOf(DataAccessException.class);
        assertThat(count(key)).isOne();
    }

    @Test
    void rechazaSecretosAntesDePersistir() {
        String key = "audit-secret:" + UUID.randomUUID();

        assertThatThrownBy(() -> audit.registrar("SEGURIDAD", "PRUEBA_SECRETO", null, null,
                null, key, Map.of("refreshToken", "no-debe-persistirse")))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("no admite secretos");
        assertThat(count(key)).isZero();
    }

    @Test
    void rechazaSecretosTambienPorValorEscalarBajoClavesInocuas() {
        List<String> secrets = List.of(
                "Bearer eyJhbGciOiJIUzI1NiJ9.payload.signature",
                "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJhZG1pbiJ9.signature",
                "password=no-debe-persistirse",
                "client_secret=no-debe-persistirse",
                "authorization: Basic no-debe-persistirse",
                "token=no-debe-persistirse",
                "jwt=no-debe-persistirse",
                "SECRET_VALUE");

        secrets.forEach(secret -> {
            String key = "audit-secret-value:" + UUID.randomUUID();
            assertThatThrownBy(() -> audit.registrar("SEGURIDAD", "PRUEBA_SECRETO", null, null,
                    null, key, Map.of("detalle", secret)))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessage("La auditoría no admite secretos");
            assertThat(count(key)).isZero();
        });
    }

    @Test
    void conservaClasificacionesLegitimasNoSensibles() {
        String key = "audit-classification:" + UUID.randomUUID();

        audit.registrar("SEGURIDAD", "PRUEBA_CLASIFICACION", null, null,
                null, key, Map.of("motivo", "TOKEN_INVALIDO"));

        assertThat(count(key)).isOne();
    }

    @Test
    void rechazaSecretosEnEstadosAnteriorYNuevo() {
        String previousKey = "audit-secret-previous:" + UUID.randomUUID();
        assertThatThrownBy(() -> audit.registrar("SEGURIDAD", "PRUEBA_SECRETO", null, null,
                null, UUID.randomUUID(), previousKey,
                Map.of("detalle", "password=no-debe-persistirse"), Map.of(), Map.of()))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessage("La auditoría no admite secretos");
        assertThat(count(previousKey)).isZero();

        String newKey = "audit-secret-new:" + UUID.randomUUID();
        assertThatThrownBy(() -> audit.registrar("SEGURIDAD", "PRUEBA_SECRETO", null, null,
                null, UUID.randomUUID(), newKey,
                Map.of(), Map.of("detalle", "token=no-debe-persistirse"), Map.of()))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessage("La auditoría no admite secretos");
        assertThat(count(newKey)).isZero();
    }

    private int count(String key) {
        return jdbc.queryForObject("SELECT count(*) FROM auditoria_eventos WHERE idempotency_key = ?",
                Integer.class, key);
    }
}
