package gestudio.infra.seguridad;

import com.auth0.jwt.JWT;
import com.auth0.jwt.algorithms.Algorithm;
import gestudio.entidades.Rol;
import gestudio.entidades.Usuario;
import gestudio.tenancy.Tenant;
import gestudio.tenancy.TenantAccess;
import gestudio.tenancy.TenantMembership;
import gestudio.tenancy.TenantMembershipRole;
import gestudio.tenancy.TenantMembershipStatus;
import gestudio.tenancy.TenantStatus;
import org.junit.jupiter.api.Test;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.temporal.ChronoUnit;
import java.util.Date;
import java.util.List;
import java.util.concurrent.Executors;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class TokenServiceTest {

    private static final String SECRET = "test-only-secret-with-at-least-32-characters";
    private static final String ISSUER = "gestudio-test";
    private static final String AUDIENCE = "gestudio-web";

    private final Instant now = Instant.now().truncatedTo(ChronoUnit.SECONDS);

    private final JwtProperties properties = new JwtProperties(
            SECRET,
            ISSUER,
            AUDIENCE,
            Duration.ofHours(1),
            Duration.ofHours(24)
    );

    private final TokenService service = new TokenService(
            properties,
            Clock.fixed(now, ZoneOffset.UTC)
    );

    @Test
    void verificaUnaVezYDevuelveClaimsTipados() {
        Usuario usuario = usuarioActivo("ADMINISTRADOR");
        String token = service.generarAccessToken(usuario, tenantAccess(usuario));

        VerifiedToken verified = service.verify(token, TokenType.ACCESS);
        long minutes = Duration.between(now, verified.expiresAt()).toMinutes();

        assertEquals(7L, verified.userId());
        assertEquals("tester", verified.subject());
        assertEquals(0L, verified.authVersion());
        assertEquals(TokenType.ACCESS, verified.tokenType());
        assertEquals(now, verified.issuedAt());
        assertEquals(60, minutes);
        assertEquals("ADMINISTRADOR", verified.role());
        assertEquals("ADMINISTRADOR", JWT.decode(token).getClaim("rol").asString());
        assertEquals(List.of("ADMINISTRADOR"), JWT.decode(token).getClaim("roles").asList(String.class));
        assertNull(JWT.decode(token).getClaim("permisos").asList(String.class));
        assertEquals(verified.tenantId().toString(), JWT.decode(token).getClaim("tenant_id").asString());
        assertEquals(verified.membershipId().toString(), JWT.decode(token).getClaim("membership_id").asString());
    }

    @Test
    void accessYRefreshNoSonIntercambiables() {
        Usuario usuario = usuarioActivo("ADMINISTRADOR");

        assertThrows(InvalidTokenException.class,
                () -> service.verify(service.generarAccessToken(usuario, tenantAccess(usuario)), TokenType.REFRESH));

        assertThrows(InvalidTokenException.class,
                () -> service.verify(service.generarRefreshToken(
                        usuario, tenantAccess(usuario), java.util.UUID.randomUUID()), TokenType.ACCESS));
    }

    @Test
    void cadaRefreshEmitidoTieneIdentificadorUnico() {
        Usuario usuario = usuarioActivo("ADMINISTRADOR");

        assertNotEquals(
                service.generarRefreshToken(usuario, tenantAccess(usuario), java.util.UUID.randomUUID()),
                service.generarRefreshToken(usuario, tenantAccess(usuario), java.util.UUID.randomUUID())
        );
    }

    @Test
    void rechazaFirmaIssuerExpiracionYFormatoInvalidos() {
        String wrongSignature = tokenFirmado(
                "otra-clave-de-prueba-con-al-menos-32-caracteres",
                ISSUER,
                now.minusSeconds(1),
                now.plusSeconds(60),
                TokenType.ACCESS
        );

        String wrongIssuer = tokenFirmado(
                SECRET,
                "otro-issuer",
                now.minusSeconds(1),
                now.plusSeconds(60),
                TokenType.ACCESS
        );

        String expired = tokenFirmado(
                SECRET,
                ISSUER,
                now.minusSeconds(120),
                now.minusSeconds(60),
                TokenType.ACCESS
        );

        assertThrows(InvalidTokenException.class, () -> service.verify(wrongSignature));
        assertThrows(InvalidTokenException.class, () -> service.verify(wrongIssuer));
        assertThrows(InvalidTokenException.class, () -> service.verify(expired));
        assertThrows(InvalidTokenException.class, () -> service.verify("no-es-un-jwt"));
    }

    @Test
    void verificacionEsSeguraAnteConcurrencia() throws Exception {
        Usuario usuario = usuarioActivo("ADMINISTRADOR");
        String token = service.generarAccessToken(usuario, tenantAccess(usuario));

        try (var executor = Executors.newFixedThreadPool(8)) {
            var tasks = java.util.stream.IntStream.range(0, 100)
                    .mapToObj(ignored -> (java.util.concurrent.Callable<VerifiedToken>)
                            () -> service.verify(token, TokenType.ACCESS))
                    .toList();

            List<java.util.concurrent.Future<VerifiedToken>> results = executor.invokeAll(tasks);

            assertTrue(results.stream().allMatch(result -> {
                try {
                    return result.get().userId().equals(7L);
                } catch (Exception e) {
                    return false;
                }
            }));
        }
    }

    private Usuario usuarioActivo(String role) {
        Usuario usuario = new Usuario();
        usuario.setId(7L);
        usuario.setNombreUsuario("tester");
        usuario.setRol(new Rol(1L, role, true));
        usuario.setRoles(new java.util.LinkedHashSet<>(List.of(usuario.getRol())));
        usuario.setActivo(true);
        usuario.setAuthVersion(0L);
        return usuario;
    }

    private TenantAccess tenantAccess(Usuario user) {
        Tenant tenant = new Tenant();
        tenant.setId(java.util.UUID.fromString("10000000-0000-0000-0000-000000000001"));
        tenant.setCode("TEST");
        tenant.setName("Test");
        tenant.setStatus(TenantStatus.ACTIVE);
        tenant.setSecurityVersion(2L);

        TenantMembership membership = new TenantMembership();
        membership.setId(java.util.UUID.fromString("20000000-0000-0000-0000-000000000001"));
        membership.setTenant(tenant);
        membership.setUsuario(user);
        membership.setStatus(TenantMembershipStatus.ACTIVE);
        membership.setSecurityVersion(3L);
        membership.setValidFrom(Instant.EPOCH);
        membership.getRoleAssignments().add(new TenantMembershipRole(membership, tenant, user.getRol()));
        return new TenantAccess(membership);
    }

    private String tokenFirmado(
            String secret,
            String issuer,
            Instant issuedAt,
            Instant expiresAt,
            TokenType type
    ) {
        return JWT.create()
                .withIssuer(issuer)
                .withAudience(AUDIENCE)
                .withSubject("tester")
                .withClaim("id", 7L)
                .withClaim("type", type.name())
                .withClaim("auth_version", 0L)
                .withJWTId(java.util.UUID.randomUUID().toString())
                .withIssuedAt(Date.from(issuedAt))
                .withExpiresAt(Date.from(expiresAt))
                .sign(Algorithm.HMAC256(secret));
    }
}
