package ledance.infra.seguridad;

import java.time.Instant;

public record VerifiedToken(
        String subject,
        Long userId,
        String role,
        Long authVersion,
        String jwtId,
        TokenType tokenType,
        Instant issuedAt,
        Instant expiresAt
) {
}
