package gestudio.infra.seguridad;

import gestudio.auditoria.application.AuditService;
import gestudio.entidades.RolSistema;
import gestudio.entidades.Usuario;
import gestudio.repositorios.RolRepositorio;
import gestudio.repositorios.UsuarioRepositorio;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.stream.Collectors;

@Service
public class SuperadminBootstrapService {
    static final String CLAIM = "SUPERADMIN_INICIAL";

    private final JdbcTemplate jdbc;
    private final UsuarioRepositorio usuarios;
    private final RolRepositorio roles;
    private final PasswordEncoder passwordEncoder;
    private final PasswordPolicy passwordPolicy;
    private final AuditService audit;
    private final Clock clock;

    public SuperadminBootstrapService(JdbcTemplate jdbc,
                                      UsuarioRepositorio usuarios,
                                      RolRepositorio roles,
                                      PasswordEncoder passwordEncoder,
                                      PasswordPolicy passwordPolicy,
                                      AuditService audit,
                                      Clock clock) {
        this.jdbc = jdbc;
        this.usuarios = usuarios;
        this.roles = roles;
        this.passwordEncoder = passwordEncoder;
        this.passwordPolicy = passwordPolicy;
        this.audit = audit;
        this.clock = clock;
    }

    @Transactional
    public Usuario bootstrap(String rawUsername, String password) {
        if (jdbc.update("""
                INSERT INTO bootstrap_ejecuciones(tipo)
                VALUES (?) ON CONFLICT (tipo) DO NOTHING
                """, CLAIM) != 1) {
            throw new IllegalStateException(
                    "El bootstrap SUPERADMIN ya fue ejecutado; deshabilite la bandera");
        }

        String username = normalizarUsername(rawUsername);
        try {
            passwordPolicy.validar(password, RolSistema.SUPERADMIN);
        } catch (IllegalArgumentException e) {
            throw new IllegalStateException("APP_BOOTSTRAP_SUPERADMIN_PASSWORD: " + e.getMessage(), e);
        }
        var role = roles.findWithPermisosByCodigoIgnoreCase(RolSistema.SUPERADMIN.name())
                .filter(existing -> Boolean.TRUE.equals(existing.getActivo()))
                .orElseThrow(() -> new IllegalStateException("El rol SUPERADMIN no está disponible"));
        var permisosActivos = role.getPermisos().stream()
                .filter(permiso -> Boolean.TRUE.equals(permiso.getActivo()))
                .map(permiso -> permiso.getCodigo())
                .collect(Collectors.toSet());
        if (!permisosActivos.containsAll(PermissionCodes.ALL)) {
            throw new IllegalStateException("La matriz obligatoria del rol SUPERADMIN no está disponible");
        }
        if (usuarios.findByNombreUsuarioIgnoreCase(username).isPresent()) {
            throw new IllegalStateException("El username del bootstrap ya existe");
        }

        Usuario superadmin = new Usuario();
        superadmin.setNombreUsuario(username);
        superadmin.setContrasena(passwordEncoder.encode(password));
        superadmin.setRol(role);
        superadmin.setRoles(new LinkedHashSet<>(java.util.List.of(role)));
        superadmin.setActivo(true);
        superadmin.setAuthVersion(0L);
        superadmin.setPasswordChangedAt(clock.instant());
        Usuario saved = usuarios.saveAndFlush(superadmin);
        jdbc.update("UPDATE bootstrap_ejecuciones SET usuario_id = ? WHERE tipo = ?", saved.getId(), CLAIM);
        audit.registrar("SEGURIDAD", "SUPERADMIN_BOOTSTRAP", "USUARIO", saved.getId().toString(),
                saved, "bootstrap:" + CLAIM, Map.of("resultado", "CREADO"));
        return saved;
    }

    private String normalizarUsername(String username) {
        String normalizado = username == null ? "" : username.trim();
        if (normalizado.length() < 3 || normalizado.length() > 100) {
            throw new IllegalStateException(
                    "APP_BOOTSTRAP_SUPERADMIN_USERNAME debe tener entre 3 y 100 caracteres");
        }
        return normalizado;
    }
}
