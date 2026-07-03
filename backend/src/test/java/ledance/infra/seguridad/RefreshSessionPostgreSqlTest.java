package ledance.infra.seguridad;

import ledance.entidades.Usuario;
import ledance.infra.persistencia.PostgreSqlIntegrationTest;
import ledance.repositorios.UsuarioRepositorio;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.NONE)
class RefreshSessionPostgreSqlTest extends PostgreSqlIntegrationTest {
    @Autowired private RefreshSessionService sessions;
    @Autowired private TokenService tokens;
    @Autowired private UsuarioRepositorio usuarios;
    @Autowired private JdbcTemplate jdbc;

    @Test
    void rotaDetectaReuseRevocaFamiliaYNoPersisteTokensPlanos() {
        Usuario user = usuario();
        var inicial = sessions.iniciar(user, "test-agent", "127.0.0.1");

        assertThat(jdbc.queryForObject("SELECT token_hash FROM refresh_sessions WHERE id = ?",
                String.class, inicial.session().getId()))
                .isEqualTo(RefreshSessionService.hash(inicial.refreshToken()))
                .doesNotContain(inicial.refreshToken());

        var rotada = sessions.rotar(inicial.refreshToken(), "test-agent", "127.0.0.1");
        assertThat(rotada.session().getFamilyId()).isEqualTo(inicial.session().getFamilyId());
        assertThat(jdbc.queryForObject("SELECT used_at IS NOT NULL FROM refresh_sessions WHERE id = ?",
                Boolean.class, inicial.session().getId())).isTrue();

        assertThatThrownBy(() -> sessions.rotar(inicial.refreshToken(), "test-agent", "127.0.0.1"))
                .isInstanceOf(RefreshTokenReuseException.class);
        assertThat(jdbc.queryForObject("""
                SELECT count(*) FROM refresh_sessions
                WHERE family_id = ? AND revoked_at IS NULL
                """, Integer.class, inicial.session().getFamilyId())).isZero();
        assertThatThrownBy(() -> sessions.rotar(rotada.refreshToken(), "test-agent", "127.0.0.1"))
                .isInstanceOf(InvalidTokenException.class);
    }

    @Test
    void logoutAuthVersionInactividadYExpiracionInvalidanRefresh() {
        Usuario user = usuario();

        var logout = sessions.iniciar(user, null, null);
        sessions.logout(logout.refreshToken());
        assertThatThrownBy(() -> sessions.rotar(logout.refreshToken(), null, null))
                .isInstanceOf(InvalidTokenException.class);

        var version = sessions.iniciar(user, null, null);
        jdbc.update("UPDATE usuarios SET auth_version = auth_version + 1 WHERE id = ?", user.getId());
        assertThatThrownBy(() -> sessions.rotar(version.refreshToken(), null, null))
                .isInstanceOf(InvalidTokenException.class);

        Usuario updated = usuarios.findById(user.getId()).orElseThrow();
        var inactive = sessions.iniciar(updated, null, null);
        jdbc.update("UPDATE usuarios SET activo = false, auth_version = auth_version + 1 WHERE id = ?", user.getId());
        assertThatThrownBy(() -> sessions.rotar(inactive.refreshToken(), null, null))
                .isInstanceOf(InvalidTokenException.class);

        jdbc.update("UPDATE usuarios SET activo = true WHERE id = ?", user.getId());
        Usuario active = usuarios.findById(user.getId()).orElseThrow();
        var expired = sessions.iniciar(active, null, null);
        jdbc.update("UPDATE refresh_sessions SET expires_at = issued_at + interval '1 millisecond' WHERE id = ?",
                expired.session().getId());
        assertThatThrownBy(() -> sessions.rotar(expired.refreshToken(), null, null))
                .isInstanceOf(InvalidTokenException.class);

        assertThatThrownBy(() -> tokens.verify(tokens.generarAccessToken(active), TokenType.REFRESH))
                .isInstanceOf(InvalidTokenException.class);
    }

    private Usuario usuario() {
        String suffix = UUID.randomUUID().toString();
        Long role = jdbc.queryForObject("SELECT id FROM roles WHERE descripcion = 'ADMINISTRADOR'", Long.class);
        Long id = jdbc.queryForObject("""
                INSERT INTO usuarios(nombre_usuario, contrasena, rol_id, activo, auth_version)
                VALUES (?, 'test-only', ?, true, 0) RETURNING id
                """, Long.class, "refresh-" + suffix, role);
        return usuarios.findById(id).orElseThrow();
    }
}
