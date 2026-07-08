package ledance.servicios.rol;

import ledance.auditoria.application.AuditService;
import ledance.dto.rol.RolMapper;
import ledance.dto.rol.request.RolPermisosRequest;
import ledance.dto.rol.request.RolRegistroRequest;
import ledance.dto.rol.request.RolModificacionRequest;
import ledance.entidades.Permiso;
import ledance.entidades.Rol;
import ledance.entidades.Usuario;
import ledance.infra.errores.TratadorDeErrores.OperacionNoPermitidaException;
import ledance.repositorios.PermisoRepositorio;
import ledance.repositorios.RolRepositorio;
import ledance.repositorios.UsuarioRepositorio;
import org.junit.jupiter.api.Test;

import java.util.LinkedHashSet;
import java.util.List;
import java.util.Optional;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class RolServicioTest {
    private final RolRepositorio roles = mock(RolRepositorio.class);
    private final PermisoRepositorio permisos = mock(PermisoRepositorio.class);
    private final UsuarioRepositorio usuarios = mock(UsuarioRepositorio.class);
    private final AuditService audit = mock(AuditService.class);
    private final RolServicio service = new RolServicio(roles, permisos, usuarios, mock(RolMapper.class), audit);

    @Test
    void creaRolActivoConPermisosEnUnaSolaOperacion() {
        Usuario actor = usuario(1L, rol(1L, "SUPERADMIN", "ROLES_WRITE"));
        Permiso alumnosRead = permiso("ALUMNOS_READ");
        when(permisos.findByCodigoInAndActivoTrue(Set.of("ALUMNOS_READ"))).thenReturn(List.of(alumnosRead));
        when(roles.save(any(Rol.class))).thenAnswer(invocation -> {
            Rol saved = invocation.getArgument(0);
            saved.setId(10L);
            return saved;
        });

        var result = service.crear(new RolRegistroRequest(
                "OPERADOR", "Operador", null, Set.of("ALUMNOS_READ")), actor);

        assertThat(result.activo()).isTrue();
        assertThat(result.permisos()).extracting("codigo").containsExactly("ALUMNOS_READ");
    }

    @Test
    void rechazaPrefijoReservadoParaEvitarAuthorityDuplicada() {
        Usuario actor = usuario(1L, rol(1L, "SUPERADMIN", "ROLES_WRITE"));

        assertThatThrownBy(() -> service.crear(new RolRegistroRequest(
                "ROLE_OPERADOR", "Operador", null, Set.of("ALUMNOS_READ")), actor))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("sin prefijo ROLE_");
        verify(roles, never()).save(any());
    }

    @Test
    void rechazaAgregarPermisoQueElActorNoPosee() {
        Rol editable = rol(10L, "OPERADOR", "ALUMNOS_READ");
        Usuario actor = usuario(20L, rol(20L, "GESTOR_ROLES", "ROLES_WRITE"));
        Permiso pagosWrite = permiso("PAGOS_WRITE");
        when(roles.findById(10L)).thenReturn(Optional.of(editable));
        when(permisos.findByCodigoInAndActivoTrue(Set.of("ALUMNOS_READ", "PAGOS_WRITE")))
                .thenReturn(List.of(editable.getPermisos().iterator().next(), pagosWrite));

        assertThatThrownBy(() -> service.asignarPermisos(10L,
                new RolPermisosRequest(Set.of("ALUMNOS_READ", "PAGOS_WRITE")), actor))
                .isInstanceOf(OperacionNoPermitidaException.class)
                .hasMessageContaining("permisos superiores");
        verify(roles, never()).save(editable);
    }

    @Test
    void cambioDePermisosInvalidaUsuariosAsignados() {
        Rol editable = rol(10L, "OPERADOR", "ALUMNOS_READ");
        Usuario actor = usuario(1L, rol(1L, "SUPERADMIN", "ROLES_WRITE"));
        Usuario asignado = usuario(30L, editable);
        Permiso pagosRead = permiso("PAGOS_READ");
        when(roles.findById(10L)).thenReturn(Optional.of(editable));
        when(permisos.findByCodigoInAndActivoTrue(Set.of("PAGOS_READ"))).thenReturn(List.of(pagosRead));
        when(usuarios.findByRoleCode("OPERADOR")).thenReturn(List.of(asignado));

        service.asignarPermisos(10L, new RolPermisosRequest(Set.of("PAGOS_READ")), actor);

        assertThat(asignado.getAuthVersion()).isOne();
        verify(usuarios).save(asignado);
    }

    @Test
    void modificaMetadatosYPermisosEnLaMismaTransaccion() {
        Rol editable = rol(10L, "OPERADOR", "ALUMNOS_READ");
        Usuario actor = usuario(1L, rol(1L, "SUPERADMIN", "ROLES_WRITE"));
        Usuario asignado = usuario(30L, editable);
        Permiso pagosRead = permiso("PAGOS_READ");
        when(roles.findById(10L)).thenReturn(Optional.of(editable));
        when(permisos.findByCodigoInAndActivoTrue(Set.of("PAGOS_READ"))).thenReturn(List.of(pagosRead));
        when(usuarios.findByRoleCode("OPERADOR")).thenReturn(List.of(asignado));

        service.modificar(10L, new RolModificacionRequest(
                "Operador de pagos", null, true, Set.of("PAGOS_READ")), actor);

        assertThat(editable.getNombre()).isEqualTo("Operador de pagos");
        assertThat(editable.getPermisos()).extracting("codigo").containsExactly("PAGOS_READ");
        assertThat(asignado.getAuthVersion()).isOne();
    }

    private static Rol rol(Long id, String codigo, String... codigosPermiso) {
        Rol rol = new Rol(id, codigo, true);
        rol.setSistema(false);
        rol.setEditable(true);
        for (String codigoPermiso : codigosPermiso) rol.getPermisos().add(permiso(codigoPermiso));
        return rol;
    }

    private static Permiso permiso(String codigo) {
        Permiso permiso = new Permiso();
        permiso.setCodigo(codigo);
        permiso.setDescripcion(codigo);
        permiso.setModulo("TEST");
        permiso.setActivo(true);
        return permiso;
    }

    private static Usuario usuario(Long id, Rol... roles) {
        Usuario usuario = new Usuario();
        usuario.setId(id);
        usuario.setNombreUsuario("usuario-" + id);
        usuario.setRol(roles[0]);
        usuario.setRoles(new LinkedHashSet<>(List.of(roles)));
        usuario.setActivo(true);
        usuario.setAuthVersion(0L);
        return usuario;
    }
}
