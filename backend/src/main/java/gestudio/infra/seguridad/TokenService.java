package gestudio.infra.seguridad;

import com.auth0.jwt.JWT;
import com.auth0.jwt.algorithms.Algorithm;
import com.auth0.jwt.interfaces.DecodedJWT;
import com.auth0.jwt.interfaces.JWTVerifier;
import gestudio.entidades.Usuario;
import gestudio.tenancy.TenantAccess;
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

    public String generarAccessToken(Usuario usuario, TenantAccess access) {
        return generarToken(usuario, access, UUID.randomUUID(), properties.accessTokenTtl(), TokenType.ACCESS);
    }

    public String generarRefreshToken(Usuario usuario, TenantAccess access, UUID sessionId) {
        return generarToken(usuario, access, sessionId, properties.refreshTokenTtl(), TokenType.REFRESH);
    }

    public Instant refreshExpiresAt(Instant issuedAt) {
        return issuedAt.plus(properties.refreshTokenTtl());
    }

    private String generarToken(Usuario usuario, TenantAccess access, UUID jwtId, Duration ttl, TokenType tipo) {
        if (usuario == null
                || usuario.getId() == null
                || usuario.getNombreUsuario() == null
                || usuario.getAuthVersion() == null
                || access == null
                || !usuario.getId().equals(access.usuario().getId())) {
            throw new IllegalArgumentException("No se puede generar un token para un usuario incompleto");
        }

        String rolPrincipal = access.primaryRoleCode();

        Instant issuedAt = clock.instant();

        return JWT.create()
                .withIssuer(properties.issuer())
                .withAudience(properties.audience())
                .withSubject(usuario.getNombreUsuario())
                .withClaim("id", usuario.getId())
                .withClaim("type", tipo.name())
                .withClaim("rol", rolPrincipal)
                .withClaim("roles", access.roleCodes().stream().sorted().toList())
                .withClaim("auth_version", usuario.getAuthVersion())
                .withClaim("tenant_id", access.tenantId().toString())
                .withClaim("membership_id", access.membershipId().toString())
                .withClaim("tenant_security_version", access.tenantSecurityVersion())
                .withClaim("membership_security_version", access.membershipSecurityVersion())
                .withJWTId(jwtId.toString())
                .withIssuedAt(Date.from(issuedAt))
                .withExpiresAt(Date.from(issuedAt.plus(ttl)))
                .sign(algorithm);
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
            String tenantId = decoded.getClaim("tenant_id").asString();
            String membershipId = decoded.getClaim("membership_id").asString();
            Long tenantSecurityVersion = decoded.getClaim("tenant_security_version").asLong();
            Long membershipSecurityVersion = decoded.getClaim("membership_security_version").asLong();
            String type = decoded.getClaim("type").asString();
            String jwtId = decoded.getId();
            Date issuedAt = decoded.getIssuedAt();
            Date expiresAt = decoded.getExpiresAt();

            if (subject == null || subject.isBlank()
                    || userId == null
                    || role == null || role.isBlank()
                    || authVersion == null
                    || tenantId == null || tenantId.isBlank()
                    || membershipId == null || membershipId.isBlank()
                    || tenantSecurityVersion == null
                    || membershipSecurityVersion == null
                    || type == null || type.isBlank()
                    || jwtId == null || jwtId.isBlank()
                    || issuedAt == null
                    || expiresAt == null) {
                throw new InvalidTokenException();
            }

            return new VerifiedToken(
                    subject,
                    userId,
                    role,
                    authVersion,
                    UUID.fromString(tenantId),
                    UUID.fromString(membershipId),
                    tenantSecurityVersion,
                    membershipSecurityVersion,
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
