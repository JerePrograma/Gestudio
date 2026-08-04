package gestudio.infra.seguridad;

import gestudio.entidades.Usuario;
import gestudio.infra.persistencia.PostgreSqlIntegrationTest;
import gestudio.repositorios.UsuarioRepositorio;
import gestudio.tenancy.TenantAccess;
import gestudio.tenancy.TenantAccessService;
import gestudio.tenancy.TenantContext;
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
    @Autowired private TenantAccessService tenantAccess;

    @Test
    void rotaDetectaReuseRevocaFamiliaYNoPersisteTokensPlanos() {
        Usuario user = usuario();

        var inicial = iniciar(user, "test-agent", "127.0.0.1");

        assertThat(jdbc.queryForObject(
                "SELECT token_hash FROM refresh_sessions WHERE id = ?",
                String.class,
                inicial.session().getId()
        ))
                .isEqualTo(RefreshSessionService.hash(inicial.refreshToken()))
                .doesNotContain(inicial.refreshToken());

        var rotada = rotar(inicial.refreshToken(), "test-agent", "127.0.0.1");

        assertThat(rotada.session().getFamilyId()).isEqualTo(inicial.session().getFamilyId());

        assertThat(jdbc.queryForObject(
                "SELECT used_at IS NOT NULL FROM refresh_sessions WHERE id = ?",
                Boolean.class,
                inicial.session().getId()
        )).isTrue();

        assertThatThrownBy(() -> rotar(inicial.refreshToken(), "test-agent", "127.0.0.1"))
                .isInstanceOf(RefreshTokenReuseException.class);

        assertThat(jdbc.queryForObject("""
                SELECT count(*)
                FROM refresh_sessions
                WHERE family_id = ? AND revoked_at IS NULL
                """, Integer.class, inicial.session().getFamilyId()))
                .isZero();

        assertThatThrownBy(() -> rotar(rotada.refreshToken(), "test-agent", "127.0.0.1"))
                .isInstanceOf(InvalidTokenException.class);
    }

    @Test
    void logoutAuthVersionInactividadYExpiracionInvalidanRefresh() {
        Usuario user = usuario();

        var logout = iniciar(user, null, null);
        logout(logout.refreshToken());

        assertThatThrownBy(() -> rotar(logout.refreshToken(), null, null))
                .isInstanceOf(InvalidTokenException.class);

        var version = iniciar(user, null, null);
        jdbc.update("UPDATE usuarios SET auth_version = auth_version + 1 WHERE id = ?", user.getId());

        assertThatThrownBy(() -> rotar(version.refreshToken(), null, null))
                .isInstanceOf(InvalidTokenException.class);

        Usuario updated = usuarios.findByIdConRolesYPermisos(user.getId()).orElseThrow();
        var inactive = iniciar(updated, null, null);

        jdbc.update(
                "UPDATE usuarios SET activo = false, auth_version = auth_version + 1 WHERE id = ?",
                user.getId()
        );

        assertThatThrownBy(() -> rotar(inactive.refreshToken(), null, null))
                .isInstanceOf(InvalidTokenException.class);

        jdbc.update("UPDATE usuarios SET activo = true WHERE id = ?", user.getId());

        Usuario active = usuarios.findByIdConRolesYPermisos(user.getId()).orElseThrow();
        var expired = iniciar(active, null, null);

        jdbc.update("""
                UPDATE refresh_sessions
                SET expires_at = issued_at + interval '1 millisecond'
                WHERE id = ?
                """, expired.session().getId());

        assertThatThrownBy(() -> rotar(expired.refreshToken(), null, null))
                .isInstanceOf(InvalidTokenException.class);

        TenantAccess access = access(active);
        assertThatThrownBy(() -> tokens.verify(tokens.generarAccessToken(active, access), TokenType.REFRESH))
                .isInstanceOf(InvalidTokenException.class);
    }

    @Test
    void suspensionDeMembershipYTenantInvalidanRefreshExistente() {
        Usuario membershipUser = usuario();
        var membershipSession = iniciar(membershipUser, null, null);
        jdbc.update("""
                UPDATE tenant_memberships
                SET status = 'SUSPENDED', security_version = security_version + 1
                WHERE id = ?
                """, membershipSession.access().membershipId());

        assertThatThrownBy(() -> rotar(membershipSession.refreshToken(), null, null))
                .isInstanceOf(InvalidTokenException.class);

        Usuario tenantUser = usuario();
        var tenantSession = iniciar(tenantUser, null, null);
        jdbc.update("""
                UPDATE tenants
                SET status = 'SUSPENDED', security_version = security_version + 1
                WHERE id = ?
                """, tenantSession.access().tenantId());

        assertThatThrownBy(() -> rotar(tenantSession.refreshToken(), null, null))
                .isInstanceOf(InvalidTokenException.class);

        jdbc.update("UPDATE tenants SET status = 'ACTIVE' WHERE id = ?", tenantSession.access().tenantId());
    }

    @Test
    void cambioDeTenantRechazaUnaSesionConAuthVersionDistintaDelToken() {
        Usuario user = usuario();
        var emission = iniciar(user, null, null);
        jdbc.update(
                "UPDATE refresh_sessions SET auth_version = auth_version + 1 WHERE id = ?",
                emission.session().getId()
        );

        VerifiedToken verified = tokens.verify(emission.refreshToken(), TokenType.REFRESH);
        try (TenantContext.Scope ignored = TenantContext.open(
                verified.tenantId(),
                verified.membershipId()
        )) {
            assertThatThrownBy(() -> sessions.revocarParaCambio(emission.refreshToken(), user))
                    .isInstanceOf(InvalidTokenException.class);
        }
    }

    private Usuario usuario() {
        String suffix = UUID.randomUUID().toString();

        Long roleId = jdbc.queryForObject(
                "SELECT id FROM roles WHERE descripcion = 'ADMINISTRADOR'",
                Long.class
        );

        Long id = jdbc.queryForObject("""
                INSERT INTO usuarios(nombre_usuario, contrasena, rol_id, activo, auth_version)
                VALUES (?, 'test-only', ?, true, 0)
                RETURNING id
                """, Long.class, "refresh-" + suffix, roleId);

        jdbc.update("""
                INSERT INTO usuario_roles(usuario_id, rol_id)
                VALUES (?, ?)
                ON CONFLICT DO NOTHING
                """, id, roleId);

        UUID tenantId = jdbc.queryForObject(
                "SELECT id FROM tenants WHERE code = 'academia-inicial'",
                UUID.class
        );
        UUID membershipId = UUID.randomUUID();
        jdbc.update("""
                INSERT INTO tenant_memberships(
                    id, tenant_id, usuario_id, status, security_version, valid_from)
                VALUES (?, ?, ?, 'ACTIVE', 0, now())
                """, membershipId, tenantId, id);
        jdbc.update("""
                INSERT INTO tenant_membership_roles(membership_id, tenant_id, role_id)
                VALUES (?, ?, ?)
                """, membershipId, tenantId, roleId);

        return usuarios.findByIdConRolesYPermisos(id).orElseThrow();
    }

    private TenantAccess access(Usuario user) {
        UUID tenantId = jdbc.queryForObject(
                "SELECT tenant_id FROM tenant_memberships WHERE usuario_id = ? AND status = 'ACTIVE'",
                UUID.class,
                user.getId()
        );
        return tenantAccess.findActiveAccess(user.getId(), tenantId).orElseThrow();
    }

    private RefreshSessionService.Emision iniciar(Usuario user, String userAgent, String ip) {
        TenantAccess access = access(user);
        try (TenantContext.Scope ignored = TenantContext.open(access.tenantId(), access.membershipId())) {
            return sessions.iniciar(user, access, userAgent, ip);
        }
    }

    private RefreshSessionService.Emision rotar(String rawToken, String userAgent, String ip) {
        VerifiedToken verified = tokens.verify(rawToken, TokenType.REFRESH);
        try (TenantContext.Scope ignored = TenantContext.open(verified.tenantId(), verified.membershipId())) {
            return sessions.rotar(rawToken, userAgent, ip);
        }
    }

    private void logout(String rawToken) {
        VerifiedToken verified = tokens.verify(rawToken, TokenType.REFRESH);
        try (TenantContext.Scope ignored = TenantContext.open(verified.tenantId(), verified.membershipId())) {
            sessions.logout(rawToken);
        }
    }
}
