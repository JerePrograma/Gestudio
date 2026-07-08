package ledance.servicios.usuario;

import ledance.auditoria.application.AuditFailureService;
import ledance.auditoria.application.AuditService;
import ledance.dto.usuario.UsuarioMapper;
import ledance.dto.usuario.request.UsuarioModificacionRequest;
import ledance.dto.usuario.request.UsuarioRegistroRequest;
import ledance.entidades.Permiso;
import ledance.entidades.Rol;
import ledance.entidades.Usuario;
import ledance.infra.errores.TratadorDeErrores.OperacionNoPermitidaException;
import ledance.infra.seguridad.PasswordPolicy;
import ledance.repositorios.RolRepositorio;
import ledance.repositorios.UsuarioRepositorio;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Optional;

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
    private final Clock clock = Clock.fixed(Instant.parse("2026-07-03T12:00:00Z"), ZoneOffset.UTC);
    private final UsuarioServicio service = new UsuarioServicio(
            usuarios, encoder, new PasswordPolicy(), roles, mapper, clock, audit, auditFailures);

    private Rol superadmin;
    private Rol recepcion;
    private Usuario actor;

    @BeforeEach
    void setUp() {
        superadmin = rol(1L, "SUPERADMIN", "USUARIOS_WRITE", "USUARIOS_READ", "ALUMNOS_READ");
        recepcion = rol(2L, "RECEPCION", "ALUMNOS_READ");
        actor = usuario(1L, "root", true, superadmin);
        when(usuarios.findWithAuthoritiesById(actor.getId())).thenReturn(Optional.of(actor));
        when(roles.findByCodigoIgnoreCase("SUPERADMIN")).thenReturn(Optional.of(superadmin));
        when(roles.findByCodigoIgnoreCase("RECEPCION")).thenReturn(Optional.of(recepcion));
    }

    @Test
    void creaUsuarioConMultiplesRolesYConservaRolLegado() {
        Usuario nuevo = new Usuario();
        when(usuarios.findByNombreUsuarioIgnoreCase("nuevo-root")).thenReturn(Optional.empty());
        when(mapper.toEntity(any())).thenReturn(nuevo);
        when(encoder.encode("clave-superadmin-segura")).thenReturn("hash");

        service.registrarUsuario(new UsuarioRegistroRequest(
                " nuevo-root ", "clave-superadmin-segura", List.of("RECEPCION", "SUPERADMIN")), actor);

        assertThat(nuevo.getRoles()).containsExactlyInAnyOrder(superadmin, recepcion);
        assertThat(nuevo.getRol()).isEqualTo(superadmin);
        assertThat(nuevo.getContrasena()).isEqualTo("hash");
        assertThat(nuevo.getPasswordChangedAt()).isEqualTo(clock.instant());
        verify(usuarios).save(nuevo);
    }

    @Test
    void actorSinPermisoNoPuedeAdministrarUsuarios() {
        Usuario profesor = usuario(3L, "profesor", true, rol(3L, "PROFESOR", "ALUMNOS_READ"));
        when(usuarios.findWithAuthoritiesById(profesor.getId())).thenReturn(Optional.of(profesor));

        assertThatThrownBy(() -> service.registrarUsuario(
                new UsuarioRegistroRequest("otro", "clave-segura-usuario", List.of("RECEPCION")), profesor))
                .isInstanceOf(OperacionNoPermitidaException.class);
        verify(usuarios, never()).save(any());
    }

    @Test
    void editarRolesInvalidaSesiones() {
        Usuario objetivo = usuario(8L, "operador", true, recepcion);
        when(usuarios.findWithAuthoritiesById(objetivo.getId())).thenReturn(Optional.of(objetivo));
        when(usuarios.findByIdForUpdate(objetivo.getId())).thenReturn(Optional.of(objetivo));

        service.editarUsuario(objetivo.getId(),
                new UsuarioModificacionRequest(null, null, List.of("SUPERADMIN", "RECEPCION"), null), actor);

        assertThat(objetivo.getRoles()).containsExactlyInAnyOrder(superadmin, recepcion);
        assertThat(objetivo.getAuthVersion()).isOne();
        verify(usuarios).save(objetivo);
    }

    @Test
    void impidePerderUltimoSuperadmin() {
        when(usuarios.findWithAuthoritiesById(actor.getId())).thenReturn(Optional.of(actor));
        when(usuarios.findActiveSuperadminsForUpdate()).thenReturn(List.of(actor));

        assertThatThrownBy(() -> service.editarUsuario(actor.getId(),
                new UsuarioModificacionRequest(null, null, List.of("RECEPCION"), null), actor))
                .isInstanceOf(OperacionNoPermitidaException.class)
                .hasMessageContaining("último SUPERADMIN");
        verify(usuarios, never()).save(any());
    }

    @Test
    void passwordSuperadminCortoSeRechaza() {
        when(usuarios.findByNombreUsuarioIgnoreCase("nuevo-root")).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.registrarUsuario(
                new UsuarioRegistroRequest("nuevo-root", "doce-caracter", List.of("SUPERADMIN")), actor))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("16 y 72");
        verify(usuarios, never()).save(any());
    }

    private static Rol rol(Long id, String codigo, String... permisos) {
        Rol rol = new Rol(id, codigo, true);
        for (String codigoPermiso : permisos) {
            Permiso permiso = new Permiso();
            permiso.setCodigo(codigoPermiso);
            permiso.setDescripcion(codigoPermiso);
            permiso.setModulo("TEST");
            permiso.setActivo(true);
            rol.getPermisos().add(permiso);
        }
        return rol;
    }

    private static Usuario usuario(Long id, String username, boolean activo, Rol... roles) {
        Usuario usuario = new Usuario();
        usuario.setId(id);
        usuario.setNombreUsuario(username);
        usuario.setContrasena("hash");
        usuario.setRol(roles[0]);
        usuario.setRoles(new LinkedHashSet<>(List.of(roles)));
        usuario.setActivo(activo);
        usuario.setAuthVersion(0L);
        return usuario;
    }
}
