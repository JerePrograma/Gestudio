package gestudio.infra.seguridad;

import java.time.Instant;
import java.util.UUID;

public record VerifiedToken(
        String subject,
        Long userId,
        String role,
        Long authVersion,
        UUID tenantId,
        UUID membershipId,
        Long tenantSecurityVersion,
        Long membershipSecurityVersion,
        String jwtId,
        TokenType tokenType,
        Instant issuedAt,
        Instant expiresAt
) {
}
