package gestudio.platform.control;

import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.time.Clock;
import java.time.Instant;

@Repository
public class PlatformIdempotencyRepository {
    private static final int EXPECTED_UPDATED_ROWS = 1;

    private final JdbcTemplate jdbc;
    private final Clock clock;

    public PlatformIdempotencyRepository(@Qualifier("platformJdbcTemplate") JdbcTemplate jdbc,
                                         Clock clock) {
        this.jdbc = jdbc;
        this.clock = clock;
    }

    public Claim claim(String operation, String key, long actorId, String requestHash) {
        Instant now = clock.instant();
        int inserted = jdbc.update("""
                INSERT INTO platform_idempotency_keys(
                    operation, idempotency_key, actor_usuario_id, request_hash,
                    status, created_at, updated_at)
                VALUES (?, ?, ?, ?, 'PENDING', ?, ?)
                ON CONFLICT (operation, idempotency_key) DO NOTHING
                """, operation, key, actorId, requestHash,
                Timestamp.from(now), Timestamp.from(now));
        Claim claim = jdbc.query("""
                SELECT operation, idempotency_key, actor_usuario_id, request_hash, status,
                       resource_type, resource_id, response_status,
                       result_reference::text AS result_reference
                FROM platform_idempotency_keys
                WHERE operation = ? AND idempotency_key = ?
                FOR UPDATE
                """, PlatformIdempotencyRepository::claim, operation, key).stream().findFirst()
                .orElseThrow(() -> new IllegalStateException("No se pudo reclamar la clave de idempotencia"));
        return claim.withCreated(inserted == 1);
    }

    public void succeeded(String operation, String key, String resourceType, String resourceId,
                          int responseStatus, String resultReferenceJson) {
        Instant now = clock.instant();
        if (jdbc.update("""
                UPDATE platform_idempotency_keys
                SET status = 'SUCCEEDED', resource_type = ?, resource_id = ?,
                    response_status = ?, result_reference = CAST(? AS jsonb),
                    updated_at = ?, completed_at = ?
                WHERE operation = ? AND idempotency_key = ? AND status = 'PENDING'
                """, resourceType, resourceId, responseStatus, resultReferenceJson,
                Timestamp.from(now), Timestamp.from(now), operation, key) != EXPECTED_UPDATED_ROWS) {
            throw new IllegalStateException("No se pudo completar la clave de idempotencia");
        }
    }

    private static Claim claim(ResultSet rs, int row) throws SQLException {
        return new Claim(rs.getString("operation"), rs.getString("idempotency_key"),
                rs.getLong("actor_usuario_id"), rs.getString("request_hash"),
                rs.getString("status"), rs.getString("resource_type"),
                rs.getString("resource_id"), (Integer) rs.getObject("response_status"),
                rs.getString("result_reference"), false);
    }

    public record Claim(String operation, String key, long actorId, String requestHash,
                        String status, String resourceType, String resourceId,
                        Integer responseStatus, String resultReferenceJson, boolean created) {
        Claim withCreated(boolean value) {
            return new Claim(operation, key, actorId, requestHash, status, resourceType,
                    resourceId, responseStatus, resultReferenceJson, value);
        }

        public boolean succeeded() {
            return "SUCCEEDED".equals(status);
        }
    }
}
