package gestudio.platform.security;

import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

@Repository
public class PlatformIdentityRepository {
    private static final int EXPECTED_UPDATED_ROWS = 1;

    private final JdbcTemplate jdbc;

    public PlatformIdentityRepository(@Qualifier("platformJdbcTemplate") JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public Optional<Identity> findActiveByUsername(String username) {
        return jdbc.query("""
                SELECT u.id, u.nombre_usuario, u.contrasena, u.activo, u.auth_version,
                       pa.security_version, pa.active, pa.mfa_required
                FROM usuarios u
                JOIN platform_admins pa ON pa.usuario_id = u.id
                WHERE lower(u.nombre_usuario) = lower(?)
                """, PlatformIdentityRepository::identity, username).stream()
                .filter(value -> value.userActive() && value.platformActive())
                .findFirst();
    }

    public Optional<Identity> findActiveById(long userId) {
        return jdbc.query("""
                SELECT u.id, u.nombre_usuario, u.contrasena, u.activo, u.auth_version,
                       pa.security_version, pa.active, pa.mfa_required
                FROM usuarios u
                JOIN platform_admins pa ON pa.usuario_id = u.id
                WHERE u.id = ?
                """, PlatformIdentityRepository::identity, userId).stream()
                .filter(value -> value.userActive() && value.platformActive())
                .findFirst();
    }

    public Optional<MfaCredential> lockActiveMfa(long userId) {
        return jdbc.query("""
                SELECT id, usuario_id, secret_ciphertext, key_version, verified_at, last_counter,
                       failed_attempts, failure_window_started_at, blocked_until
                FROM platform_mfa_credentials
                WHERE usuario_id = ? AND verified_at IS NOT NULL AND revoked_at IS NULL
                FOR UPDATE
                """, PlatformIdentityRepository::mfaCredential, userId).stream().findFirst();
    }

    public void mfaSucceeded(UUID credentialId, long counter, Instant now) {
        int updated = jdbc.update("""
                UPDATE platform_mfa_credentials
                SET last_counter = ?, last_used_at = ?, failed_attempts = 0,
                    failure_window_started_at = NULL, blocked_until = NULL
                WHERE id = ? AND (last_counter IS NULL OR last_counter < ?)
                """, counter, Timestamp.from(now), credentialId, counter);
        if (updated != EXPECTED_UPDATED_ROWS) {
            throw new IllegalStateException("El código MFA ya fue consumido");
        }
    }

    public void mfaFailed(UUID credentialId, short attempts, Instant windowStartedAt, Instant blockedUntil) {
        jdbc.update("""
                UPDATE platform_mfa_credentials
                SET failed_attempts = ?, failure_window_started_at = ?, blocked_until = ?
                WHERE id = ?
                """, attempts, sqlTimestamp(windowStartedAt), sqlTimestamp(blockedUntil), credentialId);
    }

    public boolean consumeRecoveryCode(long userId, String codeHash, Instant now) {
        return jdbc.update("""
                UPDATE platform_recovery_codes rc
                SET used_at = ?
                FROM platform_mfa_credentials mc
                WHERE rc.credential_id = mc.id
                  AND mc.usuario_id = ? AND mc.verified_at IS NOT NULL AND mc.revoked_at IS NULL
                  AND rc.code_hash = ? AND rc.used_at IS NULL
                """, Timestamp.from(now), userId, codeHash) == 1;
    }

    public UUID insertInitialMfa(long userId, byte[] ciphertext, int keyVersion,
                                 Instant verifiedAt, long counter) {
        UUID id = UUID.randomUUID();
        jdbc.update("""
                INSERT INTO platform_mfa_credentials(
                    id, usuario_id, method, secret_ciphertext, key_version, verified_at,
                    last_used_at, last_counter)
                VALUES (?, ?, 'TOTP', ?, ?, ?, ?, ?)
                """, id, userId, ciphertext, keyVersion, Timestamp.from(verifiedAt),
                Timestamp.from(verifiedAt), counter);
        return id;
    }

    public void insertRecoveryCodes(UUID credentialId, List<String> hashes) {
        jdbc.batchUpdate("""
                INSERT INTO platform_recovery_codes(id, credential_id, code_hash)
                VALUES (?, ?, ?)
                """, hashes, hashes.size(), (statement, hash) -> {
            statement.setObject(1, UUID.randomUUID());
            statement.setObject(2, credentialId);
            statement.setString(3, hash);
        });
    }

    private static Identity identity(ResultSet rs, int row) throws SQLException {
        return new Identity(rs.getLong("id"), rs.getString("nombre_usuario"),
                rs.getString("contrasena"), rs.getBoolean("activo"), rs.getLong("auth_version"),
                rs.getLong("security_version"), rs.getBoolean("active"), rs.getBoolean("mfa_required"));
    }

    private static MfaCredential mfaCredential(ResultSet rs, int row) throws SQLException {
        return new MfaCredential((UUID) rs.getObject("id"), rs.getLong("usuario_id"),
                rs.getBytes("secret_ciphertext"), rs.getShort("key_version"),
                rs.getTimestamp("verified_at").toInstant(), (Long) rs.getObject("last_counter"),
                rs.getShort("failed_attempts"), timestamp(rs, "failure_window_started_at"),
                timestamp(rs, "blocked_until"));
    }

    private static Instant timestamp(ResultSet rs, String name) throws SQLException {
        var value = rs.getTimestamp(name);
        return value == null ? null : value.toInstant();
    }

    private static Timestamp sqlTimestamp(Instant value) {
        return value == null ? null : Timestamp.from(value);
    }

    public record Identity(long userId, String username, String passwordHash, boolean userActive,
                           long authVersion, long platformSecurityVersion,
                           boolean platformActive, boolean mfaRequired) {
    }

    public record MfaCredential(UUID id, long userId, byte[] ciphertext, short keyVersion,
                                Instant verifiedAt, Long lastCounter, short failedAttempts,
                                Instant failureWindowStartedAt, Instant blockedUntil) {
        public MfaCredential {
            ciphertext = ciphertext.clone();
        }

        @Override
        public byte[] ciphertext() {
            return ciphertext.clone();
        }
    }
}
