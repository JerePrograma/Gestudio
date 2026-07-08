package gestudio.servicios.rol;

import gestudio.auditoria.application.AuditFailureService;
import gestudio.dto.rol.RolMapper;
import gestudio.dto.rol.request.RolModificacionRequest;
import gestudio.dto.rol.request.RolPermisosRequest;
import gestudio.dto.rol.request.RolRegistroRequest;
import gestudio.entidades.Permiso;
import gestudio.entidades.Rol;
import gestudio.entidades.Usuario;
import gestudio.infra.errores.TratadorDeErrores.OperacionNoPermitidaException;
import gestudio.infra.seguridad.RbacService;
import gestudio.repositorios.PermisoRepositorio;
import gestudio.repositorios.RolRepositorio;
import gestudio.repositorios.UsuarioRepositorio;
import org.junit.jupiter.api.Test;

import java.util.LinkedHashSet;
import java.util.List;
import java.util.Optional;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class RolServicioTest {

    private final RolRepositorio roles = mock(RolRepositorio.class);
    private final PermisoRepositorio permisos = mock(PermisoRepositorio.class);
    private final UsuarioRepositorio usuarios = mock(UsuarioRepositorio.class);
    private final AuditFailureService auditFailures = mock(AuditFailureService.class);

    private final RolMapper mapper = new RolMapper() {
    };

    private final RbacService rbac = new RbacService(usuarios, auditFailures);

    private final RolServicio service = new RolServicio(
            roles,
            permisos,
            usuarios,
            mapper,
            rbac
    );

    @Test
    void creaRolActivoConPermisosEnUnaSolaOperacion() {
        Usuario actor = usuario(1L, rol(1L, "SUPERADMIN", "PERM_ROLES_ADMIN"));
        Permiso alumnosRead = permiso("PERM_ALUMNOS_LEER");

        when(usuarios.findByIdConRolesYPermisos(actor.getId()))
                .thenReturn(Optional.of(actor));

        when(roles.existsByCodigoIgnoreCase("OPERADOR"))
                .thenReturn(false);

        when(permisos.findByCodigoIgnoreCase("PERM_ALUMNOS_LEER"))
                .thenReturn(Optional.of(alumnosRead));

        when(roles.saveAndFlush(any(Rol.class)))
                .thenAnswer(invocation -> {
                    Rol saved = invocation.getArgument(0);
                    saved.setId(10L);
                    return saved;
                });

        var result = service.crearRol(
                new RolRegistroRequest(
                        "OPERADOR",
                        "Operador",
                        null,
                        Set.of("PERM_ALUMNOS_LEER")
                ),
                actor
        );

        assertThat(result.activo()).isTrue();
        assertThat(result.permisos()).extracting("codigo").containsExactly("PERM_ALUMNOS_LEER");
    }

    @Test
    void rechazaCodigoRolInvalido() {
        Usuario actor = usuario(1L, rol(1L, "SUPERADMIN", "PERM_ROLES_ADMIN"));

        when(usuarios.findByIdConRolesYPermisos(actor.getId()))
                .thenReturn(Optional.of(actor));

        assertThatThrownBy(() -> service.crearRol(
                new RolRegistroRequest(
                        "1_OPERADOR",
                        "Operador",
                        null,
                        Set.of("PERM_ALUMNOS_LEER")
                ),
                actor
        ))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("Código de rol inválido");

        verify(roles, never()).saveAndFlush(any());
    }

    @Test
    void rechazaAgregarPermisoQueElActorNoPosee() {
        Rol editable = rol(10L, "OPERADOR", "PERM_ALUMNOS_LEER");
        Usuario actor = usuario(20L, rol(20L, "GESTOR_ROLES", "PERM_ROLES_ADMIN"));

        Permiso alumnosRead = editable.getPermisos().iterator().next();
        Permiso pagosAdmin = permiso("PERM_PAGOS_ADMIN");

        when(usuarios.findByIdConRolesYPermisos(actor.getId()))
                .thenReturn(Optional.of(actor));

        when(roles.findWithPermisosById(10L))
                .thenReturn(Optional.of(editable));

        when(permisos.findByCodigoIgnoreCase("PERM_ALUMNOS_LEER"))
                .thenReturn(Optional.of(alumnosRead));

        when(permisos.findByCodigoIgnoreCase("PERM_PAGOS_ADMIN"))
                .thenReturn(Optional.of(pagosAdmin));

        assertThatThrownBy(() -> service.actualizarPermisos(
                10L,
                new RolPermisosRequest(Set.of("PERM_ALUMNOS_LEER", "PERM_PAGOS_ADMIN")),
                actor
        ))
                .isInstanceOf(OperacionNoPermitidaException.class)
                .hasMessageContaining("No se puede asignar un permiso");

        verify(roles, never()).saveAndFlush(editable);
    }

    @Test
    void cambioDePermisosInvalidaUsuariosAsignados() {
        Rol editable = rol(10L, "OPERADOR", "PERM_ALUMNOS_LEER");
        Usuario actor = usuario(1L, rol(1L, "SUPERADMIN", "PERM_ROLES_ADMIN"));

        Permiso pagosRead = permiso("PERM_PAGOS_LEER");

        when(usuarios.findByIdConRolesYPermisos(actor.getId()))
                .thenReturn(Optional.of(actor));

        when(roles.findWithPermisosById(10L))
                .thenReturn(Optional.of(editable));

        when(permisos.findByCodigoIgnoreCase("PERM_PAGOS_LEER"))
                .thenReturn(Optional.of(pagosRead));

        when(roles.saveAndFlush(editable))
                .thenReturn(editable);

        service.actualizarPermisos(
                10L,
                new RolPermisosRequest(Set.of("PERM_PAGOS_LEER")),
                actor
        );

        assertThat(editable.getPermisos()).extracting("codigo").containsExactly("PERM_PAGOS_LEER");
        verify(usuarios).incrementarAuthVersionPorRolId(10L);
    }

    @Test
    void modificaMetadatosYPermisosEnLaMismaTransaccion() {
        Rol editable = rol(10L, "OPERADOR", "PERM_ALUMNOS_LEER");
        Usuario actor = usuario(1L, rol(1L, "SUPERADMIN", "PERM_ROLES_ADMIN"));

        Permiso pagosRead = permiso("PERM_PAGOS_LEER");

        when(usuarios.findByIdConRolesYPermisos(actor.getId()))
                .thenReturn(Optional.of(actor));

        when(roles.findWithPermisosById(10L))
                .thenReturn(Optional.of(editable));

        when(permisos.findByCodigoIgnoreCase("PERM_PAGOS_LEER"))
                .thenReturn(Optional.of(pagosRead));

        when(roles.saveAndFlush(editable))
                .thenReturn(editable);

        service.actualizarRol(
                10L,
                new RolModificacionRequest(
                        "Operador de pagos",
                        null,
                        true,
                        Set.of("PERM_PAGOS_LEER")
                ),
                actor
        );

        assertThat(editable.getNombre()).isEqualTo("Operador de pagos");
        assertThat(editable.getPermisos()).extracting("codigo").containsExactly("PERM_PAGOS_LEER");

        verify(usuarios).incrementarAuthVersionPorRolId(10L);
    }

    private static Rol rol(Long id, String codigo, String... codigosPermiso) {
        Rol rol = new Rol(id, codigo, true);
        rol.setSistema("SUPERADMIN".equals(codigo) || "ADMINISTRADOR".equals(codigo));
        rol.setEditable(!"SUPERADMIN".equals(codigo));

        for (String codigoPermiso : codigosPermiso) {
            rol.getPermisos().add(permiso(codigoPermiso));
        }

        return rol;
    }

    private static Permiso permiso(String codigo) {
        Permiso permiso = new Permiso();
        permiso.setCodigo(codigo);
        permiso.setDescripcion(codigo);
        permiso.setModulo("TEST");
        permiso.setActivo(true);
        permiso.setSistema(true);
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