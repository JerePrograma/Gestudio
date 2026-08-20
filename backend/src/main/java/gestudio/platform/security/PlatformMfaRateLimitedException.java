package gestudio.platform.security;

import java.time.Duration;

public class PlatformMfaRateLimitedException extends RuntimeException {
    private static final long serialVersionUID = 1L;

    private final Duration retryAfterDuration;

    public PlatformMfaRateLimitedException(Duration retryAfter) {
        super("MFA temporalmente bloqueado");
        this.retryAfterDuration = retryAfter;
    }

    public Duration retryAfter() {
        return retryAfterDuration;
    }
}
