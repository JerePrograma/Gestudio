package gestudio.servicios.rol;

import gestudio.dto.rol.RolMapper;
import gestudio.dto.rol.request.RolModificacionRequest;
import gestudio.dto.rol.request.RolPermisosRequest;
import gestudio.dto.rol.request.RolRegistroRequest;
import gestudio.dto.rol.response.RolResponse;
import gestudio.entidades.Permiso;
import gestudio.entidades.Rol;
import gestudio.entidades.Usuario;
import gestudio.infra.errores.TratadorDeErrores.OperacionNoPermitidaException;
import gestudio.infra.seguridad.RbacService;
import gestudio.repositorios.PermisoRepositorio;
import gestudio.repositorios.RolRepositorio;
import gestudio.repositorios.UsuarioRepositorio;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

@Service
public class RolServicio {

    private static final String PERM_ROLES_ADMIN = "PERM_ROLES_ADMIN";

    private final RolRepositorio roles;
    private final PermisoRepositorio permisos;
    private final UsuarioRepositorio usuarios;
    private final RolMapper rolMapper;
    private final RbacService rbac;

    public RolServicio(RolRepositorio roles,
                       PermisoRepositorio permisos,
                       UsuarioRepositorio usuarios,
                       RolMapper rolMapper,
                       RbacService rbac) {
        this.roles = roles;
        this.permisos = permisos;
        this.usuarios = usuarios;
        this.rolMapper = rolMapper;
        this.rbac = rbac;
    }

    @Transactional(readOnly = true)
    public RolResponse obtenerRolPorId(Long id) {
        Rol rol = roles.findWithPermisosById(id)
                .orElseThrow(() -> new IllegalArgumentException("Rol no encontrado."));

        return rolMapper.toDTO(rol);
    }

    @Transactional(readOnly = true)
    public List<RolResponse> listarRoles() {
        return roles.findAllByOrderByCodigoAsc().stream()
                .map(rolMapper::toDTO)
                .toList();
    }

    @Transactional
    public RolResponse crearRol(RolRegistroRequest request, Usuario actor) {
        Usuario actorActual = rbac.exigirPermiso(actor, PERM_ROLES_ADMIN, "CREAR_ROL");

        String codigo = normalizarCodigoRol(request.codigo());

        if ("SUPERADMIN".equals(codigo)) {
            throw new OperacionNoPermitidaException("SUPERADMIN no puede crearse desde panel");
        }

        if (roles.existsByCodigoIgnoreCase(codigo)) {
            throw new IllegalArgumentException("Ya existe un rol con código: " + codigo);
        }

        Set<Permiso> permisosAsignados = permisosExistentes(request.permisos());
        validarNoEscalaPermisos(actorActual, permisosAsignados);

        Rol rol = new Rol();
        rol.setCodigo(codigo);
        rol.setDescripcion(codigo);
        rol.setNombre(request.nombre().trim());
        rol.setDescripcionFuncional(limpiar(request.descripcionFuncional()));
        rol.setActivo(true);
        rol.setSistema(false);
        rol.setEditable(true);
        rol.setPermisos(permisosAsignados);

        return rolMapper.toDTO(roles.saveAndFlush(rol));
    }

    @Transactional
    public RolResponse actualizarRol(Long id, RolModificacionRequest request, Usuario actor) {
        Usuario actorActual = rbac.exigirPermiso(actor, PERM_ROLES_ADMIN, "MODIFICAR_ROL");

        Rol rol = roles.findWithPermisosById(id)
                .orElseThrow(() -> new IllegalArgumentException("Rol no encontrado."));

        validarEditableDesdePanel(rol);

        Set<Permiso> permisosAsignados = request.permisos() == null
                ? new LinkedHashSet<>(rol.getPermisos())
                : permisosExistentes(request.permisos());

        validarNoEscalaPermisos(actorActual, permisosAsignados);

        rol.setNombre(request.nombre().trim());
        rol.setDescripcionFuncional(limpiar(request.descripcionFuncional()));

        if (request.activo() != null) {
            rol.setActivo(request.activo());
        }

        rol.setPermisos(permisosAsignados);

        Rol saved = roles.saveAndFlush(rol);
        usuarios.incrementarAuthVersionPorRolId(saved.getId());

        return rolMapper.toDTO(saved);
    }

    @Transactional
    public RolResponse actualizarPermisos(Long id, RolPermisosRequest request, Usuario actor) {
        Usuario actorActual = rbac.exigirPermiso(actor, PERM_ROLES_ADMIN, "MODIFICAR_PERMISOS_ROL");

        Rol rol = roles.findWithPermisosById(id)
                .orElseThrow(() -> new IllegalArgumentException("Rol no encontrado."));

        validarEditableDesdePanel(rol);

        Set<Permiso> permisosAsignados = permisosExistentes(request.permisos());
        validarNoEscalaPermisos(actorActual, permisosAsignados);

        rol.setPermisos(permisosAsignados);

        Rol saved = roles.saveAndFlush(rol);
        usuarios.incrementarAuthVersionPorRolId(saved.getId());

        return rolMapper.toDTO(saved);
    }

    @Transactional
    public RolResponse clonarRol(Long id, RolRegistroRequest request, Usuario actor) {
        Usuario actorActual = rbac.exigirPermiso(actor, PERM_ROLES_ADMIN, "CLONAR_ROL");

        Rol origen = roles.findWithPermisosById(id)
                .orElseThrow(() -> new IllegalArgumentException("Rol origen no encontrado."));

        String codigo = normalizarCodigoRol(request.codigo());

        if ("SUPERADMIN".equals(codigo)) {
            throw new OperacionNoPermitidaException("SUPERADMIN no puede crearse desde panel");
        }

        if (roles.existsByCodigoIgnoreCase(codigo)) {
            throw new IllegalArgumentException("Ya existe un rol con código: " + codigo);
        }

        Set<Permiso> permisosAsignados = request.permisos() == null || request.permisos().isEmpty()
                ? new LinkedHashSet<>(origen.getPermisos())
                : permisosExistentes(request.permisos());

        validarNoEscalaPermisos(actorActual, permisosAsignados);

        Rol clon = new Rol();
        clon.setCodigo(codigo);
        clon.setDescripcion(codigo);
        clon.setNombre(request.nombre().trim());
        clon.setDescripcionFuncional(limpiar(request.descripcionFuncional()));
        clon.setActivo(true);
        clon.setSistema(false);
        clon.setEditable(true);
        clon.setPermisos(permisosAsignados);

        return rolMapper.toDTO(roles.saveAndFlush(clon));
    }

    @Transactional
    public void desactivarRol(Long id, Usuario actor) {
        rbac.exigirPermiso(actor, PERM_ROLES_ADMIN, "DESACTIVAR_ROL");

        Rol rol = roles.findWithPermisosById(id)
                .orElseThrow(() -> new IllegalArgumentException("Rol no encontrado."));

        validarEditableDesdePanel(rol);

        if (!Boolean.TRUE.equals(rol.getActivo())) {
            return;
        }

        rol.setActivo(false);

        Rol saved = roles.saveAndFlush(rol);
        usuarios.incrementarAuthVersionPorRolId(saved.getId());
    }

    private void validarEditableDesdePanel(Rol rol) {
        if (rol.esSuperadminSistema()) {
            throw new OperacionNoPermitidaException("SUPERADMIN no puede editarse desde panel");
        }

        if (rol.esSistema() && !rol.esEditable()) {
            throw new OperacionNoPermitidaException("El rol sistema no es editable");
        }
    }

    private Set<Permiso> permisosExistentes(Set<String> codigos) {
        Set<Permiso> result = new LinkedHashSet<>();

        if (codigos == null) {
            return result;
        }

        for (String codigo : codigos) {
            String normalizado = normalizarCodigoPermiso(codigo);

            Permiso permiso = permisos.findByCodigoIgnoreCase(normalizado)
                    .filter(Permiso::estaActivo)
                    .orElseThrow(() -> new IllegalArgumentException("Permiso no válido o inactivo: " + codigo));

            result.add(permiso);
        }

        return result;
    }

    private void validarNoEscalaPermisos(Usuario actor, Set<Permiso> permisosAsignados) {
        if (actor.esSuperadminSistema()) {
            return;
        }

        Set<String> permisosActor = actor.codigosPermisosActivos();

        for (Permiso permiso : permisosAsignados) {
            if (!permisosActor.contains(permiso.getCodigo())) {
                throw new OperacionNoPermitidaException(
                        "No se puede asignar un permiso que el actor no posee: " + permiso.getCodigo()
                );
            }
        }
    }

    private static String normalizarCodigoRol(String codigo) {
        String normalizado = codigo == null ? "" : codigo.trim().toUpperCase();

        if (!normalizado.matches("^[A-Z][A-Z0-9_]{2,49}$")) {
            throw new IllegalArgumentException("Código de rol inválido: " + codigo);
        }

        return normalizado;
    }

    private static String normalizarCodigoPermiso(String codigo) {
        String normalizado = codigo == null ? "" : codigo.trim().toUpperCase();

        if (!normalizado.matches("^PERM_[A-Z0-9_]{3,95}$")) {
            throw new IllegalArgumentException("Código de permiso inválido: " + codigo);
        }

        return normalizado;
    }

    private static String limpiar(String value) {
        return value == null || value.isBlank() ? null : value.trim();
    }
}