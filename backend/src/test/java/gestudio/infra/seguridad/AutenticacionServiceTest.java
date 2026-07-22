package gestudio.infra.seguridad;

import gestudio.auditoria.application.AuditFailureService;
import gestudio.dto.request.LoginRequest;
import gestudio.entidades.RefreshSession;
import gestudio.entidades.Rol;
import gestudio.entidades.Usuario;
import gestudio.repositorios.UsuarioRepositorio;
import org.junit.jupiter.api.Test;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.authentication.ProviderManager;
import org.springframework.security.authentication.dao.DaoAuthenticationProvider;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.time.Instant;
import java.util.LinkedHashSet;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class AutenticacionServiceTest {

    private static final String PASSWORD = "clave-admin-segura";

    private final UsuarioRepositorio usuarios = mock(UsuarioRepositorio.class);
    private final RefreshSessionService sessions = mock(RefreshSessionService.class);
    private final AuditFailureService auditFailures = mock(AuditFailureService.class);
    private final PasswordEncoder passwordEncoder = new BCryptPasswordEncoder(4);

    private final AutenticacionService autenticacion = new AutenticacionService(
            authenticationManager(),
            sessions,
            auditFailures,
            usuarios
    );

    @Test
    void loginExitosoConUsuarioYRolActivosYBcryptValido() {
        Usuario usuario = usuario(true, true, passwordEncoder.encode(PASSWORD));

        when(usuarios.findByNombreUsuarioIgnoreCaseConRolesYPermisos("admin"))
                .thenReturn(Optional.of(usuario));
        when(usuarios.findByIdConRolesYPermisos(usuario.getId()))
                .thenReturn(Optional.of(usuario));

        RefreshSession session = new RefreshSession();
        session.setExpiresAt(Instant.parse("2026-07-07T00:00:00Z"));

        when(sessions.iniciar(usuario, "agent", "127.0.0.1"))
                .thenReturn(new RefreshSessionService.Emision(usuario, "access", "refresh", session));

        var resultado = autenticacion.login(new LoginRequest(" admin ", PASSWORD), "agent", "127.0.0.1");

        assertThat(resultado.accessToken()).isEqualTo("access");
        assertThat(resultado.refreshToken()).isEqualTo("refresh");
        assertThat(resultado.usuario().nombreUsuario()).isEqualTo("admin");
    }

    @Test
    void loginFallaConContrasenaIncorrecta() {
        Usuario usuario = usuario(true, true, passwordEncoder.encode(PASSWORD));

        when(usuarios.findByNombreUsuarioIgnoreCaseConRolesYPermisos("admin"))
                .thenReturn(Optional.of(usuario));

        assertThatThrownBy(() -> autenticacion.login(
                new LoginRequest("admin", "incorrecta"), null, "127.0.0.1"))
                .isInstanceOf(BadCredentialsException.class);

        verify(auditFailures).registrarAnonimo(anyString(), anyString(), any());
    }

    @Test
    void loginFallaConUsuarioInactivo() {
        Usuario usuario = usuario(false, true, passwordEncoder.encode(PASSWORD));

        when(usuarios.findByNombreUsuarioIgnoreCaseConRolesYPermisos("admin"))
                .thenReturn(Optional.of(usuario));

        assertThatThrownBy(() -> autenticacion.login(
                new LoginRequest("admin", PASSWORD), null, "127.0.0.1"))
                .isInstanceOf(AuthenticationException.class);

        verify(auditFailures).registrarAnonimo(anyString(), anyString(), any());
    }

    @Test
    void loginFallaConRolInactivo() {
        Usuario usuario = usuario(true, false, passwordEncoder.encode(PASSWORD));

        when(usuarios.findByNombreUsuarioIgnoreCaseConRolesYPermisos("admin"))
                .thenReturn(Optional.of(usuario));

        assertThatThrownBy(() -> autenticacion.login(
                new LoginRequest("admin", PASSWORD), null, "127.0.0.1"))
                .isInstanceOf(AuthenticationException.class);

        verify(auditFailures).registrarAnonimo(anyString(), anyString(), any());
    }

    private ProviderManager authenticationManager() {
        DaoAuthenticationProvider provider = new DaoAuthenticationProvider(new UsuarioDetailsService(usuarios));
        provider.setPasswordEncoder(passwordEncoder);
        return new ProviderManager(provider);
    }

    private Usuario usuario(boolean activo, boolean rolActivo, String hash) {
        Rol rol = new Rol(1L, "ADMINISTRADOR", rolActivo);
        rol.getPermisos().add(permiso("PERM_APP_ACCESO"));

        Usuario usuario = new Usuario();
        usuario.setId(1L);
        usuario.setNombreUsuario("admin");
        usuario.setContrasena(hash);
        usuario.setActivo(activo);
        usuario.setRol(rol);
        usuario.setRoles(new LinkedHashSet<>(java.util.List.of(rol)));
        usuario.setAuthVersion(0L);
        return usuario;
    }

    private gestudio.entidades.Permiso permiso(String codigo) {
        gestudio.entidades.Permiso permiso = new gestudio.entidades.Permiso();
        permiso.setCodigo(codigo);
        permiso.setDescripcion(codigo);
        permiso.setModulo("TEST");
        permiso.setActivo(true);
        permiso.setSistema(true);
        return permiso;
    }
}
