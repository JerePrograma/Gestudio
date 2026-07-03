package ledance.servicios.usuario;

import ledance.auditoria.application.AuditFailureService;
import ledance.auditoria.application.AuditService;
import ledance.dto.usuario.UsuarioMapper;
import ledance.dto.usuario.request.UsuarioModificacionRequest;
import ledance.dto.usuario.request.UsuarioRegistroRequest;
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

    private Rol superadminRole;
    private Rol adminRole;
    private Usuario actor;

    @BeforeEach
    void setUp() {
        superadminRole = new Rol(1L, "SUPERADMIN", true);
        adminRole = new Rol(2L, "ADMINISTRADOR", true);
        actor = usuario(1L, "root", superadminRole, true);
        when(usuarios.findById(actor.getId())).thenReturn(Optional.of(actor));
        when(roles.findByDescripcionIgnoreCase("SUPERADMIN")).thenReturn(Optional.of(superadminRole));
        when(roles.findByDescripcionIgnoreCase("ADMINISTRADOR")).thenReturn(Optional.of(adminRole));
    }

    @Test
    void administradorNoPuedeCrearNiModificarUsuariosDesdeElServicio() {
        Usuario admin = usuario(2L, "admin", adminRole, true);
        when(usuarios.findById(admin.getId())).thenReturn(Optional.of(admin));

        assertThatThrownBy(() -> service.registrarUsuario(
                new UsuarioRegistroRequest("otro", "clave-segura-usuario", "SUPERADMIN"), admin))
                .isInstanceOf(OperacionNoPermitidaException.class);
        assertThatThrownBy(() -> service.editarUsuario(actor.getId(),
                new UsuarioModificacionRequest(null, null, "ADMINISTRADOR", null), admin))
                .isInstanceOf(OperacionNoPermitidaException.class);

        verify(usuarios, never()).save(any());
    }

    @Test
    void superadminPuedeCrearOtroSuperadminConPoliticaDePassword() {
        Usuario nuevo = new Usuario();
        when(usuarios.findByNombreUsuarioIgnoreCase("nuevo-root")).thenReturn(Optional.empty());
        when(mapper.toEntity(any())).thenReturn(nuevo);
        when(encoder.encode("clave-superadmin-segura")).thenReturn("hash");

        service.registrarUsuario(new UsuarioRegistroRequest(
                "  nuevo-root  ", "clave-superadmin-segura", "SUPERADMIN"), actor);

        assertThat(nuevo.getNombreUsuario()).isEqualTo("nuevo-root");
        assertThat(nuevo.getRol()).isEqualTo(superadminRole);
        assertThat(nuevo.getContrasena()).isEqualTo("hash");
        assertThat(nuevo.getPasswordChangedAt()).isEqualTo(clock.instant());
        verify(usuarios).save(nuevo);
    }

    @Test
    void noPermiteDesactivarAlUltimoSuperadminActivo() {
        when(usuarios.findActiveSuperadminsForUpdate()).thenReturn(List.of(actor));

        assertThatThrownBy(() -> service.eliminarUsuario(actor.getId(), actor))
                .isInstanceOf(OperacionNoPermitidaException.class)
                .hasMessageContaining("último SUPERADMIN");

        verify(usuarios, never()).save(any());
    }

    @Test
    void bajaLogicaConservaUsuarioEInvalidaAutenticacion() {
        Usuario otroRoot = usuario(3L, "root-2", superadminRole, true);
        Usuario objetivo = usuario(8L, "admin", adminRole, true);
        when(usuarios.findById(objetivo.getId())).thenReturn(Optional.of(objetivo));
        when(usuarios.findByIdForUpdate(objetivo.getId())).thenReturn(Optional.of(objetivo));
        when(usuarios.findActiveSuperadminsForUpdate()).thenReturn(List.of(actor, otroRoot));

        service.eliminarUsuario(objetivo.getId(), actor);

        assertThat(objetivo.getActivo()).isFalse();
        assertThat(objetivo.getAuthVersion()).isOne();
        verify(usuarios).save(objetivo);
        verify(usuarios, never()).deleteById(objetivo.getId());
    }

    @Test
    void passwordSuperadminCortoSeRechaza() {
        when(usuarios.findByNombreUsuarioIgnoreCase("nuevo-root")).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.registrarUsuario(
                new UsuarioRegistroRequest("nuevo-root", "doce-caracter", "SUPERADMIN"), actor))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("16 y 72");
        verify(usuarios, never()).save(any());
    }

    private static Usuario usuario(Long id, String username, Rol rol, boolean activo) {
        Usuario usuario = new Usuario();
        usuario.setId(id);
        usuario.setNombreUsuario(username);
        usuario.setContrasena("hash");
        usuario.setRol(rol);
        usuario.setActivo(activo);
        usuario.setAuthVersion(0L);
        return usuario;
    }
}
