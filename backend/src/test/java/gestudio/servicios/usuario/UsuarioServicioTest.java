package gestudio.servicios.usuario;

import gestudio.auditoria.application.AuditFailureService;
import gestudio.auditoria.application.AuditService;
import gestudio.dto.usuario.UsuarioMapper;
import gestudio.dto.usuario.request.UsuarioModificacionRequest;
import gestudio.dto.usuario.request.UsuarioRegistroRequest;
import gestudio.entidades.Permiso;
import gestudio.entidades.Rol;
import gestudio.entidades.Usuario;
import gestudio.infra.errores.TratadorDeErrores.OperacionNoPermitidaException;
import gestudio.infra.seguridad.PasswordPolicy;
import gestudio.infra.seguridad.RbacService;
import gestudio.repositorios.RolRepositorio;
import gestudio.repositorios.UsuarioRepositorio;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
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

class UsuarioServicioTest {

    private final UsuarioRepositorio usuarios = mock(UsuarioRepositorio.class);
    private final PasswordEncoder encoder = mock(PasswordEncoder.class);
    private final RolRepositorio roles = mock(RolRepositorio.class);
    private final UsuarioMapper mapper = mock(UsuarioMapper.class);
    private final AuditService audit = mock(AuditService.class);
    private final AuditFailureService auditFailures = mock(AuditFailureService.class);

    private final Clock clock = Clock.fixed(
            Instant.parse("2026-07-03T12:00:00Z"),
            ZoneOffset.UTC
    );

    private final RbacService rbac = new RbacService(usuarios, auditFailures);

    private final UsuarioServicio service = new UsuarioServicio(
            usuarios,
            encoder,
            new PasswordPolicy(),
            roles,
            mapper,
            clock,
            audit,
            rbac
    );

    private Rol superadmin;
    private Rol recepcion;
    private Usuario actor;

    @BeforeEach
    void setUp() {
        superadmin = rol(
                1L,
                "SUPERADMIN",
                "PERM_APP_ACCESO",
                "PERM_USUARIOS_ADMIN"
        );

        recepcion = rol(
                2L,
                "RECEPCION",
                "PERM_APP_ACCESO"
        );

        actor = usuario(1L, "root", true, superadmin);

        when(usuarios.findByIdConRolesYPermisos(actor.getId()))
                .thenReturn(Optional.of(actor));

        when(roles.findWithPermisosByCodigoIgnoreCase("SUPERADMIN"))
                .thenReturn(Optional.of(superadmin));

        when(roles.findWithPermisosByCodigoIgnoreCase("RECEPCION"))
                .thenReturn(Optional.of(recepcion));
    }

    @Test
    void creaUsuarioConMultiplesRolesYConservaRolLegado() {
        Usuario nuevo = new Usuario();

        when(usuarios.findByNombreUsuarioIgnoreCase("nuevo-root"))
                .thenReturn(Optional.empty());

        when(mapper.toEntity(any()))
                .thenReturn(nuevo);

        when(encoder.encode("clave-superadmin-segura"))
                .thenReturn("hash");

        when(usuarios.saveAndFlush(any(Usuario.class)))
                .thenAnswer(invocation -> {
                    Usuario saved = invocation.getArgument(0);
                    saved.setId(10L);
                    return saved;
                });

        when(usuarios.findByIdConRolesYPermisos(10L))
                .thenAnswer(invocation -> Optional.of(nuevo));

        service.registrarUsuario(
                new UsuarioRegistroRequest(
                        " nuevo-root ",
                        "clave-superadmin-segura",
                        Set.of("RECEPCION", "SUPERADMIN")
                ),
                actor
        );

        assertThat(nuevo.getRoles()).containsExactlyInAnyOrder(superadmin, recepcion);
        assertThat(nuevo.getRol()).isEqualTo(superadmin);
        assertThat(nuevo.getContrasena()).isEqualTo("hash");
        assertThat(nuevo.getPasswordChangedAt()).isEqualTo(clock.instant());

        verify(usuarios).saveAndFlush(nuevo);
    }

    @Test
    void actorSinPermisoNoPuedeAdministrarUsuarios() {
        Usuario profesor = usuario(
                3L,
                "profesor",
                true,
                rol(3L, "PROFESOR", "PERM_APP_ACCESO")
        );

        when(usuarios.findByIdConRolesYPermisos(profesor.getId()))
                .thenReturn(Optional.of(profesor));

        assertThatThrownBy(() -> service.registrarUsuario(
                new UsuarioRegistroRequest(
                        "otro",
                        "clave-segura-usuario",
                        Set.of("RECEPCION")
                ),
                profesor
        ))
                .isInstanceOf(AccessDeniedException.class);

        verify(usuarios, never()).saveAndFlush(any());
    }

    @Test
    void faltaDeSuperadminEs403YAunRegistraElIntento() {
        Usuario gestor = usuario(
                4L,
                "gestor",
                true,
                rol(4L, "GESTOR_USUARIOS", "PERM_USUARIOS_ADMIN")
        );
        when(usuarios.findByIdConRolesYPermisos(gestor.getId())).thenReturn(Optional.of(gestor));

        assertThatThrownBy(() -> rbac.exigirSuperadminSistema(gestor, "OPERACION_SENSIBLE"))
                .isInstanceOf(AccessDeniedException.class);

        verify(auditFailures).registrarEscalamiento(gestor, "OPERACION_SENSIBLE");
    }

    @Test
    void actorNoPuedeAsignarRolConPermisosQueNoPosee() {
        Rol gestor = rol(4L, "GESTOR_USUARIOS", "PERM_USUARIOS_ADMIN");
        Usuario gestorUsuarios = usuario(4L, "gestor", true, gestor);

        when(usuarios.findByIdConRolesYPermisos(gestorUsuarios.getId()))
                .thenReturn(Optional.of(gestorUsuarios));

        assertThatThrownBy(() -> service.registrarUsuario(
                new UsuarioRegistroRequest(
                        "nuevo",
                        "clave-segura-usuario",
                        Set.of("RECEPCION")
                ),
                gestorUsuarios
        ))
                .isInstanceOf(OperacionNoPermitidaException.class)
                .hasMessageContaining("permisos");

        verify(usuarios, never()).saveAndFlush(any());
    }

    @Test
    void listaSoloRolesQueElAdministradorDeUsuariosPuedeAsignar() {
        Rol direccion = rol(4L, "DIRECCION", "PERM_APP_ACCESO", "PERM_USUARIOS_ADMIN");
        Rol caja = rol(5L, "CAJA", "PERM_APP_ACCESO");
        Rol profesor = rol(6L, "PROFESOR");
        Rol privilegiado = rol(7L, "PRIVILEGIADO", "PERM_ROLES_ADMIN");
        Usuario gestor = usuario(4L, "direccion", true, direccion);

        when(usuarios.findByIdConRolesYPermisos(gestor.getId())).thenReturn(Optional.of(gestor));
        when(roles.findAllByOrderByCodigoAsc())
                .thenReturn(List.of(caja, direccion, profesor, privilegiado, superadmin));

        assertThat(service.listarRolesAsignables(gestor))
                .extracting("codigo")
                .containsExactly("CAJA", "DIRECCION");
    }

    @Test
    void editarRolesInvalidaSesiones() {
        Usuario objetivo = usuario(8L, "operador", true, recepcion);

        when(usuarios.findByIdConRolesYPermisos(objetivo.getId()))
                .thenReturn(Optional.of(objetivo));

        when(usuarios.saveAndFlush(any(Usuario.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        service.editarUsuario(
                objetivo.getId(),
                new UsuarioModificacionRequest(
                        null,
                        null,
                        Set.of("SUPERADMIN", "RECEPCION"),
                        null
                ),
                actor
        );

        assertThat(objetivo.getRoles()).containsExactlyInAnyOrder(superadmin, recepcion);
        assertThat(objetivo.getAuthVersion()).isOne();

        verify(usuarios).saveAndFlush(objetivo);
    }

    @Test
    void editarOtrosDatosConservaProfesorInactivoSinVolverloAsignable() {
        Rol profesor = rol(9L, "PROFESOR");
        profesor.setActivo(false);
        Usuario objetivo = usuario(9L, "docente", true, profesor);

        when(usuarios.findByIdConRolesYPermisos(objetivo.getId()))
                .thenReturn(Optional.of(objetivo));
        when(usuarios.saveAndFlush(any(Usuario.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        service.editarUsuario(
                objetivo.getId(),
                new UsuarioModificacionRequest("docente-actualizado", null, Set.of("PROFESOR"), null),
                actor
        );

        assertThat(objetivo.getNombreUsuario()).isEqualTo("docente-actualizado");
        assertThat(objetivo.getRoles()).containsExactly(profesor);
        verify(roles, never()).findWithPermisosByCodigoIgnoreCase("PROFESOR");
        verify(usuarios).saveAndFlush(objetivo);
    }

    @Test
    void impidePerderUltimoSuperadmin() {
        when(usuarios.findActiveSuperadminsForUpdate())
                .thenReturn(java.util.List.of(actor));

        assertThatThrownBy(() -> service.editarUsuario(
                actor.getId(),
                new UsuarioModificacionRequest(
                        null,
                        null,
                        Set.of("RECEPCION"),
                        null
                ),
                actor
        ))
                .isInstanceOf(OperacionNoPermitidaException.class)
                .hasMessageContaining("último SUPERADMIN");

        verify(usuarios, never()).saveAndFlush(any());
    }

    @Test
    void passwordSuperadminCortoSeRechaza() {
        when(usuarios.findByNombreUsuarioIgnoreCase("nuevo-root"))
                .thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.registrarUsuario(
                new UsuarioRegistroRequest(
                        "nuevo-root",
                        "doce-caracter",
                        Set.of("SUPERADMIN")
                ),
                actor
        ))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("16 y 72");

        verify(usuarios, never()).saveAndFlush(any());
    }

    private static Rol rol(Long id, String codigo, String... permisos) {
        Rol rol = new Rol(id, codigo, true);
        rol.setSistema("SUPERADMIN".equals(codigo) || "ADMINISTRADOR".equals(codigo));
        rol.setEditable(!"SUPERADMIN".equals(codigo));

        for (String codigoPermiso : permisos) {
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

    private static Usuario usuario(Long id, String username, boolean activo, Rol... roles) {
        Usuario usuario = new Usuario();
        usuario.setId(id);
        usuario.setNombreUsuario(username);
        usuario.setContrasena("hash");
        usuario.setRol(roles[0]);
        usuario.setRoles(new LinkedHashSet<>(java.util.List.of(roles)));
        usuario.setActivo(activo);
        usuario.setAuthVersion(0L);
        return usuario;
    }
}
