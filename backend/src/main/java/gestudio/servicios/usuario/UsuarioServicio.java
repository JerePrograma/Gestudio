package gestudio.servicios.usuario;

import gestudio.auditoria.application.AuditService;
import gestudio.dto.usuario.UsuarioMapper;
import gestudio.dto.usuario.request.UsuarioModificacionRequest;
import gestudio.dto.usuario.request.UsuarioRegistroRequest;
import gestudio.dto.usuario.response.RolAsignableResponse;
import gestudio.dto.usuario.response.UsuarioResponse;
import gestudio.entidades.Rol;
import gestudio.entidades.Usuario;
import gestudio.infra.errores.TratadorDeErrores.OperacionNoPermitidaException;
import gestudio.infra.seguridad.PasswordPolicy;
import gestudio.infra.seguridad.RbacService;
import gestudio.tenancy.TenantAccess;
import gestudio.tenancy.TenantMembership;
import gestudio.tenancy.TenantMembershipManagementService;
import gestudio.tenancy.TenantMembershipStatus;
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

import static gestudio.infra.seguridad.PermissionCodes.PERM_USUARIOS_ADMIN;

@Service
public class UsuarioServicio {

    private final UsuarioRepositorio usuarios;
    private final PasswordEncoder passwordEncoder;
    private final PasswordPolicy passwordPolicy;
    private final RolRepositorio roles;
    private final UsuarioMapper mapper;
    private final Clock clock;
    private final AuditService audit;
    private final RbacService rbac;
    private final TenantMembershipManagementService tenantMemberships;

    public UsuarioServicio(UsuarioRepositorio usuarios,
                           PasswordEncoder passwordEncoder,
                           PasswordPolicy passwordPolicy,
                           RolRepositorio roles,
                           UsuarioMapper mapper,
                           Clock clock,
                           AuditService audit,
                           RbacService rbac,
                           TenantMembershipManagementService tenantMemberships) {
        this.usuarios = usuarios;
        this.passwordEncoder = passwordEncoder;
        this.passwordPolicy = passwordPolicy;
        this.roles = roles;
        this.mapper = mapper;
        this.clock = clock;
        this.audit = audit;
        this.rbac = rbac;
        this.tenantMemberships = tenantMemberships;
    }

    @Transactional
    public UsuarioResponse registrarUsuario(UsuarioRegistroRequest request, Usuario actor) {
        Usuario actorActual = rbac.exigirPermiso(actor, PERM_USUARIOS_ADMIN, "CREAR_USUARIO");

        String username = normalizarUsername(request.nombreUsuario());

        if (usuarios.findByNombreUsuarioIgnoreCase(username).isPresent()) {
            throw new IllegalArgumentException("El nombre de usuario ya está en uso");
        }

        Set<Rol> rolesNuevos = rolesActivos(request.roles());
        validarAsignacionPermitida(rbac.accesoActual(actorActual), rolesNuevos);

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
        TenantMembership membership = tenantMemberships.create(usuario, rolesNuevos, actorActual);

        audit.registrar(
                "USUARIOS",
                "USUARIO_CREADO",
                "USUARIO",
                id(usuario),
                actorActual,
                null,
                null,
                null,
                snapshot(membership),
                Map.of()
        );

        return tenantMemberships.response(membership);
    }

    @Transactional
    public UsuarioResponse editarUsuario(Long idUsuario, UsuarioModificacionRequest request, Usuario actor) {
        Usuario actorActual = rbac.exigirPermiso(actor, PERM_USUARIOS_ADMIN, "MODIFICAR_USUARIO");
        TenantMembership membership = tenantMemberships.require(idUsuario);
        Usuario usuario = membership.getUsuario();

        Map<String, ?> anterior = snapshot(membership);

        Set<Rol> rolesActuales = new LinkedHashSet<>(membership.roles());
        Set<Rol> rolesNuevos = request.roles() == null || request.roles().isEmpty()
                ? rolesActuales
                : rolesParaEdicion(request.roles(), rolesActuales);

        validarAsignacionPermitida(rbac.accesoActual(actorActual), rolesNuevos);

        boolean activoNuevo = request.activo() == null
                ? membership.getStatus() == TenantMembershipStatus.ACTIVE
                : request.activo();

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
        boolean estadoCambiado = activoNuevo != (membership.getStatus() == TenantMembershipStatus.ACTIVE);

        if (request.contrasena() != null && !request.contrasena().isBlank()) {
            passwordPolicy.validar(request.contrasena(), contieneSuperadmin(rolesNuevos));
            usuario.setContrasena(passwordEncoder.encode(request.contrasena()));
            usuario.setPasswordChangedAt(clock.instant());
            passwordCambiada = true;
        }

        if (!codigosRoles(rolesActuales).equals(codigosRoles(rolesNuevos))) {
            rolesCambiados = true;
        }

        if (passwordCambiada) {
            usuario.setAuthVersion((usuario.getAuthVersion() == null ? 0L : usuario.getAuthVersion()) + 1L);
        }

        usuario = usuarios.saveAndFlush(usuario);
        membership = tenantMemberships.update(
                idUsuario,
                rolesCambiados ? rolesNuevos : null,
                estadoCambiado ? activoNuevo : null,
                actorActual
        );

        Map<String, ?> nuevo = snapshot(membership);

        if (passwordCambiada) {
            auditarCambio("PASSWORD_CAMBIADA", usuario, actorActual, anterior, nuevo);
        }

        if (rolesCambiados) {
            auditarCambio("ROLES_CAMBIADOS", usuario, actorActual, anterior, nuevo);
        }

        if (estadoCambiado) {
            auditarCambio(membership.getStatus() == TenantMembershipStatus.ACTIVE
                    ? "USUARIO_ACTIVADO"
                    : "USUARIO_DESACTIVADO", usuario, actorActual, anterior, nuevo);
        }

        if (!passwordCambiada && !rolesCambiados && !estadoCambiado) {
            auditarCambio("USUARIO_MODIFICADO", usuario, actorActual, anterior, nuevo);
        }

        return tenantMemberships.response(membership);
    }

    @Transactional(readOnly = true)
    public UsuarioResponse obtenerUsuario(Long idUsuario) {
        return tenantMemberships.response(tenantMemberships.require(idUsuario));
    }

    @Transactional(readOnly = true)
    public List<UsuarioResponse> listarUsuarios(String rolCodigo, Boolean activo) {
        return tenantMemberships.list().stream()
                .filter(membership -> activo == null
                        || activo == (membership.getStatus() == TenantMembershipStatus.ACTIVE))
                .filter(membership -> rolCodigo == null
                        || rolCodigo.isBlank()
                        || membership.roleCodes().stream()
                        .anyMatch(codigo -> codigo.equalsIgnoreCase(rolCodigo.trim())))
                .map(tenantMemberships::response)
                .toList();
    }

    @Transactional(readOnly = true)
    public List<RolAsignableResponse> listarRolesAsignables(Usuario actor) {
        Usuario actorActual = rbac.exigirPermiso(actor, PERM_USUARIOS_ADMIN, "LISTAR_ROLES_ASIGNABLES");
        TenantAccess access = rbac.accesoActual(actorActual);
        Set<String> permisosActor = access.permissionCodes();

        return roles.findAllByOrderByCodigoAsc().stream()
                .filter(Rol::estaActivo)
                .filter(rol -> !"PROFESOR".equals(rol.getCodigo()))
                .filter(rol -> access.membership().isSuperadmin()
                        || (!rol.esSuperadminSistema() && permisosActor.containsAll(permisosActivos(rol))))
                .map(rol -> new RolAsignableResponse(rol.getCodigo(), rol.getNombre()))
                .toList();
    }

    public UsuarioResponse convertirAUsuarioResponse(Usuario usuario) {
        return tenantMemberships.response(tenantMemberships.require(usuario.getId()));
    }

    @Transactional
    public void eliminarUsuario(Long idUsuario, Usuario actor) {
        editarUsuario(idUsuario, new UsuarioModificacionRequest(null, null, null, false), actor);
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

    private Set<Rol> rolesParaEdicion(Set<String> codigos, Set<Rol> rolesActuales) {
        Map<String, Rol> actualesPorCodigo = rolesActuales.stream()
                .collect(Collectors.toMap(
                        rol -> rol.getCodigo().toUpperCase(),
                        rol -> rol
                ));
        Set<Rol> result = new LinkedHashSet<>();

        for (String codigo : codigos) {
            String normalizado = normalizarCodigoRol(codigo);
            Rol actual = actualesPorCodigo.get(normalizado);
            if (actual != null) {
                result.add(actual);
                continue;
            }

            result.add(roles.findWithPermisosByCodigoIgnoreCase(normalizado)
                    .or(() -> roles.findByDescripcionIgnoreCase(normalizado))
                    .filter(Rol::estaActivo)
                    .orElseThrow(() -> new IllegalArgumentException("Rol no válido o inactivo: " + codigo)));
        }

        return result;
    }

    private void validarAsignacionPermitida(TenantAccess actor, Set<Rol> rolesObjetivo) {
        if (actor.membership().isSuperadmin()) {
            return;
        }

        if (contieneSuperadmin(rolesObjetivo)) {
            throw new OperacionNoPermitidaException("Sólo SUPERADMIN sistema puede asignar SUPERADMIN");
        }

        Set<String> permisosActor = actor.permissionCodes();

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

    private static Set<String> permisosActivos(Rol rol) {
        return rol.getPermisos().stream()
                .filter(permiso -> Boolean.TRUE.equals(permiso.getActivo()))
                .map(permiso -> permiso.getCodigo())
                .collect(Collectors.toSet());
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

    private static Map<String, ?> snapshot(TenantMembership membership) {
        Usuario usuario = membership.getUsuario();
        return Map.of(
                "username", usuario.getNombreUsuario(),
                "roles", membership.roleCodes(),
                "permisos", membership.permissionCodes(),
                "activo", membership.getStatus() == TenantMembershipStatus.ACTIVE,
                "membershipSecurityVersion", membership.getSecurityVersion()
        );
    }

    private static String id(Usuario usuario) {
        return usuario.getId() == null ? null : usuario.getId().toString();
    }
}
