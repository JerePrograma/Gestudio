package gestudio.platform.security;

import java.time.Instant;
import java.util.UUID;

public record PlatformPrincipal(
        Long userId,
        String username,
        long authVersion,
        long platformSecurityVersion,
        UUID sessionId,
        Instant mfaVerifiedAt
) {
    public static final String AUTHORITY = "PLATFORM_SUPERADMIN";
}
