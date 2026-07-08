package ledance.infra.seguridad;

import ledance.auditoria.application.AuditService;
import ledance.entidades.RolSistema;
import ledance.entidades.Usuario;
import ledance.repositorios.UsuarioRepositorio;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Profile;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.util.Map;

@Component
@Profile("dev")
@ConditionalOnProperty(name = "app.bootstrap-admin.reset-existing-password", havingValue = "true")
public class LocalAdminPasswordResetRunner implements ApplicationRunner {
    private static final Logger log = LoggerFactory.getLogger(LocalAdminPasswordResetRunner.class);

    private final AdminBootstrapProperties properties;
    private final UsuarioRepositorio usuarios;
    private final PasswordEncoder passwordEncoder;
    private final PasswordPolicy passwordPolicy;
    private final AuditService audit;
    private final Clock clock;

    public LocalAdminPasswordResetRunner(AdminBootstrapProperties properties,
                                         UsuarioRepositorio usuarios,
                                         PasswordEncoder passwordEncoder,
                                         PasswordPolicy passwordPolicy,
                                         AuditService audit,
                                         Clock clock) {
        this.properties = properties;
        this.usuarios = usuarios;
        this.passwordEncoder = passwordEncoder;
        this.passwordPolicy = passwordPolicy;
        this.audit = audit;
        this.clock = clock;
    }

    @Override
    @Transactional
    public void run(ApplicationArguments args) {
        if (properties.enabled()) {
            throw new IllegalStateException("No habilite bootstrap y reset local simultáneamente");
        }
        String username = properties.username() == null ? "" : properties.username().trim();
        if (username.length() < 3 || username.length() > 100) {
            throw new IllegalStateException(
                    "APP_BOOTSTRAP_ADMIN_USERNAME debe tener entre 3 y 100 caracteres");
        }
        try {
            passwordPolicy.validar(properties.password(), RolSistema.ADMINISTRADOR);
        } catch (IllegalArgumentException exception) {
            throw new IllegalStateException("APP_BOOTSTRAP_ADMIN_PASSWORD: " + exception.getMessage(), exception);
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
