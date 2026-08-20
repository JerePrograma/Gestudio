package gestudio.platform.control;

import gestudio.infra.seguridad.InvalidTokenException;
import gestudio.infra.seguridad.PasswordPolicy;
import gestudio.platform.security.PlatformStepUpService;
import gestudio.platform.security.PlatformMfaService;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.time.Clock;
import java.time.Instant;
import java.util.UUID;

@Service
public class PlatformIdentityActivationService {
    private static final int EXPECTED_UPDATED_ROWS = 1;
    private static final String IDENTITY_ACTIVATION = "IDENTITY_ACTIVATION";

    private final JdbcTemplate jdbc;
    private final PasswordEncoder passwordEncoder;
    private final PasswordPolicy passwordPolicy;
    private final PlatformAuditService audit;
    private final PlatformMfaService mfa;
    private final Clock clock;
    private final TransactionTemplate transactions;

    public PlatformIdentityActivationService(
            @Qualifier("platformJdbcTemplate") JdbcTemplate jdbc,
            PasswordEncoder passwordEncoder, PasswordPolicy passwordPolicy,
            PlatformAuditService audit, PlatformMfaService mfa, Clock clock,
            @Qualifier("platformTransactionManager") PlatformTransactionManager manager) {
        this.jdbc = jdbc;
        this.passwordEncoder = passwordEncoder;
        this.passwordPolicy = passwordPolicy;
        this.audit = audit;
        this.mfa = mfa;
        this.clock = clock;
        this.transactions = new TransactionTemplate(manager);
    }

    public ActivationResult activate(String rawToken, String password, String totpSecret,
                                     String totpCode, UUID correlationId) {
        if (rawToken == null || rawToken.isBlank() || rawToken.length() > 256) {
            throw new InvalidTokenException();
        }
        String hash = PlatformStepUpService.hash(rawToken);
        ActivationResult result = transactions.execute(status -> activateLocked(
                hash, password, totpSecret, totpCode, correlationId));
        if (result == null) throw new IllegalStateException("Resultado de activación ausente");
        return result;
    }

    private ActivationResult activateLocked(String hash, String password, String totpSecret,
                                            String totpCode, UUID correlationId) {
        Activation activation = lockActivation(hash);
        validatePassword(activation, password);
        PlatformMfaService.ProvisionedMfa provisioned = provisionMfa(
                activation, totpSecret, totpCode);
        completeActivation(activation, password, correlationId);
        return new ActivationResult(recoveryCodes(provisioned));
    }

    private void validatePassword(Activation activation, String password) {
        if (isIdentityActivation(activation)) {
            passwordPolicy.validar(password, false);
        } else if (password != null && !password.isBlank()) {
            passwordPolicy.validar(password, true);
        }
    }

    private PlatformMfaService.ProvisionedMfa provisionMfa(
            Activation activation, String totpSecret, String totpCode) {
        return isIdentityActivation(activation)
                ? null : mfa.provisionInitial(activation.userId(), totpSecret, totpCode);
    }

    private static java.util.List<String> recoveryCodes(
            PlatformMfaService.ProvisionedMfa provisioned) {
        return provisioned == null ? java.util.List.of() : provisioned.recoveryCodes();
    }

    private Activation lockActivation(String hash) {
        Activation activation = jdbc.query("""
                SELECT a.id, a.usuario_id, a.purpose, a.expires_at, a.consumed_at,
                       u.nombre_usuario, u.activo
                FROM platform_identity_activations a
                JOIN usuarios u ON u.id = a.usuario_id
                WHERE a.token_hash = ?
                FOR UPDATE OF a, u
                """, PlatformIdentityActivationService::activation, hash).stream().findFirst()
                .orElseThrow(InvalidTokenException::new);
        Instant now = clock.instant();
        if (activation.consumedAt() != null || !activation.expiresAt().isAfter(now)) {
            throw new InvalidTokenException();
        }
        return activation;
    }

    private void completeActivation(Activation locked, String password, UUID correlationId) {
        Instant now = clock.instant();
        if (locked.consumedAt() != null || !locked.expiresAt().isAfter(now)) {
            throw new InvalidTokenException();
        }
        updateIdentity(locked, password, now);
        activatePlatformCapability(locked, now);
        consumeActivation(locked, now);
        audit.system(locked.userId(), locked.username(), activationAction(locked),
                "USUARIO", Long.toString(locked.userId()), correlationId);
    }

    private void updateIdentity(Activation locked, String password, Instant now) {
        if (isIdentityActivation(locked)) {
            if (jdbc.update("""
                UPDATE usuarios
                SET contrasena = ?, activo = TRUE, auth_version = auth_version + 1,
                    password_changed_at = ?, version = version + 1
                WHERE id = ?
                """, passwordEncoder.encode(password), Timestamp.from(now), locked.userId())
                    != EXPECTED_UPDATED_ROWS) {
                throw new IllegalStateException("No se pudo activar la identidad");
            }
        } else if (password != null && !password.isBlank()) {
            jdbc.update("""
                    UPDATE usuarios SET contrasena=?, activo=TRUE,
                        auth_version=auth_version+1, password_changed_at=?, version=version+1
                    WHERE id=?
                    """, passwordEncoder.encode(password), Timestamp.from(now), locked.userId());
        }
    }

    private void activatePlatformCapability(Activation locked, Instant now) {
        if (!isIdentityActivation(locked)) {
            if (jdbc.update("""
                    UPDATE platform_admins
                    SET active=TRUE, revoked_at=NULL,
                        security_version=security_version+1, updated_at=?
                    WHERE usuario_id=?
                    """, Timestamp.from(now), locked.userId()) != EXPECTED_UPDATED_ROWS) {
                throw new IllegalStateException("No se pudo activar la capacidad de plataforma");
            }
        }
    }

    private void consumeActivation(Activation locked, Instant now) {
        if (jdbc.update("""
                UPDATE platform_identity_activations SET consumed_at = ?
                WHERE id = ? AND consumed_at IS NULL
                """, Timestamp.from(now), locked.id()) != EXPECTED_UPDATED_ROWS) {
            throw new InvalidTokenException();
        }
    }

    private static String activationAction(Activation activation) {
        return isIdentityActivation(activation)
                ? "PLATFORM_IDENTITY_ACTIVATED" : "PLATFORM_MFA_ENROLLED";
    }

    private static boolean isIdentityActivation(Activation activation) {
        return IDENTITY_ACTIVATION.equals(activation.purpose());
    }

    private static Activation activation(ResultSet rs, int row) throws SQLException {
        var consumed = rs.getTimestamp("consumed_at");
        return new Activation((UUID) rs.getObject("id"), rs.getLong("usuario_id"),
                rs.getString("purpose"),
                rs.getTimestamp("expires_at").toInstant(),
                consumed == null ? null : consumed.toInstant(), rs.getString("nombre_usuario"),
                rs.getBoolean("activo"));
    }

    private record Activation(UUID id, long userId, String purpose, Instant expiresAt,
                              Instant consumedAt, String username, boolean userActive) {
    }

    public record ActivationResult(java.util.List<String> recoveryCodes) {
        public ActivationResult {
            recoveryCodes = java.util.List.copyOf(recoveryCodes);
        }
    }
}
