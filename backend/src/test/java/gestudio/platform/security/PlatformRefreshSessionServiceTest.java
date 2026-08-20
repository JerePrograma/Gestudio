package gestudio.platform.security;

import gestudio.infra.seguridad.InvalidTokenException;
import gestudio.infra.seguridad.JwtProperties;
import gestudio.infra.seguridad.RefreshTokenReuseException;
import gestudio.infra.seguridad.TokenType;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.time.temporal.ChronoUnit;
import java.util.Base64;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class PlatformRefreshSessionServiceTest {
    private static final Instant NOW = Instant.now().minusSeconds(600).truncatedTo(ChronoUnit.SECONDS);
    private static final PlatformIdentityRepository.Identity IDENTITY =
            new PlatformIdentityRepository.Identity(17L, "root@example.test", "hash", true,
                    3L, 5L, true, true);
    private static final Instant MFA_AT = NOW.minusSeconds(30);

    @Mock private PlatformRefreshSessionRepository sessions;
    @Mock private PlatformIdentityRepository identities;

    private MutableClock clock;
    private PlatformTokenService tokens;
    private PlatformRefreshSessionService service;

    @BeforeEach
    void setUp() {
        clock = new MutableClock(NOW);
        tokens = new PlatformTokenService(properties(), jwtProperties(), clock);
        service = new PlatformRefreshSessionService(sessions, identities, tokens, clock,
                PlatformSecurityTestSupport.transactionManager());
    }

    @Test
    void startPersistsOnlyRefreshHashAndBindsSessionIdentityAndClientMetadata() {
        PlatformRefreshSessionService.Emission emission = service.start(
                IDENTITY, MFA_AT, "Browser/1.0", "192.0.2.10");

        ArgumentCaptor<PlatformRefreshSessionRepository.Session> inserted =
                ArgumentCaptor.forClass(PlatformRefreshSessionRepository.Session.class);
        verify(sessions).insert(inserted.capture());
        var stored = inserted.getValue();
        var verified = tokens.verify(emission.refreshToken(), TokenType.REFRESH);

        assertThat(stored.id()).isEqualTo(emission.sessionId()).isEqualTo(verified.sessionId());
        assertThat(stored.familyId()).isNotNull();
        assertThat(stored.tokenHash()).isEqualTo(PlatformRefreshSessionService.hash(emission.refreshToken()));
        assertThat(stored.tokenHash()).doesNotContain(emission.refreshToken());
        assertThat(stored.userAgentHash()).isEqualTo(PlatformRefreshSessionService.hash("Browser/1.0"));
        assertThat(stored.ipHash()).isEqualTo(PlatformRefreshSessionService.hash("192.0.2.10"));
        assertThat(stored.authVersion()).isEqualTo(IDENTITY.authVersion());
        assertThat(stored.platformSecurityVersion()).isEqualTo(IDENTITY.platformSecurityVersion());
        assertThat(stored.familyExpiresAt()).isEqualTo(emission.refreshExpiresAt());
    }

    @Test
    void startUsesJwtPrecisionForMfaTimeAndRejectsFutureVerification() {
        Instant fractionalMfaAt = NOW.minusMillis(250);

        PlatformRefreshSessionService.Emission emission = service.start(
                IDENTITY, fractionalMfaAt, null, null);

        ArgumentCaptor<PlatformRefreshSessionRepository.Session> inserted =
                ArgumentCaptor.forClass(PlatformRefreshSessionRepository.Session.class);
        verify(sessions).insert(inserted.capture());
        PlatformVerifiedToken verified = tokens.verify(emission.refreshToken(), TokenType.REFRESH);
        assertThat(inserted.getValue().mfaVerifiedAt()).isEqualTo(verified.mfaVerifiedAt())
                .isBeforeOrEqualTo(inserted.getValue().issuedAt());
        assertThat(emission.mfaAt()).isEqualTo(verified.mfaVerifiedAt());

        assertThatThrownBy(() -> service.start(IDENTITY, NOW.plusSeconds(1), null, null))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("MFA");
    }

    @Test
    void rotateReplacesTokenWithinSameAbsoluteFamilyAndMarksOldSessionUsed() {
        PlatformRefreshSessionRepository.Session initial = startAndCapture();
        String raw = rawFor(initial);
        when(sessions.lockByTokenHash(PlatformRefreshSessionService.hash(raw)))
                .thenReturn(Optional.of(initial));
        when(identities.findActiveById(IDENTITY.userId())).thenReturn(Optional.of(IDENTITY));
        clock.advance(Duration.ofMinutes(2));

        PlatformRefreshSessionService.Emission rotated = service.rotate(
                raw, "Browser/2.0", "192.0.2.11");

        ArgumentCaptor<PlatformRefreshSessionRepository.Session> replacement =
                ArgumentCaptor.forClass(PlatformRefreshSessionRepository.Session.class);
        verify(sessions, org.mockito.Mockito.times(2)).insert(replacement.capture());
        var storedReplacement = replacement.getAllValues().get(1);
        assertThat(storedReplacement.id()).isEqualTo(rotated.sessionId());
        assertThat(storedReplacement.familyId()).isEqualTo(initial.familyId());
        assertThat(storedReplacement.familyExpiresAt()).isEqualTo(initial.familyExpiresAt());
        assertThat(rotated.refreshExpiresAt()).isEqualTo(initial.familyExpiresAt());
        assertThat(rotated.refreshToken()).isNotEqualTo(raw);
        verify(sessions).rotate(initial.id(), rotated.sessionId(), clock.instant());
    }

    @Test
    void reuseRevokesWholeFamilyAndNeverIssuesAnotherToken() {
        PlatformRefreshSessionRepository.Session initial = startAndCapture();
        String raw = rawFor(initial);
        PlatformRefreshSessionRepository.Session used = copy(initial,
                NOW.plusSeconds(10), null, initial.familyExpiresAt(), initial.expiresAt());
        when(sessions.lockByTokenHash(PlatformRefreshSessionService.hash(raw)))
                .thenReturn(Optional.of(used));
        clock.advance(Duration.ofMinutes(1));

        assertThatThrownBy(() -> service.rotate(raw, null, null))
                .isInstanceOf(RefreshTokenReuseException.class);

        verify(sessions).revokeFamily(initial.familyId(), clock.instant(), "REUSE_DETECTED");
        verify(identities, never()).findActiveById(anyLong());
    }

    @Test
    void expiryRevocationAndSecurityVersionMismatchAreRejected() {
        PlatformRefreshSessionRepository.Session initial = startAndCapture();
        String raw = rawFor(initial);
        clock.advance(Duration.ofMinutes(1));

        when(sessions.lockByTokenHash(PlatformRefreshSessionService.hash(raw)))
                .thenReturn(Optional.of(copy(initial, null, null,
                        clock.instant().minusSeconds(1), initial.expiresAt())));
        assertThatThrownBy(() -> service.rotate(raw, null, null))
                .isInstanceOf(InvalidTokenException.class);

        when(sessions.lockByTokenHash(PlatformRefreshSessionService.hash(raw)))
                .thenReturn(Optional.of(copy(initial, null, clock.instant(),
                        initial.familyExpiresAt(), initial.expiresAt())));
        assertThatThrownBy(() -> service.rotate(raw, null, null))
                .isInstanceOf(InvalidTokenException.class);

        when(sessions.lockByTokenHash(PlatformRefreshSessionService.hash(raw)))
                .thenReturn(Optional.of(initial));
        var changed = new PlatformIdentityRepository.Identity(
                IDENTITY.userId(), IDENTITY.username(), IDENTITY.passwordHash(), true,
                IDENTITY.authVersion(), IDENTITY.platformSecurityVersion() + 1, true, true);
        when(identities.findActiveById(IDENTITY.userId())).thenReturn(Optional.of(changed));
        assertThatThrownBy(() -> service.rotate(raw, null, null))
                .isInstanceOf(InvalidTokenException.class);
    }

    @Test
    void logoutIsIdempotentAndRevokesBoundFamilyOnly() {
        PlatformRefreshSessionRepository.Session initial = startAndCapture();
        String raw = rawFor(initial);
        when(sessions.lockByTokenHash(PlatformRefreshSessionService.hash(raw)))
                .thenReturn(Optional.of(initial));

        service.logout(raw);
        verify(sessions).revokeFamily(initial.familyId(), NOW, "LOGOUT");

        service.logout(null);
        service.logout("not-a-jwt");
        verify(sessions, org.mockito.Mockito.times(1)).lockByTokenHash(any());
    }

    private PlatformRefreshSessionRepository.Session startAndCapture() {
        PlatformRefreshSessionService.Emission emission = service.start(IDENTITY, MFA_AT, null, null);
        ArgumentCaptor<PlatformRefreshSessionRepository.Session> inserted =
                ArgumentCaptor.forClass(PlatformRefreshSessionRepository.Session.class);
        verify(sessions).insert(inserted.capture());
        RawTokens.remember(inserted.getValue().id(), emission.refreshToken());
        return inserted.getValue();
    }

    private String rawFor(PlatformRefreshSessionRepository.Session session) {
        return RawTokens.get(session.id());
    }

    private PlatformRefreshSessionRepository.Session copy(
            PlatformRefreshSessionRepository.Session source,
            Instant usedAt, Instant revokedAt, Instant familyExpiresAt, Instant expiresAt) {
        return new PlatformRefreshSessionRepository.Session(source.id(), source.familyId(),
                source.userId(), source.tokenHash(), source.authVersion(), source.platformSecurityVersion(),
                source.mfaVerifiedAt(), source.issuedAt(), expiresAt, familyExpiresAt, usedAt, revokedAt,
                source.replacedById(), source.userAgentHash(), source.ipHash());
    }

    private PlatformSecurityProperties properties() {
        return new PlatformSecurityProperties("gestudio-platform", Duration.ofMinutes(5),
                Duration.ofHours(8), Duration.ofMinutes(3),
                Base64.getEncoder().encodeToString(
                        "0123456789abcdef0123456789abcdef".getBytes(StandardCharsets.US_ASCII)),
                1, new PlatformSecurityProperties.RefreshCookie(
                "platform_refresh", true, "Strict", null, "/api/platform/auth"));
    }

    private JwtProperties jwtProperties() {
        return new JwtProperties("platform-refresh-test-secret-with-more-than-32-bytes",
                "gestudio-platform-test", "gestudio-web", Duration.ofMinutes(10), Duration.ofHours(24));
    }

    private static final class RawTokens {
        private static final java.util.Map<UUID, String> TOKENS = new java.util.concurrent.ConcurrentHashMap<>();

        private RawTokens() {
        }

        static void remember(UUID id, String raw) {
            TOKENS.put(id, raw);
        }

        static String get(UUID id) {
            return TOKENS.get(id);
        }
    }

    private static final class MutableClock extends Clock {
        private Instant instant;

        private MutableClock(Instant instant) {
            this.instant = instant;
        }

        void advance(Duration duration) {
            instant = instant.plus(duration);
        }

        @Override
        public ZoneId getZone() {
            return ZoneOffset.UTC;
        }

        @Override
        public Clock withZone(ZoneId zone) {
            return this;
        }

        @Override
        public Instant instant() {
            return instant;
        }
    }
}
