package gestudio.platform.security;

import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

@Repository
public class PlatformStepUpRepository {
    private final JdbcTemplate jdbc;

    public PlatformStepUpRepository(@Qualifier("platformJdbcTemplate") JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public Challenge createOrFind(Challenge challenge) {
        jdbc.update("""
                INSERT INTO platform_step_up_challenges(
                    id, usuario_id, session_id, action, target_type, target_id,
                    idempotency_key, correlation_id, mfa_method, issued_at, expires_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'TOTP', ?, ?)
                ON CONFLICT (session_id, action, target_type, target_id, idempotency_key)
                DO NOTHING
                """, challenge.id(), challenge.userId(), challenge.sessionId(), challenge.action(),
                challenge.targetType(), challenge.targetId(), challenge.idempotencyKey(),
                challenge.correlationId(), Timestamp.from(challenge.issuedAt()),
                Timestamp.from(challenge.expiresAt()));
        return findByBinding(challenge.userId(), challenge.sessionId(), challenge.action(),
                challenge.targetType(), challenge.targetId(), challenge.idempotencyKey())
                .orElseThrow(() -> new IllegalStateException("No se pudo persistir el desafío step-up"));
    }

    public Optional<Challenge> lockById(UUID challengeId, long userId, UUID sessionId) {
        return jdbc.query("""
                SELECT id, usuario_id, session_id, action, target_type, target_id,
                       idempotency_key, correlation_id, issued_at, expires_at,
                       proof_hash, verified_at, consumed_at
                FROM platform_step_up_challenges
                WHERE id = ? AND usuario_id = ? AND session_id = ?
                FOR UPDATE
                """, PlatformStepUpRepository::challenge, challengeId, userId, sessionId)
                .stream().findFirst();
    }

    public boolean verify(UUID challengeId, String proofHash, Instant verifiedAt) {
        return jdbc.update("""
                UPDATE platform_step_up_challenges
                SET proof_hash = ?, verified_at = ?
                WHERE id = ? AND proof_hash IS NULL AND verified_at IS NULL
                  AND consumed_at IS NULL AND expires_at >= ?
                """, proofHash, Timestamp.from(verifiedAt), challengeId,
                Timestamp.from(verifiedAt)) == 1;
    }

    public boolean consume(long userId, UUID sessionId, String action, String targetType,
                           String targetId, String idempotencyKey, String proofHash, Instant now) {
        return jdbc.update("""
                UPDATE platform_step_up_challenges
                SET consumed_at = ?
                WHERE usuario_id = ? AND session_id = ? AND action = ?
                  AND target_type IS NOT DISTINCT FROM ?
                  AND target_id IS NOT DISTINCT FROM ?
                  AND idempotency_key = ? AND proof_hash = ?
                  AND verified_at IS NOT NULL AND consumed_at IS NULL AND expires_at >= ?
                """, Timestamp.from(now), userId, sessionId, action, targetType, targetId,
                idempotencyKey, proofHash, Timestamp.from(now)) == 1;
    }

    private Optional<Challenge> findByBinding(long userId, UUID sessionId, String action,
                                               String targetType, String targetId,
                                               String idempotencyKey) {
        return jdbc.query("""
                SELECT id, usuario_id, session_id, action, target_type, target_id,
                       idempotency_key, correlation_id, issued_at, expires_at,
                       proof_hash, verified_at, consumed_at
                FROM platform_step_up_challenges
                WHERE usuario_id = ? AND session_id = ? AND action = ?
                  AND target_type IS NOT DISTINCT FROM ?
                  AND target_id IS NOT DISTINCT FROM ? AND idempotency_key = ?
                """, PlatformStepUpRepository::challenge, userId, sessionId, action,
                targetType, targetId, idempotencyKey).stream().findFirst();
    }

    private static Challenge challenge(ResultSet rs, int row) throws SQLException {
        return new Challenge((UUID) rs.getObject("id"), rs.getLong("usuario_id"),
                (UUID) rs.getObject("session_id"), rs.getString("action"),
                rs.getString("target_type"), rs.getString("target_id"),
                rs.getString("idempotency_key"), (UUID) rs.getObject("correlation_id"),
                rs.getTimestamp("issued_at").toInstant(), rs.getTimestamp("expires_at").toInstant(),
                rs.getString("proof_hash"), instant(rs, "verified_at"), instant(rs, "consumed_at"));
    }

    private static Instant instant(ResultSet rs, String column) throws SQLException {
        var value = rs.getTimestamp(column);
        return value == null ? null : value.toInstant();
    }

    public record Challenge(UUID id, long userId, UUID sessionId, String action,
                            String targetType, String targetId, String idempotencyKey,
                            UUID correlationId, Instant issuedAt, Instant expiresAt,
                            String proofHash, Instant verifiedAt, Instant consumedAt) {
    }
}
