package ledance.infra.seguridad;

import ledance.entidades.Rol;
import ledance.entidades.Usuario;
import ledance.repositorios.RolRepositorio;
import ledance.repositorios.UsuarioRepositorio;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.boot.DefaultApplicationArguments;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

class AdminBootstrapRunnerTest {

    private final UsuarioRepositorio usuarioRepositorio = mock(UsuarioRepositorio.class);
    private final RolRepositorio rolRepositorio = mock(RolRepositorio.class);
    private final PasswordEncoder passwordEncoder = mock(PasswordEncoder.class);

    @Test
    void creaUnicoAdministradorSinExponerNiPersistirClavePlana() throws Exception {
        Rol role = new Rol(1L, "ADMINISTRADOR", true);
        when(usuarioRepositorio.count()).thenReturn(0L);
        when(rolRepositorio.findByDescripcionIgnoreCase("ADMINISTRADOR"))
                .thenReturn(Optional.of(role));
        when(passwordEncoder.encode("clave-inicial-segura"))
                .thenReturn("bcrypt-hash");
        when(usuarioRepositorio.save(org.mockito.ArgumentMatchers.any(Usuario.class)))
                .thenAnswer(invocation -> {
                    Usuario user = invocation.getArgument(0);
                    user.setId(10L);
                    return user;
                });

        runner("admin-inicial", "clave-inicial-segura")
                .run(new DefaultApplicationArguments());

        ArgumentCaptor<Usuario> captor = ArgumentCaptor.forClass(Usuario.class);
        verify(usuarioRepositorio).save(captor.capture());
        assertEquals("admin-inicial", captor.getValue().getNombreUsuario());
        assertEquals("bcrypt-hash", captor.getValue().getContrasena());
        assertNotEquals("clave-inicial-segura", captor.getValue().getContrasena());
        assertEquals(role, captor.getValue().getRol());
        assertTrue(captor.getValue().getActivo());
    }

    @Test
    void exigeDeshabilitarBootstrapSiYaExisteUnUsuario() {
        when(usuarioRepositorio.count()).thenReturn(1L);

        IllegalStateException exception = assertThrows(
                IllegalStateException.class,
                () -> runner("admin", "clave-inicial-segura")
                        .run(new DefaultApplicationArguments())
        );

        assertTrue(exception.getMessage().contains("deshabilítelo"));
        verify(usuarioRepositorio, never()).save(any());
        verifyNoInteractions(rolRepositorio, passwordEncoder);
    }

    @Test
    void reinicioAccidentalNoModificaElUsuarioExistente() {
        Usuario existente = new Usuario();
        existente.setId(7L);
        existente.setNombreUsuario("existente");
        existente.setContrasena("hash-existente");
        existente.setRol(new Rol(1L, "ADMINISTRADOR", true));
        existente.setActivo(true);
        when(usuarioRepositorio.count()).thenReturn(1L);

        assertThrows(IllegalStateException.class,
                () -> runner("otro-admin", "otra-clave-inicial-segura")
                        .run(new DefaultApplicationArguments()));

        assertEquals("existente", existente.getNombreUsuario());
        assertEquals("hash-existente", existente.getContrasena());
        verify(usuarioRepositorio, never()).save(any());
        verifyNoInteractions(rolRepositorio, passwordEncoder);
    }

    @Test
    void rechazaUsernameVacioEnBlancoODemasiadoLargoAntesDeGuardar() {
        when(usuarioRepositorio.count()).thenReturn(0L);

        assertThrows(IllegalStateException.class,
                () -> runner("", "clave-inicial-segura")
                        .run(new DefaultApplicationArguments()));
        assertThrows(IllegalStateException.class,
                () -> runner("   ", "clave-inicial-segura")
                        .run(new DefaultApplicationArguments()));
        assertThrows(IllegalStateException.class,
                () -> runner("a".repeat(101), "clave-inicial-segura")
                        .run(new DefaultApplicationArguments()));

        verify(usuarioRepositorio, never()).save(any());
    }

    @Test
    void rechazaPasswordAusenteCortaOMayorA72BytesAntesDeGuardar() {
        when(usuarioRepositorio.count()).thenReturn(0L);

        assertThrows(IllegalStateException.class,
                () -> runner("admin", null)
                        .run(new DefaultApplicationArguments()));
        assertThrows(IllegalStateException.class,
                () -> runner("admin", "corta")
                        .run(new DefaultApplicationArguments()));
        assertThrows(IllegalStateException.class,
                () -> runner("admin", "á".repeat(37))
                        .run(new DefaultApplicationArguments()));

        verify(usuarioRepositorio, never()).save(any());
    }

    @Test
    void fallaSiElRolAdministradorNoExiste() {
        when(usuarioRepositorio.count()).thenReturn(0L);
        when(rolRepositorio.findByDescripcionIgnoreCase("ADMINISTRADOR")).thenReturn(Optional.empty());

        assertThrows(IllegalStateException.class,
                () -> runner("admin", "clave-inicial-segura")
                        .run(new DefaultApplicationArguments()));

        verify(usuarioRepositorio, never()).save(any());
    }

    @Test
    void fallaSiElRolAdministradorEstaInactivo() {
        when(usuarioRepositorio.count()).thenReturn(0L);
        when(rolRepositorio.findByDescripcionIgnoreCase("ADMINISTRADOR"))
                .thenReturn(Optional.of(new Rol(1L, "administrador", false)));

        assertThrows(IllegalStateException.class,
                () -> runner("admin", "clave-inicial-segura")
                        .run(new DefaultApplicationArguments()));

        verify(usuarioRepositorio, never()).save(any());
    }

    @Test
    void bootstrapDeshabilitadoNoRegistraElRunner() {
        new ApplicationContextRunner()
                .withUserConfiguration(AdminBootstrapRunner.class)
                .withPropertyValues("app.bootstrap-admin.enabled=false")
                .run(context -> assertTrue(context.getBeansOfType(AdminBootstrapRunner.class).isEmpty()));
    }

    private AdminBootstrapRunner runner(String username, String password) {
        return new AdminBootstrapRunner(
                new AdminBootstrapProperties(true, username, password),
                usuarioRepositorio,
                rolRepositorio,
                passwordEncoder
        );
    }
}
