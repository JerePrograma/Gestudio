package ledance.servicios.usuario;

import jakarta.transaction.Transactional;
import ledance.auditoria.application.AuditFailureService;
import ledance.auditoria.application.AuditService;
import ledance.dto.usuario.UsuarioMapper;
import ledance.dto.usuario.request.UsuarioModificacionRequest;
import ledance.dto.usuario.request.UsuarioRegistroRequest;
import ledance.dto.usuario.response.UsuarioResponse;
import ledance.entidades.Rol;
import ledance.entidades.RolSistema;
import ledance.entidades.Usuario;
import ledance.infra.errores.TratadorDeErrores.OperacionNoPermitidaException;
import ledance.infra.seguridad.PasswordPolicy;
import ledance.repositorios.RolRepositorio;
import ledance.repositorios.UsuarioRepositorio;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

import java.time.Clock;
import java.util.List;
import java.util.Map;

@Service
public class UsuarioServicio {
    private final UsuarioRepositorio usuarios;
    private final PasswordEncoder passwordEncoder;
    private final PasswordPolicy passwordPolicy;
    private final RolRepositorio roles;
    private final UsuarioMapper mapper;
    private final Clock clock;
    private final AuditService audit;
    private final AuditFailureService auditFailures;

    public UsuarioServicio(UsuarioRepositorio usuarios,
                           PasswordEncoder passwordEncoder,
                           PasswordPolicy passwordPolicy,
                           RolRepositorio roles,
                           UsuarioMapper mapper,
                           Clock clock,
                           AuditService audit,
                           AuditFailureService auditFailures) {
        this.usuarios = usuarios;
        this.passwordEncoder = passwordEncoder;
        this.passwordPolicy = passwordPolicy;
        this.roles = roles;
        this.mapper = mapper;
        this.clock = clock;
        this.audit = audit;
        this.auditFailures = auditFailures;
    }

    @Transactional
    public String registrarUsuario(UsuarioRegistroRequest request, Usuario actor) {
        Usuario actorActual = exigirSuperadmin(actor, "CREAR_USUARIO");
        String username = normalizarUsername(request.nombreUsuario());
        if (usuarios.findByNombreUsuarioIgnoreCase(username).isPresent()) {
            throw new IllegalArgumentException("El nombre de usuario ya está en uso");
        }
        RolSistema rolSistema = rolSistema(request.rol());
        passwordPolicy.validar(request.contrasena(), rolSistema);

        Usuario usuario = mapper.toEntity(request);
        usuario.setNombreUsuario(username);
        usuario.setContrasena(passwordEncoder.encode(request.contrasena()));
        usuario.setRol(rolActivo(rolSistema));
        usuario.setActivo(true);
        usuario.setAuthVersion(0L);
        usuario.setPasswordChangedAt(clock.instant());
        usuarios.save(usuario);
        audit.registrar("USUARIOS", "USUARIO_CREADO", "USUARIO", id(usuario), actorActual,
                null, null, null, snapshot(usuario), Map.of());
        return "Usuario creado exitosamente.";
    }

    @Transactional
    public void editarUsuario(Long idUsuario, UsuarioModificacionRequest request, Usuario actor) {
        Usuario actorActual = exigirSuperadmin(actor, "MODIFICAR_USUARIO");
        Usuario usuario = bloquearObjetivo(idUsuario);
        Map<String, ?> anterior = snapshot(usuario);
        RolSistema rolActual = rolSistema(usuario.getRol().getDescripcion());
        RolSistema rolNuevo = request.rol() == null || request.rol().isBlank()
                ? rolActual : rolSistema(request.rol());
        boolean activoNuevo = request.activo() == null ? Boolean.TRUE.equals(usuario.getActivo()) : request.activo();
        if (rolActual == RolSistema.SUPERADMIN && Boolean.TRUE.equals(usuario.getActivo())
                && (rolNuevo != RolSistema.SUPERADMIN || !activoNuevo)) {
            impedirPerderUltimoSuperadmin(usuario.getId());
        }

        if (request.nombreUsuario() != null && !request.nombreUsuario().isBlank()) {
            String username = normalizarUsername(request.nombreUsuario());
            usuarios.findByNombreUsuarioIgnoreCase(username)
                    .filter(existing -> !existing.getId().equals(usuario.getId()))
                    .ifPresent(existing -> { throw new IllegalArgumentException("El nombre de usuario ya está en uso"); });
            usuario.setNombreUsuario(username);
        }

        boolean passwordCambiada = false;
        boolean rolCambiado = false;
        boolean estadoCambiado = false;
        if (request.contrasena() != null && !request.contrasena().isBlank()) {
            passwordPolicy.validar(request.contrasena(), rolNuevo);
            usuario.setContrasena(passwordEncoder.encode(request.contrasena()));
            usuario.setPasswordChangedAt(clock.instant());
            passwordCambiada = true;
        }
        if (rolNuevo != rolActual) {
            usuario.setRol(rolActivo(rolNuevo));
            rolCambiado = true;
        }
        if (request.activo() != null && request.activo() != Boolean.TRUE.equals(usuario.getActivo())) {
            usuario.setActivo(request.activo());
            estadoCambiado = true;
        }
        if (passwordCambiada || rolCambiado || estadoCambiado) {
            usuario.setAuthVersion(usuario.getAuthVersion() + 1);
        }
        usuarios.save(usuario);
        Map<String, ?> nuevo = snapshot(usuario);
        if (passwordCambiada) auditarCambio("PASSWORD_CAMBIADA", usuario, actorActual, anterior, nuevo);
        if (rolCambiado) auditarCambio("ROL_CAMBIADO", usuario, actorActual, anterior, nuevo);
        if (estadoCambiado) auditarCambio(Boolean.TRUE.equals(usuario.getActivo())
                ? "USUARIO_ACTIVADO" : "USUARIO_DESACTIVADO", usuario, actorActual, anterior, nuevo);
        if (!passwordCambiada && !rolCambiado && !estadoCambiado) {
            auditarCambio("USUARIO_MODIFICADO", usuario, actorActual, anterior, nuevo);
        }
    }

    public UsuarioResponse obtenerUsuario(Long idUsuario) {
        return convertirAUsuarioResponse(usuarios.findById(idUsuario)
                .orElseThrow(() -> new IllegalArgumentException("Usuario no encontrado")));
    }

    public List<Usuario> listarUsuarios(String rolDescripcion, Boolean activo) {
        if (rolDescripcion != null && activo != null) {
            return usuarios.findByRolAndActivo(rolActivo(rolSistema(rolDescripcion)), activo);
        }
        if (rolDescripcion != null) return usuarios.findByRol(rolActivo(rolSistema(rolDescripcion)));
        if (activo != null) return usuarios.findByActivo(activo);
        return usuarios.findAll();
    }

    public UsuarioResponse convertirAUsuarioResponse(Usuario usuario) {
        return mapper.toDTO(usuario);
    }

    @Transactional
    public void eliminarUsuario(Long idUsuario, Usuario actor) {
        editarUsuario(idUsuario, new UsuarioModificacionRequest(null, null, null, false), actor);
    }

    private Usuario exigirSuperadmin(Usuario actor, String operacion) {
        if (actor == null || actor.getId() == null) {
            auditFailures.registrarEscalamiento(actor, operacion);
            throw new OperacionNoPermitidaException("SUPERADMIN autenticado requerido");
        }
        return usuarios.findById(actor.getId())
                .filter(Usuario::isEnabled)
                .filter(user -> user.getRol() != null && Boolean.TRUE.equals(user.getRol().getActivo()))
                .filter(user -> rolSistema(user.getRol().getDescripcion()) == RolSistema.SUPERADMIN)
                .orElseThrow(() -> {
                    auditFailures.registrarEscalamiento(actor, operacion);
                    return new OperacionNoPermitidaException("La operación requiere SUPERADMIN");
                });
    }

    private Usuario bloquearObjetivo(Long idUsuario) {
        Usuario snapshot = usuarios.findById(idUsuario)
                .orElseThrow(() -> new IllegalArgumentException("Usuario no encontrado"));
        if (Boolean.TRUE.equals(snapshot.getActivo())
                && rolSistema(snapshot.getRol().getDescripcion()) == RolSistema.SUPERADMIN) {
            return usuarios.findActiveSuperadminsForUpdate().stream()
                    .filter(user -> user.getId().equals(idUsuario)).findFirst()
                    .orElseThrow(() -> new IllegalArgumentException("Usuario no encontrado"));
        }
        return usuarios.findByIdForUpdate(idUsuario)
                .orElseThrow(() -> new IllegalArgumentException("Usuario no encontrado"));
    }

    private void impedirPerderUltimoSuperadmin(Long idUsuario) {
        List<Usuario> activos = usuarios.findActiveSuperadminsForUpdate();
        if (activos.size() == 1 && activos.getFirst().getId().equals(idUsuario)) {
            throw new OperacionNoPermitidaException("No se puede degradar o desactivar al último SUPERADMIN activo");
        }
    }

    private Rol rolActivo(RolSistema rol) {
        return roles.findByDescripcionIgnoreCase(rol.name())
                .filter(existing -> Boolean.TRUE.equals(existing.getActivo()))
                .orElseThrow(() -> new IllegalArgumentException("Rol no válido: " + rol));
    }

    private static RolSistema rolSistema(String rol) {
        try {
            return RolSistema.valueOf(rol == null ? "" : rol.trim().toUpperCase());
        } catch (IllegalArgumentException e) {
            throw new IllegalArgumentException("Rol reservado no válido: " + rol, e);
        }
    }

    private static String normalizarUsername(String username) {
        String normalizado = username == null ? "" : username.trim();
        if (normalizado.length() < 3 || normalizado.length() > 100) {
            throw new IllegalArgumentException("El username debe tener entre 3 y 100 caracteres");
        }
        return normalizado;
    }

    private void auditarCambio(String accion, Usuario usuario, Usuario actor,
                               Map<String, ?> anterior, Map<String, ?> nuevo) {
        audit.registrar("USUARIOS", accion, "USUARIO", id(usuario), actor,
                null, null, anterior, nuevo, Map.of());
    }

    private static Map<String, ?> snapshot(Usuario usuario) {
        return Map.of(
                "username", usuario.getNombreUsuario(),
                "rol", usuario.getRol().getDescripcion(),
                "activo", Boolean.TRUE.equals(usuario.getActivo()),
                "authVersion", usuario.getAuthVersion());
    }

    private static String id(Usuario usuario) {
        return usuario.getId() == null ? null : usuario.getId().toString();
    }
}
