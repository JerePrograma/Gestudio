package gestudio.infra.seguridad;

import gestudio.auditoria.application.AuditService;
import gestudio.entidades.RolSistema;
import gestudio.entidades.Usuario;
import gestudio.repositorios.UsuarioRepositorio;
import gestudio.tenancy.TenantContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Profile;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

import java.time.Clock;
import java.util.Map;
import java.util.UUID;

@Component
@Profile("dev")
@ConditionalOnProperty(name = "app.local-admin-password-reset.enabled", havingValue = "true")
public class LocalAdminPasswordResetRunner implements ApplicationRunner {
    private static final Logger log = LoggerFactory.getLogger(LocalAdminPasswordResetRunner.class);
    private static final UUID INITIAL_TENANT_ID =
            UUID.fromString("00000000-0000-0000-0000-000000000001");

    private final LocalAdminPasswordResetProperties properties;
    private final UsuarioRepositorio usuarios;
    private final PasswordEncoder passwordEncoder;
    private final PasswordPolicy passwordPolicy;
    private final AuditService audit;
    private final Clock clock;
    private final TransactionTemplate transactions;

    public LocalAdminPasswordResetRunner(LocalAdminPasswordResetProperties properties,
                                         UsuarioRepositorio usuarios,
                                         PasswordEncoder passwordEncoder,
                                         PasswordPolicy passwordPolicy,
                                         AuditService audit,
                                         Clock clock,
                                         PlatformTransactionManager transactionManager) {
        this.properties = properties;
        this.usuarios = usuarios;
        this.passwordEncoder = passwordEncoder;
        this.passwordPolicy = passwordPolicy;
        this.audit = audit;
        this.clock = clock;
        this.transactions = new TransactionTemplate(transactionManager);
    }

    @Override
    public void run(ApplicationArguments args) {
        try (TenantContext.Scope ignored = TenantContext.open(INITIAL_TENANT_ID, null)) {
            transactions.executeWithoutResult(status -> resetPassword());
        }
    }

    private void resetPassword() {
        String username = properties.username() == null ? "" : properties.username().trim();
        if (username.length() < 3 || username.length() > 100) {
            throw new IllegalStateException(
                    "APP_LOCAL_ADMIN_PASSWORD_RESET_USERNAME debe tener entre 3 y 100 caracteres");
        }
        try {
            passwordPolicy.validar(properties.password(), RolSistema.ADMINISTRADOR);
        } catch (IllegalArgumentException exception) {
            throw new IllegalStateException(
                    "APP_LOCAL_ADMIN_PASSWORD_RESET_PASSWORD: " + exception.getMessage(), exception);
        }

        Usuario admin = usuarios.findByNombreUsuarioIgnoreCase(username)
                .filter(Usuario::isEnabled)
                .filter(user -> user.getRoles().stream().anyMatch(role -> Boolean.TRUE.equals(role.getActivo())
                        && RolSistema.ADMINISTRADOR.name().equalsIgnoreCase(role.getCodigo())))
                .orElseThrow(() -> new IllegalStateException("No existe el ADMINISTRADOR activo indicado"));
        if (passwordEncoder.matches(properties.password(), admin.getContrasena())) {
            log.info("Reset local omitido: la contraseña del usuario id={} ya coincide", admin.getId());
            return;
        }

        admin.setContrasena(passwordEncoder.encode(properties.password()));
        admin.setAuthVersion((admin.getAuthVersion() == null ? 0L : admin.getAuthVersion()) + 1L);
        admin.setPasswordChangedAt(clock.instant());
        usuarios.saveAndFlush(admin);
        audit.registrarAnonimo("SEGURIDAD", "ADMIN_PASSWORD_RESET_LOCAL", admin.getNombreUsuario(),
                Map.of("usuarioId", admin.getId(), "resultado", "ACTUALIZADA"));
        log.warn("Contraseña del ADMINISTRADOR local actualizada para usuario id={}; deshabilite el reset",
                admin.getId());
    }
}
