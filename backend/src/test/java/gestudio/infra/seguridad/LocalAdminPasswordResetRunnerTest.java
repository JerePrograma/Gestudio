package gestudio.infra.seguridad;

import gestudio.auditoria.application.AuditService;
import gestudio.entidades.Rol;
import gestudio.entidades.Usuario;
import gestudio.repositorios.UsuarioRepositorio;
import org.junit.jupiter.api.Test;
import org.springframework.boot.DefaultApplicationArguments;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Profile;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class LocalAdminPasswordResetRunnerTest {

    private static final String PASSWORD = "clave-admin-segura";
    private static final Instant NOW = Instant.parse("2026-07-06T03:00:00Z");

    private final UsuarioRepositorio usuarios = mock(UsuarioRepositorio.class);
    private final PasswordEncoder encoder = mock(PasswordEncoder.class);
    private final PasswordPolicy passwordPolicy = mock(PasswordPolicy.class);
    private final AuditService audit = mock(AuditService.class);

    @Test
    void reemplazaHashAnteriorUnaVezEInvalidaSesiones() {
        Usuario admin = admin("hash-anterior");
        when(usuarios.findByNombreUsuarioIgnoreCase("admin")).thenReturn(Optional.of(admin));
        when(encoder.matches(PASSWORD, "hash-anterior")).thenReturn(false);
        when(encoder.encode(PASSWORD)).thenReturn("hash-nuevo");
        when(usuarios.saveAndFlush(admin)).thenReturn(admin);

        runner().run(new DefaultApplicationArguments());

        assertThat(admin.getContrasena()).isEqualTo("hash-nuevo");
        assertThat(admin.getAuthVersion()).isEqualTo(3L);
        assertThat(admin.getPasswordChangedAt()).isEqualTo(NOW);
        verify(usuarios).saveAndFlush(admin);
        verify(audit).registrarAnonimo(eq("SEGURIDAD"), eq("ADMIN_PASSWORD_RESET_LOCAL"),
                eq("admin"), any());
    }

    @Test
    void noReescribeHashSiLaContrasenaYaCoincide() {
        Usuario admin = admin("hash-actual");
        when(usuarios.findByNombreUsuarioIgnoreCase("admin")).thenReturn(Optional.of(admin));
        when(encoder.matches(PASSWORD, "hash-actual")).thenReturn(true);

        runner().run(new DefaultApplicationArguments());

        verify(encoder, never()).encode(any());
        verify(usuarios, never()).saveAndFlush(any());
        verify(audit, never()).registrarAnonimo(any(), any(), any(), any());
    }

    @Test
    void soloPuedeActivarseEnDevYConBanderaExplicita() {
        Profile profile = LocalAdminPasswordResetRunner.class.getAnnotation(Profile.class);
        ConditionalOnProperty condition = LocalAdminPasswordResetRunner.class
                .getAnnotation(ConditionalOnProperty.class);

        assertThat(profile.value()).containsExactly("dev");
        assertThat(condition.name()).containsExactly("app.local-admin-password-reset.enabled");
        assertThat(condition.havingValue()).isEqualTo("true");
        assertThat(condition.matchIfMissing()).isFalse();
    }

    private LocalAdminPasswordResetRunner runner() {
        return new LocalAdminPasswordResetRunner(
                new LocalAdminPasswordResetProperties(" admin ", PASSWORD),
                usuarios, encoder, passwordPolicy, audit, Clock.fixed(NOW, ZoneOffset.UTC));
    }

    private Usuario admin(String hash) {
        Usuario usuario = new Usuario();
        usuario.setId(1L);
        usuario.setNombreUsuario("admin");
        usuario.setContrasena(hash);
        usuario.setActivo(true);
        usuario.setRol(new Rol(1L, "ADMINISTRADOR", true));
        usuario.setRoles(new java.util.LinkedHashSet<>(java.util.List.of(usuario.getRol())));
        usuario.setAuthVersion(2L);
        return usuario;
    }
}
