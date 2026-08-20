package gestudio.platform.security;

import gestudio.platform.PlatformMetrics;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.transaction.support.TransactionTemplate;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.HexFormat;
import java.util.List;
import java.util.Locale;
import java.util.OptionalLong;
import java.util.stream.IntStream;

@Service
public class PlatformMfaService {
    private static final Duration FAILURE_WINDOW = Duration.ofMinutes(10);
    private static final Duration BLOCK_DURATION = Duration.ofMinutes(15);
    private static final short MAX_FAILURES = 5;

    private final PlatformIdentityRepository identities;
    private final PlatformMfaCrypto crypto;
    private final TotpService totp;
    private final PlatformMetrics metrics;
    private final Clock clock;
    private final SecureRandom random = new SecureRandom();
    private final TransactionTemplate transactions;

    public PlatformMfaService(PlatformIdentityRepository identities, PlatformMfaCrypto crypto,
                              TotpService totp, PlatformMetrics metrics, Clock clock,
                              @Qualifier("platformTransactionManager") PlatformTransactionManager manager) {
        this.identities = identities;
        this.crypto = crypto;
        this.totp = totp;
        this.metrics = metrics;
        this.clock = clock;
        this.transactions = new TransactionTemplate(manager);
    }

    public Instant verifyTotp(long userId, String code) {
        try {
            Attempt attempt = transactions.execute(status -> attemptTotp(userId, code));
            Instant verifiedAt = requireVerifiedAttempt(attempt);
            metrics.mfa(PlatformMetrics.MfaMethod.TOTP, PlatformMetrics.MfaResult.SUCCESS);
            return verifiedAt;
        } catch (PlatformMfaRateLimitedException exception) {
            metrics.mfa(PlatformMetrics.MfaMethod.TOTP, PlatformMetrics.MfaResult.RATE_LIMITED);
            throw exception;
        } catch (RuntimeException exception) {
            metrics.mfa(PlatformMetrics.MfaMethod.TOTP, PlatformMetrics.MfaResult.FAILURE);
            throw exception;
        }
    }

    private static Instant requireVerifiedAttempt(Attempt attempt) {
        if (attempt == null) throw new IllegalStateException("Resultado MFA ausente");
        if (attempt.retryAfter() != null) {
            throw new PlatformMfaRateLimitedException(attempt.retryAfter());
        }
        if (!attempt.success()) throw new BadCredentialsException("Credenciales inválidas");
        return attempt.verifiedAt();
    }

    public Instant verifyRecovery(long userId, String rawCode) {
        try {
            Instant now = clock.instant();
            boolean consumed = Boolean.TRUE.equals(transactions.execute(status ->
                    identities.consumeRecoveryCode(userId, sha256(normalizeRecoveryCode(rawCode)), now)));
            if (!consumed) throw new BadCredentialsException("Credenciales inválidas");
            metrics.mfa(PlatformMetrics.MfaMethod.RECOVERY, PlatformMetrics.MfaResult.SUCCESS);
            return now;
        } catch (RuntimeException exception) {
            metrics.mfa(PlatformMetrics.MfaMethod.RECOVERY, PlatformMetrics.MfaResult.FAILURE);
            throw exception;
        }
    }

    public ProvisionedMfa provisionInitial(long userId, String base32Secret, String currentCode) {
        try {
            byte[] secret = Base32.decode(base32Secret);
            OptionalLong counter = totp.verify(secret, currentCode, null);
            if (counter.isEmpty()) throw new BadCredentialsException("Código TOTP inválido");
            PlatformMfaCrypto.Encrypted encrypted = crypto.encrypt(secret);
            Instant now = clock.instant();
            List<String> codes = IntStream.range(0, 10).mapToObj(ignored -> recoveryCode()).toList();
            transactions.executeWithoutResult(status -> {
                var existing = identities.lockActiveMfa(userId);
                if (existing.isPresent()) throw new IllegalStateException("MFA ya está configurado");
                var credentialId = identities.insertInitialMfa(userId, encrypted.ciphertext(),
                        encrypted.keyVersion(), now, counter.getAsLong());
                identities.insertRecoveryCodes(credentialId, codes.stream()
                        .map(PlatformMfaService::normalizeRecoveryCode)
                        .map(PlatformMfaService::sha256).toList());
            });
            recordEnrollmentAfterCommit();
            return new ProvisionedMfa(List.copyOf(codes));
        } catch (RuntimeException exception) {
            metrics.mfa(PlatformMetrics.MfaMethod.ENROLLMENT, PlatformMetrics.MfaResult.FAILURE);
            throw exception;
        }
    }

    private Attempt attemptTotp(long userId, String code) {
        var credential = identities.lockActiveMfa(userId)
                .orElseThrow(() -> new BadCredentialsException("Credenciales inválidas"));
        Instant now = clock.instant();
        if (credential.blockedUntil() != null && credential.blockedUntil().isAfter(now)) {
            return Attempt.blocked(Duration.between(now, credential.blockedUntil()));
        }
        byte[] secret = crypto.decrypt(credential.ciphertext(), credential.keyVersion());
        OptionalLong counter = totp.verify(secret, code, credential.lastCounter());
        if (counter.isPresent()) {
            identities.mfaSucceeded(credential.id(), counter.getAsLong(), now);
            return Attempt.success(now);
        }
        Instant window = credential.failureWindowStartedAt();
        short attempts;
        if (window == null || window.plus(FAILURE_WINDOW).isBefore(now)) {
            window = now;
            attempts = 1;
        } else {
            attempts = (short) Math.min(Short.MAX_VALUE, credential.failedAttempts() + 1);
        }
        Instant blockedUntil = attempts >= MAX_FAILURES ? now.plus(BLOCK_DURATION) : null;
        identities.mfaFailed(credential.id(), attempts, window, blockedUntil);
        return blockedUntil == null ? Attempt.failed() : Attempt.blocked(BLOCK_DURATION);
    }

    private String recoveryCode() {
        byte[] bytes = new byte[16];
        random.nextBytes(bytes);
        String encoded = Base32.encode(bytes);
        return encoded.substring(0, 8) + "-" + encoded.substring(8, 16)
                + "-" + encoded.substring(16, 24) + "-" + encoded.substring(24);
    }

    private void recordEnrollmentAfterCommit() {
        if (TransactionSynchronizationManager.isActualTransactionActive()
                && TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                @Override
                public void afterCommit() {
                    metrics.mfa(PlatformMetrics.MfaMethod.ENROLLMENT,
                            PlatformMetrics.MfaResult.SUCCESS);
                }
            });
            return;
        }
        metrics.mfa(PlatformMetrics.MfaMethod.ENROLLMENT, PlatformMetrics.MfaResult.SUCCESS);
    }

    private static String normalizeRecoveryCode(String value) {
        if (value == null || !value.matches("(?i)[A-Z2-7]{8}(?:-[A-Z2-7]{8}){2}-[A-Z2-7]{2}")) {
            return "invalid";
        }
        return value.replace("-", "").toUpperCase(Locale.ROOT);
    }

    static String sha256(String value) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
                    .digest(value.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 no disponible", exception);
        }
    }

    private record Attempt(boolean success, Instant verifiedAt, Duration retryAfter) {
        static Attempt success(Instant at) { return new Attempt(true, at, null); }
        static Attempt failed() { return new Attempt(false, null, null); }
        static Attempt blocked(Duration retryAfter) { return new Attempt(false, null, retryAfter); }
    }

    public record ProvisionedMfa(List<String> recoveryCodes) {
        public ProvisionedMfa {
            recoveryCodes = List.copyOf(recoveryCodes);
        }
    }
}
