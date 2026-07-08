package ledance.servicios.usuario;

import jakarta.transaction.Transactional;
import ledance.auditoria.application.AuditFailureService;
import ledance.auditoria.application.AuditService;
import ledance.dto.usuario.UsuarioMapper;
import ledance.dto.usuario.request.UsuarioModificacionRequest;
import ledance.dto.usuario.request.UsuarioRegistroRequest;
import ledance.dto.usuario.response.UsuarioResponse;
import ledance.entidades.Rol;
import ledance.entidades.Usuario;
import ledance.infra.errores.TratadorDeErrores.OperacionNoPermitidaException;
import ledance.infra.seguridad.PasswordPolicy;
import ledance.repositorios.RolRepositorio;
import ledance.repositorios.UsuarioRepositorio;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

import java.time.Clock;
import java.util.Collection;
import java.util.Comparator;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

@Service
public class UsuarioServicio {
    private static final String SUPERADMIN = "SUPERADMIN";

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
    public UsuarioResponse registrarUsuario(UsuarioRegistroRequest request, Usuario actor) {
        Usuario actorActual = exigirPermiso(actor, "PERM_USUARIOS_WRITE", "CREAR_USUARIO");
        String username = normalizarUsername(request.nombreUsuario());
        if (usuarios.findByNombreUsuarioIgnoreCase(username).isPresent()) {
            throw new IllegalArgumentException("El nombre de usuario ya está en uso");
        }
        Set<Rol> rolesNuevos = resolverRolesActivos(request.roles());
        validarAsignables(actorActual, rolesNuevos);
        passwordPolicy.validar(request.contrasena(), contieneRol(rolesNuevos, SUPERADMIN));

        Usuario usuario = mapper.toEntity(request);
        usuario.setNombreUsuario(username);
        usuario.setContrasena(passwordEncoder.encode(request.contrasena()));
        usuario.setRoles(rolesNuevos);
        usuario.setRol(rolPrincipal(rolesNuevos));
        usuario.setActivo(true);
        usuario.setAuthVersion(0L);
        usuario.setPasswordChangedAt(clock.instant());
        usuarios.save(usuario);
        audit.registrar("USUARIOS", "USUARIO_CREADO", "USUARIO", id(usuario), actorActual,
                null, null, null, snapshot(usuario), Map.of());
        audit.registrar("USUARIOS", "ROLES_ASIGNADOS", "USUARIO", id(usuario), actorActual,
                null, null, Map.of("roles", List.of()), Map.of("roles", codigos(rolesNuevos)), Map.of());
        return mapper.toDTO(usuario);
    }

    @Transactional
    public UsuarioResponse editarUsuario(Long idUsuario, UsuarioModificacionRequest request, Usuario actor) {
        Usuario actorActual = exigirPermiso(actor, "PERM_USUARIOS_WRITE", "MODIFICAR_USUARIO");
        Usuario usuario = bloquearObjetivo(idUsuario);
        Map<String, ?> anterior = snapshot(usuario);
        Set<String> rolesAnteriores = codigos(usuario.getRoles());
        Set<Rol> rolesNuevos = request.roles() == null
                ? new LinkedHashSet<>(usuario.getRoles()) : resolverRolesActivos(request.roles());
        validarAsignables(actorActual, rolesNuevos);
        boolean activoNuevo = request.activo() == null ? Boolean.TRUE.equals(usuario.getActivo()) : request.activo();
        if (contieneRol(usuario.getRoles(), SUPERADMIN) && Boolean.TRUE.equals(usuario.getActivo())
                && (!contieneRol(rolesNuevos, SUPERADMIN) || !activoNuevo)) {
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
        boolean rolesCambiados = !rolesAnteriores.equals(codigos(rolesNuevos));
        boolean estadoCambiado = request.activo() != null
                && request.activo() != Boolean.TRUE.equals(usuario.getActivo());
        if (request.contrasena() != null && !request.contrasena().isBlank()) {
            passwordPolicy.validar(request.contrasena(), contieneRol(rolesNuevos, SUPERADMIN));
            usuario.setContrasena(passwordEncoder.encode(request.contrasena()));
            usuario.setPasswordChangedAt(clock.instant());
            passwordCambiada = true;
        }
        if (rolesCambiados) {
            usuario.setRoles(rolesNuevos);
            usuario.setRol(rolPrincipal(rolesNuevos));
        }
        if (request.activo() != null) usuario.setActivo(request.activo());
        if (passwordCambiada || rolesCambiados || estadoCambiado) {
            usuario.setAuthVersion(usuario.getAuthVersion() + 1);
        }
        usuarios.save(usuario);
        Map<String, ?> nuevo = snapshot(usuario);
        if (passwordCambiada) auditarCambio("PASSWORD_CAMBIADA", usuario, actorActual, anterior, nuevo);
        if (rolesCambiados) auditarRoles(usuario, actorActual, rolesAnteriores, codigos(rolesNuevos));
        if (estadoCambiado) auditarCambio(Boolean.TRUE.equals(usuario.getActivo())
                ? "USUARIO_ACTIVADO" : "USUARIO_DESACTIVADO", usuario, actorActual, anterior, nuevo);
        if (!passwordCambiada && !rolesCambiados && !estadoCambiado) {
            auditarCambio("USUARIO_MODIFICADO", usuario, actorActual, anterior, nuevo);
        }
        return mapper.toDTO(usuario);
    }

    public UsuarioResponse obtenerUsuario(Long idUsuario) {
        return convertirAUsuarioResponse(usuarios.findWithAuthoritiesById(idUsuario)
                .orElseThrow(() -> new IllegalArgumentException("Usuario no encontrado")));
    }

    public List<Usuario> listarUsuarios(String rolCodigo, Boolean activo) {
        if (rolCodigo != null && activo != null) return usuarios.findByRoleCodeAndActivo(rolCodigo, activo);
        if (rolCodigo != null) return usuarios.findByRoleCode(rolCodigo);
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

    private Usuario exigirPermiso(Usuario actor, String permiso, String operacion) {
        if (actor == null || actor.getId() == null) {
            auditFailures.registrarEscalamiento(actor, operacion);
            throw new OperacionNoPermitidaException("Usuario autenticado requerido");
        }
        return usuarios.findWithAuthoritiesById(actor.getId())
                .filter(Usuario::isEnabled)
                .filter(user -> user.getAuthorities().stream().anyMatch(value -> permiso.equals(value.getAuthority())))
                .orElseThrow(() -> {
                    auditFailures.registrarEscalamiento(actor, operacion);
                    return new OperacionNoPermitidaException("La operación requiere " + permiso);
                });
    }

    private void validarAsignables(Usuario actor, Collection<Rol> rolesNuevos) {
        if (contieneRol(actor.getRoles(), SUPERADMIN)) return;
        Set<String> permisosActor = actor.getAuthorities().stream()
                .map(value -> value.getAuthority())
                .filter(value -> value.startsWith("PERM_"))
                .collect(Collectors.toSet());
        boolean excede = rolesNuevos.stream()
                .flatMap(role -> role.getPermisos().stream())
                .filter(permiso -> Boolean.TRUE.equals(permiso.getActivo()))
                .map(permiso -> "PERM_" + permiso.getCodigo())
                .anyMatch(permiso -> !permisosActor.contains(permiso));
        if (excede || contieneRol(rolesNuevos, SUPERADMIN)) {
            throw new OperacionNoPermitidaException("No puede asignar roles con permisos superiores a los propios");
        }
    }

    private Usuario bloquearObjetivo(Long idUsuario) {
        Usuario snapshot = usuarios.findWithAuthoritiesById(idUsuario)
                .orElseThrow(() -> new IllegalArgumentException("Usuario no encontrado"));
        if (Boolean.TRUE.equals(snapshot.getActivo()) && contieneRol(snapshot.getRoles(), SUPERADMIN)) {
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

    private Set<Rol> resolverRolesActivos(List<String> codigos) {
        if (codigos == null || codigos.isEmpty()) throw new IllegalArgumentException("Debe asignar al menos un rol");
        Set<Rol> encontrados = codigos.stream()
                .map(UsuarioServicio::normalizarCodigo)
                .distinct()
                .map(codigo -> roles.findByCodigoIgnoreCase(codigo)
                        .filter(role -> Boolean.TRUE.equals(role.getActivo()))
                        .orElseThrow(() -> new IllegalArgumentException("Rol no válido o inactivo: " + codigo)))
                .collect(Collectors.toCollection(LinkedHashSet::new));
        if (encontrados.isEmpty()) throw new IllegalArgumentException("Debe asignar al menos un rol");
        return encontrados;
    }

    private static Rol rolPrincipal(Collection<Rol> roles) {
        return roles.stream().min(Comparator
                .comparingInt((Rol role) -> switch (role.getCodigo()) {
                    case "SUPERADMIN" -> 0;
                    case "ADMINISTRADOR" -> 1;
                    default -> 2;
                })
                .thenComparing(Rol::getCodigo)).orElseThrow();
    }

    private void auditarRoles(Usuario usuario, Usuario actor, Set<String> anteriores, Set<String> nuevos) {
        Set<String> asignados = new LinkedHashSet<>(nuevos);
        asignados.removeAll(anteriores);
        Set<String> removidos = new LinkedHashSet<>(anteriores);
        removidos.removeAll(nuevos);
        if (!asignados.isEmpty()) audit.registrar("USUARIOS", "ROLES_ASIGNADOS", "USUARIO", id(usuario), actor,
                null, null, Map.of("roles", anteriores), Map.of("roles", nuevos), Map.of("asignados", asignados));
        if (!removidos.isEmpty()) audit.registrar("USUARIOS", "ROLES_REMOVIDOS", "USUARIO", id(usuario), actor,
                null, null, Map.of("roles", anteriores), Map.of("roles", nuevos), Map.of("removidos", removidos));
    }

    private void auditarCambio(String accion, Usuario usuario, Usuario actor,
                               Map<String, ?> anterior, Map<String, ?> nuevo) {
        audit.registrar("USUARIOS", accion, "USUARIO", id(usuario), actor,
                null, null, anterior, nuevo, Map.of());
    }

    private static Map<String, ?> snapshot(Usuario usuario) {
        return Map.of(
                "username", usuario.getNombreUsuario(),
                "roles", codigos(usuario.getRoles()),
                "activo", Boolean.TRUE.equals(usuario.getActivo()),
                "authVersion", usuario.getAuthVersion());
    }

    private static Set<String> codigos(Collection<Rol> roles) {
        return roles.stream().map(Rol::getCodigo).sorted()
                .collect(Collectors.toCollection(LinkedHashSet::new));
    }

    private static boolean contieneRol(Collection<Rol> roles, String codigo) {
        return roles.stream().anyMatch(role -> codigo.equalsIgnoreCase(role.getCodigo()));
    }

    private static String normalizarUsername(String username) {
        String normalizado = username == null ? "" : username.trim();
        if (normalizado.length() < 3 || normalizado.length() > 100) {
            throw new IllegalArgumentException("El username debe tener entre 3 y 100 caracteres");
        }
        return normalizado;
    }

    private static String normalizarCodigo(String codigo) {
        String normalizado = codigo == null ? "" : codigo.trim().toUpperCase();
        if (!normalizado.matches("[A-Z][A-Z0-9_]{1,49}")) {
            throw new IllegalArgumentException("Código de rol inválido: " + codigo);
        }
        return normalizado;
    }

    private static String id(Usuario usuario) {
        return usuario.getId() == null ? null : usuario.getId().toString();
    }
}
