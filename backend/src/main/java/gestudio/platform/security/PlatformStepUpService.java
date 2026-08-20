package gestudio.platform.security;

import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.time.Clock;
import java.time.Instant;
import java.util.Base64;
import java.util.HexFormat;
import java.util.UUID;

@Service
public class PlatformStepUpService {
    private final PlatformStepUpRepository challenges;
    private final PlatformMfaService mfa;
    private final PlatformSecurityProperties properties;
    private final Clock clock;
    private final SecureRandom random = new SecureRandom();
    private final TransactionTemplate transactions;

    public PlatformStepUpService(PlatformStepUpRepository challenges, PlatformMfaService mfa,
                                 PlatformSecurityProperties properties, Clock clock,
                                 @Qualifier("platformTransactionManager")
                                 PlatformTransactionManager manager) {
        this.challenges = challenges;
        this.mfa = mfa;
        this.properties = properties;
        this.clock = clock;
        this.transactions = new TransactionTemplate(manager);
    }

    public ChallengeEmission challenge(PlatformPrincipal principal, String action, String targetType,
                                       String targetId, String idempotencyKey, UUID correlationId) {
        validateDescriptor(action, targetType, targetId, idempotencyKey);
        Instant now = clock.instant();
        var requested = new PlatformStepUpRepository.Challenge(
                UUID.randomUUID(), principal.userId(), principal.sessionId(), action.trim(),
                targetType.trim(), targetId.trim(), idempotencyKey.trim(), correlationId,
                now, now.plus(properties.stepUpTtl()), null, null, null);
        var result = transactions.execute(status -> challenges.createOrFind(requested));
        if (result == null) throw new IllegalStateException("Resultado step-up ausente");
        if (result.consumedAt() != null || result.verifiedAt() != null || !result.expiresAt().isAfter(now)) {
            throw new PlatformPreconditionRequiredException(
                    "La clave de idempotencia ya posee un desafío step-up consumido o vencido");
        }
        return new ChallengeEmission(result.id(), result.expiresAt());
    }

    public ProofEmission verify(PlatformPrincipal principal, UUID challengeId, String code) {
        var challenge = transactions.execute(status -> {
            var locked = challenges.lockById(challengeId, principal.userId(), principal.sessionId())
                    .orElseThrow(() -> new PlatformPreconditionRequiredException("Desafío step-up inválido"));
            validateAvailable(locked, clock.instant());
            return locked;
        });
        if (challenge == null) throw new IllegalStateException("Desafío step-up ausente");

        // MFA confirma o registra el fallo en su propia transacción. De ese modo
        // un código inválido no revierte el contador de rate limiting.
        Instant verifiedAt = mfa.verifyTotp(principal.userId(), code);
        ProofEmission result = transactions.execute(status -> {
            var locked = challenges.lockById(challengeId, principal.userId(), principal.sessionId())
                    .orElseThrow(() -> new PlatformPreconditionRequiredException("Desafío step-up inválido"));
            validateAvailable(locked, clock.instant());
            String proof = randomToken();
            if (!challenges.verify(locked.id(), hash(proof), verifiedAt)) {
                throw new PlatformPreconditionRequiredException("Desafío step-up no disponible");
            }
            return new ProofEmission(proof, locked.expiresAt());
        });
        if (result == null) throw new IllegalStateException("Resultado step-up ausente");
        return result;
    }

    private static void validateAvailable(PlatformStepUpRepository.Challenge challenge, Instant now) {
        if (challenge.consumedAt() != null || challenge.verifiedAt() != null
                || !challenge.expiresAt().isAfter(now)) {
            throw new PlatformPreconditionRequiredException("Desafío step-up vencido o ya utilizado");
        }
    }

    public void requireAndConsume(PlatformPrincipal principal, String proof, String action,
                                  String targetType, String targetId, String idempotencyKey) {
        validateDescriptor(action, targetType, targetId, idempotencyKey);
        if (proof == null || proof.isBlank() || proof.length() > 256
                || !challenges.consume(principal.userId(), principal.sessionId(), action,
                targetType, targetId, idempotencyKey, hash(proof), clock.instant())) {
            throw new PlatformPreconditionRequiredException("Se requiere step-up válido para esta operación");
        }
    }

    private static void validateDescriptor(String action, String targetType, String targetId,
                                           String idempotencyKey) {
        if (!safe(action, 100) || !safe(targetType, 100) || !safe(targetId, 100)
                || !safe(idempotencyKey, 150)) {
            throw new IllegalArgumentException("Descriptor step-up inválido");
        }
    }

    private static boolean safe(String value, int max) {
        return value != null && !value.isBlank() && value.length() <= max
                && value.chars().noneMatch(character -> Character.isISOControl(character));
    }

    private String randomToken() {
        byte[] bytes = new byte[32];
        random.nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }

    public static String hash(String value) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
                    .digest(value.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 no disponible", exception);
        }
    }

    public record ChallengeEmission(UUID challengeId, Instant expiresAt) {
    }

    public record ProofEmission(String stepUpToken, Instant expiresAt) {
    }
}
