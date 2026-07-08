package ledance.infra.seguridad;

import ledance.auditoria.application.AuditFailureService;
import ledance.dto.request.LoginRequest;
import ledance.entidades.RefreshSession;
import ledance.entidades.Rol;
import ledance.entidades.Usuario;
import ledance.repositorios.UsuarioRepositorio;
import org.junit.jupiter.api.Test;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.authentication.ProviderManager;
import org.springframework.security.authentication.dao.DaoAuthenticationProvider;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.time.Instant;
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
            authenticationManager(), sessions, auditFailures);

    @Test
    void loginExitosoConUsuarioYRolActivosYBcryptValido() {
        Usuario usuario = usuario(true, true, passwordEncoder.encode(PASSWORD));
        when(usuarios.findByNombreUsuarioIgnoreCase("admin")).thenReturn(Optional.of(usuario));
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
        when(usuarios.findByNombreUsuarioIgnoreCase("admin"))
                .thenReturn(Optional.of(usuario(true, true, passwordEncoder.encode(PASSWORD))));

        assertThatThrownBy(() -> autenticacion.login(
                new LoginRequest("admin", "incorrecta"), null, "127.0.0.1"))
                .isInstanceOf(BadCredentialsException.class);
        verify(auditFailures).registrarAnonimo(anyString(), anyString(), any());
    }

    @Test
    void loginFallaConUsuarioInactivo() {
        when(usuarios.findByNombreUsuarioIgnoreCase("admin"))
                .thenReturn(Optional.of(usuario(false, true, passwordEncoder.encode(PASSWORD))));

        assertThatThrownBy(() -> autenticacion.login(
                new LoginRequest("admin", PASSWORD), null, "127.0.0.1"))
                .isInstanceOf(AuthenticationException.class);
        verify(auditFailures).registrarAnonimo(anyString(), anyString(), any());
    }

    @Test
    void loginFallaConRolInactivo() {
        when(usuarios.findByNombreUsuarioIgnoreCase("admin"))
                .thenReturn(Optional.of(usuario(true, false, passwordEncoder.encode(PASSWORD))));

        assertThatThrownBy(() -> autenticacion.login(
                new LoginRequest("admin", PASSWORD), null, "127.0.0.1"))
                .isInstanceOf(AuthenticationException.class);
        verify(auditFailures).registrarAnonimo(anyString(), anyString(), any());
    }

    private ProviderManager authenticationManager() {
        DaoAuthenticationProvider provider = new DaoAuthenticationProvider();
        provider.setUserDetailsService(new UsuarioDetailsService(usuarios));
        provider.setPasswordEncoder(passwordEncoder);
        return new ProviderManager(provider);
    }

    private Usuario usuario(boolean activo, boolean rolActivo, String hash) {
        Usuario usuario = new Usuario();
        usuario.setId(1L);
        usuario.setNombreUsuario("admin");
        usuario.setContrasena(hash);
        usuario.setActivo(activo);
        usuario.setRol(new Rol(1L, "ADMINISTRADOR", rolActivo));
        usuario.setRoles(new java.util.LinkedHashSet<>(java.util.List.of(usuario.getRol())));
        usuario.setAuthVersion(0L);
        return usuario;
    }
}
