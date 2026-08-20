package gestudio.platform.security;

import gestudio.infra.seguridad.TokenType;

import java.time.Instant;
import java.util.UUID;

public record PlatformVerifiedToken(
        String subject,
        Long userId,
        long authVersion,
        long platformSecurityVersion,
        UUID sessionId,
        Instant mfaVerifiedAt,
        String jwtId,
        TokenType tokenType,
        Instant issuedAt,
        Instant expiresAt
) {
}
