package ledance.infra.seguridad;

import java.time.Instant;

public record VerifiedToken(
        String subject,
        Long userId,
        Long authVersion,
        String jwtId,
        TokenType tokenType,
        Instant issuedAt,
        Instant expiresAt
) {
}
