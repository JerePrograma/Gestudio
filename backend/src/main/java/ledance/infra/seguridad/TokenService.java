package ledance.infra.seguridad;

import com.auth0.jwt.JWT;
import com.auth0.jwt.algorithms.Algorithm;
import com.auth0.jwt.interfaces.DecodedJWT;
import com.auth0.jwt.interfaces.JWTVerifier;
import ledance.entidades.Usuario;
import org.springframework.stereotype.Service;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Date;
import java.util.UUID;

@Service
public class TokenService {

    private final JwtProperties properties;
    private final Clock clock;
    private final Algorithm algorithm;
    private final JWTVerifier verifier;

    public TokenService(JwtProperties properties, Clock clock) {
        this.properties = properties;
        this.clock = clock;
        this.algorithm = Algorithm.HMAC256(properties.secret());
        this.verifier = JWT.require(algorithm)
                .withIssuer(properties.issuer())
                .withAudience(properties.audience())
                .build();
    }

    public String generarAccessToken(Usuario usuario) {
        return generarToken(usuario, UUID.randomUUID(), properties.accessTokenTtl(), TokenType.ACCESS);
    }

    public String generarRefreshToken(Usuario usuario, UUID sessionId) {
        return generarToken(usuario, sessionId, properties.refreshTokenTtl(), TokenType.REFRESH);
    }

    public Instant refreshExpiresAt(Instant issuedAt) {
        return issuedAt.plus(properties.refreshTokenTtl());
    }

    private String generarToken(Usuario usuario, UUID jwtId, Duration ttl, TokenType tipo) {
        if (usuario.getId() == null
                || usuario.getNombreUsuario() == null
                || usuario.getRol() == null
                || usuario.getAuthVersion() == null) {
            throw new IllegalArgumentException("No se puede generar un token para un usuario incompleto");
        }

        Instant issuedAt = clock.instant();

        return JWT.create()
                .withIssuer(properties.issuer())
                .withAudience(properties.audience())
                .withSubject(usuario.getNombreUsuario())
                .withClaim("id", usuario.getId())
                .withClaim("type", tipo.name())
                .withClaim("rol", rolPrincipalCodigo(usuario))
                .withClaim("roles", usuario.codigosRolesActivos().stream().toList())
                .withClaim("auth_version", usuario.getAuthVersion())
                .withJWTId(jwtId.toString())
                .withIssuedAt(Date.from(issuedAt))
                .withExpiresAt(Date.from(issuedAt.plus(ttl)))
                .sign(algorithm);
    }

    private static String rolPrincipalCodigo(Usuario usuario) {
        if (usuario.getRol().getCodigo() != null && !usuario.getRol().getCodigo().isBlank()) {
            return usuario.getRol().getCodigo();
        }
        return usuario.getRol().getDescripcion();
    }

    public VerifiedToken verify(String token, TokenType expectedType) {
        VerifiedToken verified = verify(token);
        if (verified.tokenType() != expectedType) {
            throw new InvalidTokenException();
        }
        return verified;
    }

    public VerifiedToken verify(String token) {
        if (token == null || token.isBlank()) {
            throw new InvalidTokenException();
        }

        try {
            DecodedJWT decoded = verifier.verify(token);
            String subject = decoded.getSubject();
            Long userId = decoded.getClaim("id").asLong();
            String role = decoded.getClaim("rol").asString();
            Long authVersion = decoded.getClaim("auth_version").asLong();
            String type = decoded.getClaim("type").asString();
            String jwtId = decoded.getId();
            Date issuedAt = decoded.getIssuedAt();
            Date expiresAt = decoded.getExpiresAt();

            if (subject == null || subject.isBlank()
                    || userId == null
                    || role == null || role.isBlank()
                    || authVersion == null
                    || type == null
                    || jwtId == null
                    || issuedAt == null
                    || expiresAt == null) {
                throw new InvalidTokenException();
            }

            return new VerifiedToken(
                    subject,
                    userId,
                    role,
                    authVersion,
                    jwtId,
                    TokenType.valueOf(type),
                    issuedAt.toInstant(),
                    expiresAt.toInstant()
            );
        } catch (InvalidTokenException e) {
            throw e;
        } catch (RuntimeException e) {
            throw new InvalidTokenException(e);
        }
    }
}