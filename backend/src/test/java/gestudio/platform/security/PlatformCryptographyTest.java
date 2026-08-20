package gestudio.platform.security;

import com.auth0.jwt.JWT;
import com.auth0.jwt.algorithms.Algorithm;
import gestudio.infra.seguridad.InvalidTokenException;
import gestudio.infra.seguridad.JwtProperties;
import gestudio.infra.seguridad.TokenType;
import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.temporal.ChronoUnit;
import java.util.Arrays;
import java.util.Base64;
import java.util.Date;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class PlatformCryptographyTest {
    private static final String JWT_SECRET = "platform-token-test-secret-with-more-than-32-bytes";
    private static final String ISSUER = "gestudio-platform-test";
    private static final String AUDIENCE = "gestudio-platform";
    private static final byte[] TOTP_SECRET =
            "12345678901234567890".getBytes(StandardCharsets.US_ASCII);
    private static final Instant NOW = Instant.now().truncatedTo(ChronoUnit.SECONDS);

    @Test
    void base32RoundTripAcceptsCanonicalSeparatorsAndRejectsInvalidSecrets() {
        String encoded = Base32.encode(TOTP_SECRET);

        assertThat(encoded).isEqualTo("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ");
        assertThat(Base32.decode(encoded.toLowerCase())).isEqualTo(TOTP_SECRET);
        assertThat(Base32.decode("GEZD-GNBV GY3T-QOJQ=GEZD-GNBV GY3T-QOJQ"))
                .isEqualTo(TOTP_SECRET);

        assertThatThrownBy(() -> Base32.encode(new byte[0]))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> Base32.decode("MZXW6"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("160");
        assertThatThrownBy(() -> Base32.decode("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJ0"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("Base32");
    }

    @Test
    void totpUsesRfc4226VectorsWindowAndCounterReplayProtection() {
        assertThat(TotpService.code(TOTP_SECRET, 0)).isEqualTo("755224");
        assertThat(TotpService.code(TOTP_SECRET, 1)).isEqualTo("287082");
        assertThat(TotpService.code(TOTP_SECRET, 2)).isEqualTo("359152");

        TotpService service = new TotpService(Clock.fixed(Instant.ofEpochSecond(60), ZoneOffset.UTC));

        assertThat(service.verify(TOTP_SECRET, "287082", null)).hasValue(1);
        assertThat(service.verify(TOTP_SECRET, "359152", null)).hasValue(2);
        assertThat(service.verify(TOTP_SECRET, TotpService.code(TOTP_SECRET, 3), null)).hasValue(3);
        assertThat(service.verify(TOTP_SECRET, "359152", 2L)).isEmpty();
        assertThat(service.verify(TOTP_SECRET, "12345", null)).isEmpty();
        assertThat(service.verify(TOTP_SECRET, "abcdef", null)).isEmpty();
    }

    @Test
    void aesGcmRoundTripUsesRandomIvAndDetectsTamperingAndWrongKeyVersion() {
        PlatformMfaCrypto crypto = new PlatformMfaCrypto(properties());

        PlatformMfaCrypto.Encrypted first = crypto.encrypt(TOTP_SECRET);
        PlatformMfaCrypto.Encrypted second = crypto.encrypt(TOTP_SECRET);

        assertThat(first.keyVersion()).isEqualTo(7);
        assertThat(first.ciphertext()).isNotEqualTo(second.ciphertext());
        assertThat(crypto.decrypt(first.ciphertext(), first.keyVersion())).isEqualTo(TOTP_SECRET);

        byte[] exposedCopy = first.ciphertext();
        exposedCopy[0] ^= 1;
        assertThat(crypto.decrypt(first.ciphertext(), first.keyVersion())).isEqualTo(TOTP_SECRET);

        byte[] tampered = first.ciphertext();
        tampered[tampered.length - 1] ^= 1;
        assertThatThrownBy(() -> crypto.decrypt(tampered, first.keyVersion()))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("descifrar");
        assertThatThrownBy(() -> crypto.decrypt(first.ciphertext(), first.keyVersion() + 1))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("versión");
    }

    @Test
    void platformTokensEnforceAudienceScopeTypeExpiryAndExcludeTenantClaims() {
        Clock clock = Clock.fixed(NOW, ZoneOffset.UTC);
        PlatformTokenService service = new PlatformTokenService(properties(), jwtProperties(), clock);
        UUID sessionId = UUID.randomUUID();
        Instant mfaAt = NOW.minusSeconds(30);

        PlatformTokenService.Tokens issued = service.issue(
                41L, "root@example.test", 3L, 9L, sessionId, mfaAt);
        PlatformVerifiedToken access = service.verify(issued.accessToken(), TokenType.ACCESS);
        PlatformVerifiedToken refresh = service.verify(issued.refreshToken(), TokenType.REFRESH);

        assertThat(access.userId()).isEqualTo(41L);
        assertThat(access.subject()).isEqualTo("root@example.test");
        assertThat(access.authVersion()).isEqualTo(3L);
        assertThat(access.platformSecurityVersion()).isEqualTo(9L);
        assertThat(access.sessionId()).isEqualTo(sessionId);
        assertThat(access.mfaVerifiedAt()).isEqualTo(mfaAt);
        assertThat(refresh.jwtId()).isEqualTo(sessionId.toString());
        assertThat(refresh.expiresAt()).isEqualTo(issued.refreshExpiresAt());
        assertThat(JWT.decode(issued.accessToken()).getAudience()).containsExactly(AUDIENCE);
        assertThat(JWT.decode(issued.accessToken()).getClaim("scope").asString())
                .isEqualTo(PlatformTokenService.SCOPE);
        assertThat(JWT.decode(issued.accessToken()).getClaim("tenant_id").isMissing()).isTrue();
        assertThat(JWT.decode(issued.accessToken()).getClaim("membership_id").isMissing()).isTrue();
        assertThat(JWT.decode(issued.accessToken()).getClaim("tenant_security_version").isMissing()).isTrue();
        assertThat(JWT.decode(issued.accessToken()).getClaim("membership_security_version").isMissing()).isTrue();

        assertThatThrownBy(() -> service.verify(issued.accessToken(), TokenType.REFRESH))
                .isInstanceOf(InvalidTokenException.class);
        assertThatThrownBy(() -> service.verify(issued.refreshToken(), TokenType.ACCESS))
                .isInstanceOf(InvalidTokenException.class);
        assertThatThrownBy(() -> service.verify(forged("tenant-web", "PLATFORM", NOW.plusSeconds(60), false),
                TokenType.ACCESS)).isInstanceOf(InvalidTokenException.class);
        assertThatThrownBy(() -> service.verify(forged(AUDIENCE, "TENANT", NOW.plusSeconds(60), false),
                TokenType.ACCESS)).isInstanceOf(InvalidTokenException.class);
        assertThatThrownBy(() -> service.verify(forged(AUDIENCE, "PLATFORM", NOW.minusSeconds(1), false),
                TokenType.ACCESS)).isInstanceOf(InvalidTokenException.class);
        assertThatThrownBy(() -> service.verify(forged(AUDIENCE, "PLATFORM", NOW.plusSeconds(60), true),
                TokenType.ACCESS)).isInstanceOf(InvalidTokenException.class);
    }

    @Test
    void accessTokenCannotOutliveAbsoluteRefreshFamilyExpiry() {
        PlatformTokenService service = new PlatformTokenService(
                properties(), jwtProperties(), Clock.fixed(NOW, ZoneOffset.UTC));
        Instant familyExpiresAt = NOW.plusSeconds(45);

        PlatformTokenService.Tokens issued = service.issue(41L, "root@example.test", 3L, 9L,
                UUID.randomUUID(), NOW.minusSeconds(30), familyExpiresAt);

        assertThat(service.verify(issued.accessToken(), TokenType.ACCESS).expiresAt())
                .isEqualTo(familyExpiresAt);
        assertThat(service.verify(issued.refreshToken(), TokenType.REFRESH).expiresAt())
                .isEqualTo(familyExpiresAt);
    }

    @Test
    void securityPropertiesRejectWeakKeysInvalidTtlsAndUnsafeCookies() {
        byte[] shortKey = Arrays.copyOf(TOTP_SECRET, 16);
        assertThatThrownBy(() -> new PlatformSecurityProperties(
                AUDIENCE, Duration.ofMinutes(5), Duration.ofHours(1), Duration.ofMinutes(2),
                Base64.getEncoder().encodeToString(shortKey), 1, cookie()))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("AES-256");
        assertThatThrownBy(() -> new PlatformSecurityProperties(
                AUDIENCE, Duration.ZERO, Duration.ofHours(1), Duration.ofMinutes(2),
                key(), 1, cookie()))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("TTL");
        assertThatThrownBy(() -> new PlatformSecurityProperties.RefreshCookie(
                "platform_refresh", false, "None", null, "/api/platform/auth"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("Secure");
        assertThatThrownBy(() -> new PlatformSecurityProperties.RefreshCookie(
                "platform_refresh", true, "Strict", null, "/api/platform;bad"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("Path");
    }

    private String forged(String audience, String scope, Instant expiresAt, boolean tenantClaim) {
        var builder = JWT.create()
                .withIssuer(ISSUER).withAudience(audience).withSubject("root@example.test")
                .withClaim("id", 41L).withClaim("type", TokenType.ACCESS.name())
                .withClaim("scope", scope).withClaim("rol", PlatformPrincipal.AUTHORITY)
                .withClaim("auth_version", 3L).withClaim("platform_security_version", 9L)
                .withClaim("session_id", UUID.randomUUID().toString())
                .withClaim("mfa_at", Date.from(NOW.minusSeconds(30)))
                .withJWTId(UUID.randomUUID().toString()).withIssuedAt(Date.from(NOW.minusSeconds(1)))
                .withExpiresAt(Date.from(expiresAt));
        if (tenantClaim) builder.withClaim("tenant_id", UUID.randomUUID().toString());
        return builder.sign(Algorithm.HMAC256(JWT_SECRET));
    }

    private PlatformSecurityProperties properties() {
        return new PlatformSecurityProperties(AUDIENCE, Duration.ofMinutes(5),
                Duration.ofHours(8), Duration.ofMinutes(3), key(), 7, cookie());
    }

    private PlatformSecurityProperties.RefreshCookie cookie() {
        return new PlatformSecurityProperties.RefreshCookie(
                "gestudio_platform_refresh", true, "Strict", null, "/api/platform/auth");
    }

    private JwtProperties jwtProperties() {
        return new JwtProperties(JWT_SECRET, ISSUER, "gestudio-web",
                Duration.ofMinutes(10), Duration.ofHours(24));
    }

    private String key() {
        return Base64.getEncoder().encodeToString(
                "0123456789abcdef0123456789abcdef".getBytes(StandardCharsets.US_ASCII));
    }
}
