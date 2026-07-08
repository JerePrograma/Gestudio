package gestudio.servicios.usuario;

import gestudio.auditoria.application.AuditService;
import gestudio.dto.usuario.UsuarioMapper;
import gestudio.dto.usuario.request.UsuarioModificacionRequest;
import gestudio.dto.usuario.request.UsuarioRegistroRequest;
import gestudio.dto.usuario.response.UsuarioResponse;
import gestudio.entidades.Rol;
import gestudio.entidades.Usuario;
import gestudio.infra.errores.TratadorDeErrores.OperacionNoPermitidaException;
import gestudio.infra.seguridad.PasswordPolicy;
import gestudio.infra.seguridad.RbacService;
import gestudio.repositorios.RolRepositorio;
import gestudio.repositorios.UsuarioRepositorio;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

@Service
public class UsuarioServicio {

    private static final String PERM_USUARIOS_ADMIN = "PERM_USUARIOS_ADMIN";

    private final UsuarioRepositorio usuarios;
    private final PasswordEncoder passwordEncoder;
    private final PasswordPolicy passwordPolicy;
    private final RolRepositorio roles;
    private final UsuarioMapper mapper;
    private final Clock clock;
    private final AuditService audit;
    private final RbacService rbac;

    public UsuarioServicio(UsuarioRepositorio usuarios,
                           PasswordEncoder passwordEncoder,
                           PasswordPolicy passwordPolicy,
                           RolRepositorio roles,
                           UsuarioMapper mapper,
                           Clock clock,
                           AuditService audit,
                           RbacService rbac) {
        this.usuarios = usuarios;
        this.passwordEncoder = passwordEncoder;
        this.passwordPolicy = passwordPolicy;
        this.roles = roles;
        this.mapper = mapper;
        this.clock = clock;
        this.audit = audit;
        this.rbac = rbac;
    }

    @Transactional
    public UsuarioResponse registrarUsuario(UsuarioRegistroRequest request, Usuario actor) {
        Usuario actorActual = rbac.exigirPermiso(actor, PERM_USUARIOS_ADMIN, "CREAR_USUARIO");

        String username = normalizarUsername(request.nombreUsuario());

        if (usuarios.findByNombreUsuarioIgnoreCase(username).isPresent()) {
            throw new IllegalArgumentException("El nombre de usuario ya está en uso");
        }

        Set<Rol> rolesNuevos = rolesActivos(request.roles());
        validarAsignacionPermitida(actorActual, rolesNuevos);

        passwordPolicy.validar(request.contrasena(), contieneSuperadmin(rolesNuevos));

        Usuario usuario = mapper.toEntity(request);
        usuario.setNombreUsuario(username);
        usuario.setContrasena(passwordEncoder.encode(request.contrasena()));
        usuario.setRol(rolPrincipal(rolesNuevos));
        usuario.setRoles(rolesNuevos);
        usuario.setActivo(true);
        usuario.setAuthVersion(0L);
        usuario.setPasswordChangedAt(clock.instant());

        usuario = usuarios.saveAndFlush(usuario);

        audit.registrar(
                "USUARIOS",
                "USUARIO_CREADO",
                "USUARIO",
                id(usuario),
                actorActual,
                null,
                null,
                null,
                snapshot(usuario),
                Map.of()
        );

        return convertirAUsuarioResponse(recargar(usuario.getId()));
    }

    @Transactional
    public UsuarioResponse editarUsuario(Long idUsuario, UsuarioModificacionRequest request, Usuario actor) {
        Usuario actorActual = rbac.exigirPermiso(actor, PERM_USUARIOS_ADMIN, "MODIFICAR_USUARIO");
        Usuario usuario = bloquearObjetivo(idUsuario);

        Map<String, ?> anterior = snapshot(usuario);

        Set<Rol> rolesActuales = new LinkedHashSet<>(usuario.rolesEfectivos());
        Set<Rol> rolesNuevos = request.roles() == null || request.roles().isEmpty()
                ? rolesActuales
                : rolesActivos(request.roles());

        validarAsignacionPermitida(actorActual, rolesNuevos);

        boolean activoNuevo = request.activo() == null
                ? Boolean.TRUE.equals(usuario.getActivo())
                : request.activo();

        if (contieneSuperadmin(rolesActuales)
                && Boolean.TRUE.equals(usuario.getActivo())
                && (!contieneSuperadmin(rolesNuevos) || !activoNuevo)) {
            impedirPerderUltimoSuperadmin(usuario.getId());
        }

        if (request.nombreUsuario() != null && !request.nombreUsuario().isBlank()) {
            String username = normalizarUsername(request.nombreUsuario());

            Long usuarioIdActual = usuario.getId();

            usuarios.findByNombreUsuarioIgnoreCase(username)
                    .filter(existing -> !existing.getId().equals(usuarioIdActual))
                    .ifPresent(existing -> {
                        throw new IllegalArgumentException("El nombre de usuario ya está en uso");
                    });

            usuario.setNombreUsuario(username);
        }

        boolean passwordCambiada = false;
        boolean rolesCambiados = false;
        boolean estadoCambiado = false;

        if (request.contrasena() != null && !request.contrasena().isBlank()) {
            passwordPolicy.validar(request.contrasena(), contieneSuperadmin(rolesNuevos));
            usuario.setContrasena(passwordEncoder.encode(request.contrasena()));
            usuario.setPasswordChangedAt(clock.instant());
            passwordCambiada = true;
        }

        if (!codigosRoles(rolesActuales).equals(codigosRoles(rolesNuevos))) {
            usuario.setRoles(rolesNuevos);
            usuario.setRol(rolPrincipal(rolesNuevos));
            rolesCambiados = true;
        }

        if (request.activo() != null && request.activo() != Boolean.TRUE.equals(usuario.getActivo())) {
            usuario.setActivo(request.activo());
            estadoCambiado = true;
        }

        if (passwordCambiada || rolesCambiados || estadoCambiado) {
            usuario.setAuthVersion((usuario.getAuthVersion() == null ? 0L : usuario.getAuthVersion()) + 1L);
        }

        usuario = usuarios.saveAndFlush(usuario);

        Map<String, ?> nuevo = snapshot(usuario);

        if (passwordCambiada) {
            auditarCambio("PASSWORD_CAMBIADA", usuario, actorActual, anterior, nuevo);
        }

        if (rolesCambiados) {
            auditarCambio("ROLES_CAMBIADOS", usuario, actorActual, anterior, nuevo);
        }

        if (estadoCambiado) {
            auditarCambio(Boolean.TRUE.equals(usuario.getActivo())
                    ? "USUARIO_ACTIVADO"
                    : "USUARIO_DESACTIVADO", usuario, actorActual, anterior, nuevo);
        }

        if (!passwordCambiada && !rolesCambiados && !estadoCambiado) {
            auditarCambio("USUARIO_MODIFICADO", usuario, actorActual, anterior, nuevo);
        }

        return convertirAUsuarioResponse(recargar(usuario.getId()));
    }

    @Transactional(readOnly = true)
    public UsuarioResponse obtenerUsuario(Long idUsuario) {
        return convertirAUsuarioResponse(recargar(idUsuario));
    }

    @Transactional(readOnly = true)
    public List<Usuario> listarUsuarios(String rolCodigo, Boolean activo) {
        return usuarios.findAllConRolesYPermisos().stream()
                .filter(usuario -> activo == null || activo.equals(usuario.getActivo()))
                .filter(usuario -> rolCodigo == null
                        || rolCodigo.isBlank()
                        || usuario.codigosRolesActivos().stream()
                        .anyMatch(codigo -> codigo.equalsIgnoreCase(rolCodigo.trim())))
                .toList();
    }

    public UsuarioResponse convertirAUsuarioResponse(Usuario usuario) {
        return mapper.toDTO(usuario);
    }

    @Transactional
    public void eliminarUsuario(Long idUsuario, Usuario actor) {
        editarUsuario(idUsuario, new UsuarioModificacionRequest(null, null, null, false), actor);
    }

    private Usuario recargar(Long idUsuario) {
        return usuarios.findByIdConRolesYPermisos(idUsuario)
                .orElseThrow(() -> new IllegalArgumentException("Usuario no encontrado"));
    }

    private Usuario bloquearObjetivo(Long idUsuario) {
        Usuario snapshot = recargar(idUsuario);

        if (Boolean.TRUE.equals(snapshot.getActivo()) && snapshot.esSuperadminSistema()) {
            return usuarios.findActiveSuperadminsForUpdate().stream()
                    .filter(user -> user.getId().equals(idUsuario))
                    .findFirst()
                    .orElseThrow(() -> new IllegalArgumentException("Usuario no encontrado"));
        }

        return snapshot;
    }

    private void impedirPerderUltimoSuperadmin(Long idUsuario) {
        List<Usuario> activos = usuarios.findActiveSuperadminsForUpdate();

        if (activos.size() == 1 && activos.getFirst().getId().equals(idUsuario)) {
            throw new OperacionNoPermitidaException(
                    "No se puede degradar o desactivar al último SUPERADMIN activo"
            );
        }
    }

    private Set<Rol> rolesActivos(Set<String> codigos) {
        if (codigos == null || codigos.isEmpty()) {
            throw new IllegalArgumentException("Debe indicar al menos un rol");
        }

        Set<Rol> result = new LinkedHashSet<>();

        for (String codigo : codigos) {
            String normalizado = normalizarCodigoRol(codigo);

            Rol rol = roles.findWithPermisosByCodigoIgnoreCase(normalizado)
                    .or(() -> roles.findByDescripcionIgnoreCase(normalizado))
                    .filter(Rol::estaActivo)
                    .orElseThrow(() -> new IllegalArgumentException("Rol no válido o inactivo: " + codigo));

            result.add(rol);
        }

        return result;
    }

    private void validarAsignacionPermitida(Usuario actor, Set<Rol> rolesObjetivo) {
        if (actor.esSuperadminSistema()) {
            return;
        }

        if (contieneSuperadmin(rolesObjetivo)) {
            throw new OperacionNoPermitidaException("Sólo SUPERADMIN sistema puede asignar SUPERADMIN");
        }

        Set<String> permisosActor = actor.codigosPermisosActivos();

        Set<String> permisosObjetivo = rolesObjetivo.stream()
                .flatMap(rol -> rol.getPermisos().stream())
                .filter(permiso -> Boolean.TRUE.equals(permiso.getActivo()))
                .map(permiso -> permiso.getCodigo())
                .collect(Collectors.toCollection(LinkedHashSet::new));

        if (!permisosActor.containsAll(permisosObjetivo)) {
            throw new OperacionNoPermitidaException(
                    "No se puede asignar un rol con permisos que el actor no posee"
            );
        }
    }

    private static Rol rolPrincipal(Set<Rol> roles) {
        return roles.stream()
                .filter(Rol::esSuperadminSistema)
                .findFirst()
                .orElseGet(() -> roles.stream()
                        .findFirst()
                        .orElseThrow(() -> new IllegalArgumentException("Debe indicar al menos un rol")));
    }

    private static boolean contieneSuperadmin(Set<Rol> roles) {
        return roles.stream().anyMatch(Rol::esSuperadminSistema);
    }

    private static Set<String> codigosRoles(Set<Rol> roles) {
        return roles.stream()
                .map(Rol::getCodigo)
                .map(String::toUpperCase)
                .collect(Collectors.toCollection(LinkedHashSet::new));
    }

    private static String normalizarUsername(String username) {
        String normalizado = username == null ? "" : username.trim();

        if (normalizado.length() < 3 || normalizado.length() > 100) {
            throw new IllegalArgumentException("El username debe tener entre 3 y 100 caracteres");
        }

        return normalizado;
    }

    private static String normalizarCodigoRol(String codigo) {
        String normalizado = codigo == null ? "" : codigo.trim().toUpperCase();

        if (!normalizado.matches("^[A-Z][A-Z0-9_]{2,49}$")) {
            throw new IllegalArgumentException("Código de rol inválido: " + codigo);
        }

        return normalizado;
    }

    private void auditarCambio(String accion,
                               Usuario usuario,
                               Usuario actor,
                               Map<String, ?> anterior,
                               Map<String, ?> nuevo) {
        audit.registrar(
                "USUARIOS",
                accion,
                "USUARIO",
                id(usuario),
                actor,
                null,
                null,
                anterior,
                nuevo,
                Map.of()
        );
    }

    private static Map<String, ?> snapshot(Usuario usuario) {
        return Map.of(
                "username", usuario.getNombreUsuario(),
                "roles", usuario.codigosRolesActivos(),
                "permisos", usuario.codigosPermisosActivos(),
                "activo", Boolean.TRUE.equals(usuario.getActivo()),
                "authVersion", usuario.getAuthVersion()
        );
    }

    private static String id(Usuario usuario) {
        return usuario.getId() == null ? null : usuario.getId().toString();
    }
}
