package gestudio.infra.idempotencia;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

@Service
public class IdempotencyLockService {

    private final JdbcTemplate jdbc;

    public IdempotencyLockService(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public void lock(String operacion, String idempotencyKey) {
        if (operacion == null || operacion.isBlank()) {
            throw new IllegalArgumentException("La operación de idempotencia es requerida");
        }

        if (idempotencyKey == null || idempotencyKey.isBlank()) {
            throw new IllegalArgumentException("La idempotency key es requerida");
        }

        jdbc.query(
                "SELECT pg_advisory_xact_lock(hashtextextended(?, 0))",
                ps -> ps.setString(1, operacion + ":" + idempotencyKey),
                rs -> null
        );
    }
}