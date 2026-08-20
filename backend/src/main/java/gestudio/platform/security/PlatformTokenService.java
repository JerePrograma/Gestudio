package gestudio.platform.security;

import com.auth0.jwt.JWT;
import com.auth0.jwt.algorithms.Algorithm;
import com.auth0.jwt.interfaces.DecodedJWT;
import com.auth0.jwt.interfaces.JWTVerifier;
import gestudio.infra.seguridad.InvalidTokenException;
import gestudio.infra.seguridad.JwtProperties;
import gestudio.infra.seguridad.TokenType;
import org.springframework.stereotype.Service;

import java.time.Clock;
import java.time.Instant;
import java.util.Date;
import java.util.UUID;

@Service
public class PlatformTokenService {
    public static final String SCOPE = "PLATFORM";

    private final PlatformSecurityProperties properties;
    private final String issuer;
    private final Clock clock;
    private final Algorithm algorithm;
    private final JWTVerifier verifier;

    public PlatformTokenService(PlatformSecurityProperties properties, JwtProperties jwt, Clock clock) {
        this.properties = properties;
        this.issuer = jwt.issuer();
        this.clock = clock;
        this.algorithm = Algorithm.HMAC256(jwt.secret());
        this.verifier = JWT.require(algorithm)
                .withIssuer(jwt.issuer())
                .withAudience(properties.audience())
                .withClaim("scope", SCOPE)
                .build();
    }

    public Tokens issue(Long userId, String username, long authVersion, long platformSecurityVersion,
                        UUID sessionId, Instant mfaVerifiedAt) {
        Instant issuedAt = clock.instant();
        return issue(userId, username, authVersion, platformSecurityVersion, sessionId,
                mfaVerifiedAt, issuedAt.plus(properties.refreshTokenTtl()));
    }

    public Tokens issue(Long userId, String username, long authVersion, long platformSecurityVersion,
                        UUID sessionId, Instant mfaVerifiedAt, Instant refreshExpiresAt) {
        Instant issuedAt = clock.instant();
        if (refreshExpiresAt == null || !refreshExpiresAt.isAfter(issuedAt)) {
            throw new InvalidTokenException();
        }
        Instant accessExpiresAt = issuedAt.plus(properties.accessTokenTtl());
        if (accessExpiresAt.isAfter(refreshExpiresAt)) {
            accessExpiresAt = refreshExpiresAt;
        }
        String access = token(userId, username, authVersion, platformSecurityVersion, sessionId,
                mfaVerifiedAt, UUID.randomUUID(), TokenType.ACCESS, issuedAt,
                accessExpiresAt);
        String refresh = token(userId, username, authVersion, platformSecurityVersion, sessionId,
                mfaVerifiedAt, sessionId, TokenType.REFRESH, issuedAt,
                refreshExpiresAt);
        return new Tokens(access, refresh, refreshExpiresAt);
    }

    public String issueAccess(PlatformPrincipal principal) {
        Instant issuedAt = clock.instant();
        return token(principal.userId(), principal.username(), principal.authVersion(),
                principal.platformSecurityVersion(), principal.sessionId(), principal.mfaVerifiedAt(),
                UUID.randomUUID(), TokenType.ACCESS, issuedAt, issuedAt.plus(properties.accessTokenTtl()));
    }

    public PlatformVerifiedToken verify(String raw, TokenType expectedType) {
        if (raw == null || raw.isBlank()) throw new InvalidTokenException();
        try {
            DecodedJWT jwt = verifier.verify(raw);
            RequiredClaims claims = requiredClaims(jwt);
            requireNoTenantClaims(jwt);
            TokenType tokenType = requiredType(claims.type(), expectedType);
            return new PlatformVerifiedToken(claims.subject(), claims.userId(), claims.authVersion(),
                    claims.platformVersion(), UUID.fromString(claims.session()),
                    claims.mfaAt().toInstant(), jwt.getId(), tokenType,
                    jwt.getIssuedAt().toInstant(), jwt.getExpiresAt().toInstant());
        } catch (InvalidTokenException exception) {
            throw exception;
        } catch (RuntimeException exception) {
            throw new InvalidTokenException(exception);
        }
    }

    private static RequiredClaims requiredClaims(DecodedJWT jwt) {
        String subject = jwt.getSubject();
        Long userId = jwt.getClaim("id").asLong();
        Long authVersion = jwt.getClaim("auth_version").asLong();
        Long platformVersion = jwt.getClaim("platform_security_version").asLong();
        String session = jwt.getClaim("session_id").asString();
        Date mfaAt = jwt.getClaim("mfa_at").asDate();
        String type = jwt.getClaim("type").asString();
        if (subject == null || subject.isBlank()) throw new InvalidTokenException();
        requirePresent(userId, authVersion, platformVersion, session, mfaAt, type,
                jwt.getId(), jwt.getIssuedAt(), jwt.getExpiresAt());
        return new RequiredClaims(subject, userId, authVersion, platformVersion, session, mfaAt, type);
    }

    private static void requirePresent(Object... values) {
        for (Object value : values) {
            if (value == null) throw new InvalidTokenException();
        }
    }

    private static void requireNoTenantClaims(DecodedJWT jwt) {
        if (!jwt.getClaim("tenant_id").isMissing()
                || !jwt.getClaim("membership_id").isMissing()
                || !jwt.getClaim("tenant_security_version").isMissing()
                || !jwt.getClaim("membership_security_version").isMissing()) {
            throw new InvalidTokenException();
        }
    }

    private static TokenType requiredType(String type, TokenType expectedType) {
        TokenType tokenType = TokenType.valueOf(type);
        if (tokenType != expectedType) throw new InvalidTokenException();
        return tokenType;
    }

    private String token(Long userId, String username, long authVersion, long platformVersion,
                         UUID sessionId, Instant mfaAt, UUID jwtId, TokenType type,
                         Instant issuedAt, Instant expiresAt) {
        if (userId == null || username == null || username.isBlank() || sessionId == null || mfaAt == null) {
            throw new IllegalArgumentException("Identidad de plataforma incompleta");
        }
        return JWT.create()
                .withIssuer(issuer).withAudience(properties.audience())
                .withSubject(username).withClaim("id", userId).withClaim("type", type.name())
                .withClaim("scope", SCOPE).withClaim("rol", PlatformPrincipal.AUTHORITY)
                .withClaim("auth_version", authVersion)
                .withClaim("platform_security_version", platformVersion)
                .withClaim("session_id", sessionId.toString())
                .withClaim("mfa_at", Date.from(mfaAt))
                .withJWTId(jwtId.toString()).withIssuedAt(Date.from(issuedAt))
                .withExpiresAt(Date.from(expiresAt)).sign(algorithm);
    }

    public record Tokens(String accessToken, String refreshToken, Instant refreshExpiresAt) {
    }

    private record RequiredClaims(String subject, Long userId, Long authVersion,
                                  Long platformVersion, String session, Date mfaAt, String type) {
    }
}
