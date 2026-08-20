package gestudio.infra.seguridad;

import gestudio.entidades.RolSistema;
import gestudio.platform.PlatformMetrics;
import gestudio.platform.control.PlatformAuditService;
import gestudio.platform.security.PlatformMfaService;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

import java.sql.Timestamp;
import java.time.Clock;
import java.util.Locale;
import java.util.UUID;
import java.util.function.Consumer;

@Service
public class SuperadminBootstrapService {
    static final String CLAIM = "SUPERADMIN_INICIAL";

    private final JdbcTemplate jdbc;
    private final PasswordEncoder passwordEncoder;
    private final PasswordPolicy passwordPolicy;
    private final PlatformMfaService mfa;
    private final PlatformAuditService audit;
    private final PlatformMetrics metrics;
    private final Clock clock;
    private final TransactionTemplate transactions;

    public SuperadminBootstrapService(
            @Qualifier("platformJdbcTemplate") JdbcTemplate jdbc,
            PasswordEncoder passwordEncoder, PasswordPolicy passwordPolicy,
            PlatformMfaService mfa, PlatformAuditService audit, PlatformMetrics metrics, Clock clock,
            @Qualifier("platformTransactionManager") PlatformTransactionManager manager) {
        this.jdbc = jdbc;
        this.passwordEncoder = passwordEncoder;
        this.passwordPolicy = passwordPolicy;
        this.mfa = mfa;
        this.audit = audit;
        this.metrics = metrics;
        this.clock = clock;
        this.transactions = new TransactionTemplate(manager);
    }

    public BootstrapResult bootstrap(String rawUsername, String password,
                                     String totpSecret, String currentTotpCode,
                                     Consumer<java.util.List<String>> recoveryCodeSink) {
        try {
            BootstrapResult result = bootstrapInternal(rawUsername, password, totpSecret,
                    currentTotpCode, recoveryCodeSink);
            metrics.bootstrap(PlatformMetrics.BootstrapResult.SUCCESS);
            return result;
        } catch (RuntimeException exception) {
            metrics.bootstrap(PlatformMetrics.BootstrapResult.FAILED);
            metrics.provisioningFailure(PlatformMetrics.ProvisioningResource.BOOTSTRAP,
                    bootstrapFailureReason(exception));
            throw exception;
        }
    }

    private BootstrapResult bootstrapInternal(String rawUsername, String password,
                                              String totpSecret, String currentTotpCode,
                                              Consumer<java.util.List<String>> recoveryCodeSink) {
        String username = normalizeUsername(rawUsername);
        try {
            passwordPolicy.validar(password, RolSistema.SUPERADMIN);
        } catch (IllegalArgumentException exception) {
            throw new IllegalStateException("APP_BOOTSTRAP_SUPERADMIN_PASSWORD: "
                    + exception.getMessage(), exception);
        }

        if (recoveryCodeSink == null) {
            throw new IllegalArgumentException("El destino seguro de recovery codes es obligatorio");
        }
        BootstrapResult result = transactions.execute(status -> {
            Created created = createClaimed(username, password);
            PlatformMfaService.ProvisionedMfa provisioned =
                    mfa.provisionInitial(created.userId(), totpSecret, currentTotpCode);
            // El archivo se materializa antes del commit: si no puede protegerse,
            // la misma transacción revierte identidad, capacidad y MFA.
            recoveryCodeSink.accept(provisioned.recoveryCodes());
            audit.bootstrap(created.userId(), username, UUID.randomUUID());
            jdbc.update("UPDATE bootstrap_ejecuciones SET usuario_id = ? WHERE tipo = ?",
                    created.userId(), CLAIM);
            return new BootstrapResult(created.userId(), username);
        });
        if (result == null) throw new IllegalStateException("Resultado bootstrap ausente");
        return result;
    }

    private static PlatformMetrics.ProvisioningFailureReason bootstrapFailureReason(
            RuntimeException exception) {
        if (exception instanceof BootstrapConfigurationException
                || exception instanceof IllegalArgumentException
                || exception.getCause() instanceof IllegalArgumentException) {
            return PlatformMetrics.ProvisioningFailureReason.INVALID_REQUEST;
        }
        return PlatformMetrics.ProvisioningFailureReason.INTERNAL;
    }

    private Created createClaimed(String username, String password) {
        if (jdbc.update("""
                INSERT INTO bootstrap_ejecuciones(tipo)
                VALUES (?) ON CONFLICT (tipo) DO NOTHING
                """, CLAIM) != 1) {
            throw new IllegalStateException(
                    "El bootstrap SUPERADMIN ya fue ejecutado; deshabilite la bandera");
        }
        if (jdbc.queryForObject("SELECT count(*) FROM platform_admins", Integer.class) != 0) {
            throw new IllegalStateException(
                    "La plataforma ya posee administradores; el bootstrap inicial se rechaza");
        }
        if (jdbc.queryForObject("SELECT count(*) FROM usuarios WHERE lower(nombre_usuario)=lower(?)",
                Integer.class, username) != 0) {
            throw new IllegalStateException("El username del bootstrap ya existe");
        }
        Timestamp now = Timestamp.from(clock.instant());
        Long userId = jdbc.queryForObject("""
                INSERT INTO usuarios(nombre_usuario, contrasena, rol_id, activo,
                                     auth_version, password_changed_at, version)
                VALUES (?, ?, NULL, TRUE, 0, ?, 0)
                RETURNING id
                """, Long.class, username, passwordEncoder.encode(password), now);
        if (userId == null) throw new IllegalStateException("No se pudo crear la identidad bootstrap");
        jdbc.update("""
                INSERT INTO platform_admins(
                    usuario_id, active, granted_at, granted_by_usuario_id,
                    security_version, mfa_required, updated_at)
                VALUES (?, TRUE, ?, ?, 0, TRUE, ?)
                """, userId, now, userId, now);
        return new Created(userId);
    }

    private static String normalizeUsername(String username) {
        String normalized = username == null ? "" : username.trim();
        if (normalized.length() < 3 || normalized.length() > 100
                || !normalized.matches("^[A-Za-z0-9._@+-]+$")
                || normalized.toLowerCase(Locale.ROOT).contains("password")) {
            throw new BootstrapConfigurationException(
                    "APP_BOOTSTRAP_SUPERADMIN_USERNAME debe ser un identificador válido de 3 a 100 caracteres");
        }
        return normalized;
    }

    private record Created(long userId) {
    }

    private static final class BootstrapConfigurationException extends IllegalStateException {
        private static final long serialVersionUID = 1L;

        private BootstrapConfigurationException(String message) {
            super(message);
        }
    }

    public record BootstrapResult(long userId, String username) {
    }
}
