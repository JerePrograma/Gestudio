package ledance.servicios.rol;

import ledance.auditoria.application.AuditService;
import ledance.dto.permiso.response.PermisoResponse;
import ledance.dto.rol.RolMapper;
import ledance.dto.rol.request.RolModificacionRequest;
import ledance.dto.rol.request.RolPermisosRequest;
import ledance.dto.rol.request.RolRegistroRequest;
import ledance.dto.rol.response.RolDetalleResponse;
import ledance.dto.rol.response.RolResponse;
import ledance.entidades.Permiso;
import ledance.entidades.Rol;
import ledance.entidades.Usuario;
import ledance.infra.errores.TratadorDeErrores.OperacionNoPermitidaException;
import ledance.repositorios.PermisoRepositorio;
import ledance.repositorios.RolRepositorio;
import ledance.repositorios.UsuarioRepositorio;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Comparator;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

@Service
public class RolServicio {
    private final RolRepositorio roles;
    private final PermisoRepositorio permisos;
    private final UsuarioRepositorio usuarios;
    private final RolMapper mapper;
    private final AuditService audit;

    public RolServicio(RolRepositorio roles, PermisoRepositorio permisos, UsuarioRepositorio usuarios,
                       RolMapper mapper, AuditService audit) {
        this.roles = roles;
        this.permisos = permisos;
        this.usuarios = usuarios;
        this.mapper = mapper;
        this.audit = audit;
    }

    @Transactional(readOnly = true)
    public RolDetalleResponse obtenerRolPorId(Long id) {
        return detalle(buscar(id));
    }

    @Transactional(readOnly = true)
    public List<RolResponse> listarRoles() {
        return roles.findAllByOrderByNombreAsc().stream().map(mapper::toDTO).toList();
    }

    @Transactional
    public RolDetalleResponse crear(RolRegistroRequest request, Usuario actor) {
        String codigo = normalizarCodigo(request.codigo());
        if (roles.existsByCodigoIgnoreCase(codigo) || roles.existsByDescripcion(codigo)) {
            throw new IllegalArgumentException("Ya existe un rol con el código " + codigo);
        }
        Rol rol = new Rol();
        rol.setCodigo(codigo);
        rol.setDescripcion(codigo);
        rol.setNombre(request.nombre().trim());
        rol.setDescripcionFuncional(limpiar(request.descripcionFuncional()));
        rol.setActivo(true);
        rol.setSistema(false);
        rol.setEditable(true);
        rol = roles.save(rol);
        audit.registrar("SEGURIDAD", "ROL_CREADO", "ROL", rol.getId().toString(), actor,
                null, null, null, snapshot(rol), Map.of());
        return detalle(rol);
    }

    @Transactional
    public RolDetalleResponse modificar(Long id, RolModificacionRequest request, Usuario actor) {
        Rol rol = buscarEditable(id);
        Map<String, ?> anterior = snapshot(rol);
        boolean cambiaEstado = request.activo() != null && request.activo() != Boolean.TRUE.equals(rol.getActivo());
        if (Boolean.FALSE.equals(request.activo())) validarDesactivacion(rol);
        rol.setNombre(request.nombre().trim());
        rol.setDescripcionFuncional(limpiar(request.descripcionFuncional()));
        if (request.activo() != null) rol.setActivo(request.activo());
        if (cambiaEstado) invalidarUsuarios(rol);
        audit.registrar("SEGURIDAD", "ROL_MODIFICADO", "ROL", rol.getId().toString(), actor,
                null, null, anterior, snapshot(rol), Map.of());
        return detalle(rol);
    }

    @Transactional
    public void desactivar(Long id, Usuario actor) {
        Rol rol = buscarEditable(id);
        validarDesactivacion(rol);
        Map<String, ?> anterior = snapshot(rol);
        rol.setActivo(false);
        invalidarUsuarios(rol);
        audit.registrar("SEGURIDAD", "ROL_DESACTIVADO", "ROL", rol.getId().toString(), actor,
                null, null, anterior, snapshot(rol), Map.of());
    }

    @Transactional
    public RolDetalleResponse asignarPermisos(Long id, RolPermisosRequest request, Usuario actor) {
        Rol rol = buscarEditable(id);
        Set<String> codigos = request.permisos().stream()
                .map(RolServicio::normalizarCodigoPermiso)
                .collect(Collectors.toCollection(LinkedHashSet::new));
        List<Permiso> encontrados = permisos.findByCodigoInAndActivoTrue(codigos);
        if (encontrados.size() != codigos.size()) {
            throw new IllegalArgumentException("Uno o más permisos no existen o están inactivos");
        }
        Set<String> anteriores = rol.getPermisos().stream().map(Permiso::getCodigo)
                .collect(Collectors.toCollection(LinkedHashSet::new));
        rol.setPermisos(encontrados.stream()
                .sorted(Comparator.comparing(Permiso::getCodigo))
                .collect(Collectors.toCollection(LinkedHashSet::new)));
        roles.save(rol);
        if (!anteriores.equals(codigos)) invalidarUsuarios(rol);
        audit.registrar("SEGURIDAD", "PERMISOS_ROL_MODIFICADOS", "ROL", rol.getId().toString(), actor,
                null, null, Map.of("permisos", anteriores), Map.of("permisos", codigos), Map.of());
        return detalle(rol);
    }

    private Rol buscar(Long id) {
        return roles.findById(id).orElseThrow(() -> new IllegalArgumentException("Rol no encontrado"));
    }

    private Rol buscarEditable(Long id) {
        Rol rol = buscar(id);
        if (Boolean.TRUE.equals(rol.getSistema()) || !Boolean.TRUE.equals(rol.getEditable())) {
            throw new OperacionNoPermitidaException("Los roles de sistema no se pueden modificar");
        }
        return rol;
    }

    private void validarDesactivacion(Rol rol) {
        if (Boolean.FALSE.equals(rol.getActivo())) return;
        boolean dejaUsuarioSinRol = usuarios.findByRoleCode(rol.getCodigo()).stream()
                .filter(Usuario::isEnabled)
                .anyMatch(usuario -> usuario.getRoles().stream()
                        .filter(asignado -> !asignado.getId().equals(rol.getId()))
                        .noneMatch(asignado -> Boolean.TRUE.equals(asignado.getActivo())));
        if (dejaUsuarioSinRol) {
            throw new OperacionNoPermitidaException("El rol está en uso y dejaría usuarios activos sin acceso");
        }
    }

    private void invalidarUsuarios(Rol rol) {
        usuarios.findByRoleCode(rol.getCodigo()).forEach(usuario -> {
            usuario.setAuthVersion(usuario.getAuthVersion() + 1);
            usuarios.save(usuario);
        });
    }

    private RolDetalleResponse detalle(Rol rol) {
        return new RolDetalleResponse(rol.getId(), rol.getCodigo(), rol.getNombre(),
                rol.getDescripcionFuncional(), rol.getActivo(), rol.getSistema(), rol.getEditable(),
                rol.getPermisos().stream().sorted(Comparator.comparing(Permiso::getModulo)
                                .thenComparing(Permiso::getCodigo))
                        .map(PermisoResponse::from).toList());
    }

    private static Map<String, ?> snapshot(Rol rol) {
        return Map.of(
                "codigo", rol.getCodigo(),
                "nombre", rol.getNombre(),
                "activo", Boolean.TRUE.equals(rol.getActivo()),
                "permisos", rol.getPermisos().stream().map(Permiso::getCodigo).sorted().toList());
    }

    private static String normalizarCodigo(String value) {
        String codigo = value == null ? "" : value.trim().toUpperCase(Locale.ROOT)
                .replaceAll("[^A-Z0-9]+", "_").replaceAll("^_+|_+$", "");
        if (!codigo.matches("[A-Z][A-Z0-9_]{1,49}")) {
            throw new IllegalArgumentException("El código debe ser uppercase snake case y tener hasta 50 caracteres");
        }
        return codigo;
    }

    private static String normalizarCodigoPermiso(String value) {
        String codigo = value == null ? "" : value.trim().toUpperCase(Locale.ROOT);
        if (!codigo.matches("[A-Z][A-Z0-9_]{1,99}")) {
            throw new IllegalArgumentException("Código de permiso inválido: " + value);
        }
        return codigo;
    }

    private static String limpiar(String value) {
        return value == null || value.isBlank() ? null : value.trim();
    }
}
