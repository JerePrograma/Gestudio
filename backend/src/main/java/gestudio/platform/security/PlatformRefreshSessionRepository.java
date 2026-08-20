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
public class PlatformRefreshSessionRepository {
    private static final int EXPECTED_UPDATED_ROWS = 1;

    private final JdbcTemplate jdbc;

    public PlatformRefreshSessionRepository(@Qualifier("platformJdbcTemplate") JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public void insert(Session session) {
        jdbc.update("""
                INSERT INTO platform_refresh_sessions(
                    id, family_id, usuario_id, session_scope, token_hash, auth_version,
                    platform_security_version, mfa_verified_at, issued_at, expires_at,
                    family_expires_at, user_agent_hash, ip_hash)
                VALUES (?, ?, ?, 'PLATFORM', ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, session.id(), session.familyId(), session.userId(), session.tokenHash(),
                session.authVersion(), session.platformSecurityVersion(),
                Timestamp.from(session.mfaVerifiedAt()), Timestamp.from(session.issuedAt()),
                Timestamp.from(session.expiresAt()), Timestamp.from(session.familyExpiresAt()),
                session.userAgentHash(), session.ipHash());
    }

    public Optional<Session> lockByTokenHash(String hash) {
        return jdbc.query("""
                SELECT id, family_id, usuario_id, token_hash, auth_version,
                       platform_security_version, mfa_verified_at, issued_at, expires_at,
                       family_expires_at, used_at, revoked_at, replaced_by_id,
                       user_agent_hash, ip_hash
                FROM platform_refresh_sessions
                WHERE token_hash = ?
                FOR UPDATE
                """, PlatformRefreshSessionRepository::session, hash).stream().findFirst();
    }

    public void rotate(UUID oldId, UUID newId, Instant usedAt) {
        if (jdbc.update("""
                UPDATE platform_refresh_sessions
                SET used_at = ?, replaced_by_id = ?
                WHERE id = ? AND used_at IS NULL AND revoked_at IS NULL
                """, Timestamp.from(usedAt), newId, oldId) != EXPECTED_UPDATED_ROWS) {
            throw new IllegalStateException("La sesión refresh ya fue rotada");
        }
    }

    public int revokeFamily(UUID familyId, Instant now, String reason) {
        return jdbc.update("""
                UPDATE platform_refresh_sessions
                SET revoked_at = ?, revoke_reason = ?
                WHERE family_id = ? AND revoked_at IS NULL
                """, Timestamp.from(now), reason, familyId);
    }

    public int revokeUser(long userId, Instant now, String reason) {
        return jdbc.update("""
                UPDATE platform_refresh_sessions
                SET revoked_at = ?, revoke_reason = ?
                WHERE usuario_id = ? AND revoked_at IS NULL
                """, Timestamp.from(now), reason, userId);
    }

    private static Session session(ResultSet rs, int row) throws SQLException {
        return new Session((UUID) rs.getObject("id"), (UUID) rs.getObject("family_id"),
                rs.getLong("usuario_id"), rs.getString("token_hash"), rs.getLong("auth_version"),
                rs.getLong("platform_security_version"), rs.getTimestamp("mfa_verified_at").toInstant(),
                rs.getTimestamp("issued_at").toInstant(), rs.getTimestamp("expires_at").toInstant(),
                rs.getTimestamp("family_expires_at").toInstant(), timestamp(rs, "used_at"),
                timestamp(rs, "revoked_at"), (UUID) rs.getObject("replaced_by_id"),
                rs.getString("user_agent_hash"), rs.getString("ip_hash"));
    }

    private static Instant timestamp(ResultSet rs, String name) throws SQLException {
        var value = rs.getTimestamp(name);
        return value == null ? null : value.toInstant();
    }

    public record Session(UUID id, UUID familyId, long userId, String tokenHash,
                          long authVersion, long platformSecurityVersion, Instant mfaVerifiedAt,
                          Instant issuedAt, Instant expiresAt, Instant familyExpiresAt,
                          Instant usedAt, Instant revokedAt, UUID replacedById,
                          String userAgentHash, String ipHash) {
    }
}
