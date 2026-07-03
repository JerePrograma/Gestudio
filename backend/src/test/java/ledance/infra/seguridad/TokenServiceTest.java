package ledance.infra.seguridad;

import com.auth0.jwt.JWT;
import com.auth0.jwt.algorithms.Algorithm;
import ledance.entidades.Rol;
import ledance.entidades.Usuario;
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
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.assertNotEquals;

class TokenServiceTest {

    private static final String SECRET = "test-only-secret-with-at-least-32-characters";
    private static final String ISSUER = "le-dance-test";
    private static final String AUDIENCE = "le-dance-web";
    private final Instant now = Instant.now().truncatedTo(ChronoUnit.SECONDS);
    private final JwtProperties properties = new JwtProperties(
            SECRET, ISSUER, AUDIENCE, Duration.ofHours(1), Duration.ofHours(24));
    private final TokenService service = new TokenService(
            properties,
            Clock.fixed(now, ZoneOffset.UTC)
    );

    @Test
    void verificaUnaVezYDevuelveClaimsTipados() {
        String token = service.generarAccessToken(usuarioActivo("ADMINISTRADOR"));

        VerifiedToken verified = service.verify(token, TokenType.ACCESS);
        long minutes = Duration.between(now, verified.expiresAt()).toMinutes();

        assertEquals(7L, verified.userId());
        assertEquals("tester", verified.subject());
        assertEquals("ADMINISTRADOR", verified.role());
        assertEquals(0L, verified.authVersion());
        assertEquals(TokenType.ACCESS, verified.tokenType());
        assertEquals(now, verified.issuedAt());
        assertEquals(60, minutes);
    }

    @Test
    void accessYRefreshNoSonIntercambiables() {
        Usuario usuario = usuarioActivo("ADMINISTRADOR");

        assertThrows(InvalidTokenException.class,
                () -> service.verify(service.generarAccessToken(usuario), TokenType.REFRESH));
        assertThrows(InvalidTokenException.class,
                () -> service.verify(service.generarRefreshToken(usuario, java.util.UUID.randomUUID()), TokenType.ACCESS));
    }

    @Test
    void cadaRefreshEmitidoTieneIdentificadorUnico() {
        Usuario usuario = usuarioActivo("ADMINISTRADOR");

        assertNotEquals(
                service.generarRefreshToken(usuario, java.util.UUID.randomUUID()),
                service.generarRefreshToken(usuario, java.util.UUID.randomUUID())
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
        String token = service.generarAccessToken(usuarioActivo("ADMINISTRADOR"));
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
        usuario.setActivo(true);
        usuario.setAuthVersion(0L);
        return usuario;
    }

    private String tokenFirmado(
            String secret,
            String issuer,
            Instant issuedAt,
            Instant expiresAt,
            TokenType type) {
        return JWT.create()
                .withIssuer(issuer)
                .withAudience(AUDIENCE)
                .withSubject("tester")
                .withClaim("id", 7L)
                .withClaim("rol", "ADMINISTRADOR")
                .withClaim("type", type.name())
                .withClaim("auth_version", 0L)
                .withJWTId(java.util.UUID.randomUUID().toString())
                .withIssuedAt(Date.from(issuedAt))
                .withExpiresAt(Date.from(expiresAt))
                .sign(Algorithm.HMAC256(secret));
    }
}
