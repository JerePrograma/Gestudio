package gestudio.platform.security;

import gestudio.infra.seguridad.InvalidTokenException;
import gestudio.infra.seguridad.RefreshTokenReuseException;
import gestudio.infra.seguridad.TokenType;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Clock;
import java.time.Instant;
import java.util.HexFormat;
import java.util.Objects;
import java.util.UUID;

@Service
public class PlatformRefreshSessionService {
    private final PlatformRefreshSessionRepository sessions;
    private final PlatformIdentityRepository identities;
    private final PlatformTokenService tokens;
    private final Clock clock;
    private final TransactionTemplate transactions;

    public PlatformRefreshSessionService(PlatformRefreshSessionRepository sessions,
                                         PlatformIdentityRepository identities,
                                         PlatformTokenService tokens, Clock clock,
                                         @Qualifier("platformTransactionManager")
                                         PlatformTransactionManager manager) {
        this.sessions = sessions;
        this.identities = identities;
        this.tokens = tokens;
        this.clock = clock;
        this.transactions = new TransactionTemplate(manager);
    }

    public Emission start(PlatformIdentityRepository.Identity identity, Instant mfaAt,
                          String userAgent, String ip) {
        return transactions.execute(status -> issue(identity, mfaAt, UUID.randomUUID(),
                null, userAgent, ip));
    }

    public Emission rotate(String raw, String userAgent, String ip) {
        PlatformVerifiedToken token = tokens.verify(raw, TokenType.REFRESH);
        Rotation rotation = transactions.execute(status -> rotateLocked(raw, token, userAgent, ip));
        if (rotation == null) throw new IllegalStateException("Resultado refresh ausente");
        if (rotation.reuseDetected()) throw new RefreshTokenReuseException();
        return rotation.emission();
    }

    public void logout(String raw) {
        if (raw == null || raw.isBlank()) return;
        try {
            PlatformVerifiedToken token = tokens.verify(raw, TokenType.REFRESH);
            transactions.executeWithoutResult(status -> sessions.lockByTokenHash(hash(raw))
                    .filter(value -> binding(value, token))
                    .ifPresent(value -> sessions.revokeFamily(value.familyId(), clock.instant(), "LOGOUT")));
        } catch (InvalidTokenException ignored) {
            // Idempotent logout clears the cookie at the HTTP boundary.
        }
    }

    private Rotation rotateLocked(String raw, PlatformVerifiedToken token,
                                  String userAgent, String ip) {
        var current = sessions.lockByTokenHash(hash(raw)).orElseThrow(InvalidTokenException::new);
        if (!binding(current, token)) throw new InvalidTokenException();
        Instant now = clock.instant();
        if (current.usedAt() != null) {
            sessions.revokeFamily(current.familyId(), now, "REUSE_DETECTED");
            return Rotation.reuse();
        }
        if (current.revokedAt() != null || !current.expiresAt().isAfter(now)
                || !current.familyExpiresAt().isAfter(now)) throw new InvalidTokenException();
        var identity = identities.findActiveById(token.userId())
                .filter(value -> value.username().equals(token.subject()))
                .filter(value -> value.authVersion() == token.authVersion())
                .filter(value -> value.platformSecurityVersion() == token.platformSecurityVersion())
                .orElseThrow(InvalidTokenException::new);
        Emission replacement = issue(identity, current.mfaVerifiedAt(), current.familyId(),
                current.familyExpiresAt(), userAgent, ip);
        sessions.rotate(current.id(), replacement.sessionId(), now);
        return Rotation.success(replacement);
    }

    private Emission issue(PlatformIdentityRepository.Identity identity, Instant mfaAt,
                           UUID familyId, Instant absoluteExpiry, String userAgent, String ip) {
        UUID id = UUID.randomUUID();
        PlatformTokenService.Tokens emission = absoluteExpiry == null
                ? tokens.issue(identity.userId(), identity.username(), identity.authVersion(),
                identity.platformSecurityVersion(), id, mfaAt)
                : tokens.issue(identity.userId(), identity.username(), identity.authVersion(),
                identity.platformSecurityVersion(), id, mfaAt, absoluteExpiry);
        PlatformVerifiedToken verified = tokens.verify(emission.refreshToken(), TokenType.REFRESH);
        Instant canonicalMfaAt = verified.mfaVerifiedAt();
        if (canonicalMfaAt.isAfter(verified.issuedAt())) {
            throw new IllegalArgumentException("La verificación MFA no puede ser posterior a la sesión");
        }
        var session = new PlatformRefreshSessionRepository.Session(
                id, familyId, identity.userId(), hash(emission.refreshToken()), identity.authVersion(),
                identity.platformSecurityVersion(), canonicalMfaAt,
                verified.issuedAt(), verified.expiresAt(),
                emission.refreshExpiresAt(), null, null, null, hashNullable(userAgent), hashNullable(ip));
        sessions.insert(session);
        return new Emission(emission.accessToken(), emission.refreshToken(), emission.refreshExpiresAt(),
                id, identity.userId(), identity.username(), canonicalMfaAt);
    }

    private static boolean binding(PlatformRefreshSessionRepository.Session session,
                                   PlatformVerifiedToken token) {
        return session.id().toString().equals(token.jwtId())
                && session.id().equals(token.sessionId())
                && session.userId() == token.userId()
                && session.authVersion() == token.authVersion()
                && session.platformSecurityVersion() == token.platformSecurityVersion()
                && Objects.equals(session.mfaVerifiedAt(), token.mfaVerifiedAt());
    }

    static String hash(String value) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
                    .digest(value.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 no disponible", exception);
        }
    }

    private static String hashNullable(String value) {
        return value == null || value.isBlank() ? null : hash(value);
    }

    public record Emission(String accessToken, String refreshToken, Instant refreshExpiresAt,
                           UUID sessionId, long userId, String username, Instant mfaAt) {
    }

    private record Rotation(Emission emission, boolean reuseDetected) {
        static Rotation success(Emission emission) { return new Rotation(emission, false); }
        static Rotation reuse() { return new Rotation(null, true); }
    }
}
