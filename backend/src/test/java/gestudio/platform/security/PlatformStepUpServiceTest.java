package gestudio.platform.security;

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
import java.time.ZoneOffset;
import java.util.Base64;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class PlatformStepUpServiceTest {
    private static final Instant NOW = Instant.parse("2026-08-12T18:00:00Z");
    private static final UUID SESSION_ID = UUID.fromString("11111111-1111-1111-1111-111111111111");
    private static final UUID CHALLENGE_ID = UUID.fromString("22222222-2222-2222-2222-222222222222");
    private static final UUID CORRELATION_ID = UUID.fromString("33333333-3333-3333-3333-333333333333");
    private static final PlatformPrincipal PRINCIPAL =
            new PlatformPrincipal(19L, "root", 2L, 4L, SESSION_ID, NOW.minusSeconds(30));

    @Mock private PlatformStepUpRepository challenges;
    @Mock private PlatformMfaService mfa;

    private PlatformStepUpService service;

    @BeforeEach
    void setUp() {
        service = new PlatformStepUpService(challenges, mfa, properties(),
                Clock.fixed(NOW, ZoneOffset.UTC), PlatformSecurityTestSupport.transactionManager());
    }

    @Test
    void challengeIsPurposeBoundIdempotentAndExpiresAtConfiguredTtl() {
        ArgumentCaptor<PlatformStepUpRepository.Challenge> requested =
                ArgumentCaptor.forClass(PlatformStepUpRepository.Challenge.class);
        when(challenges.createOrFind(requested.capture())).thenAnswer(invocation -> {
            PlatformStepUpRepository.Challenge value = invocation.getArgument(0);
            return new PlatformStepUpRepository.Challenge(CHALLENGE_ID, value.userId(), value.sessionId(),
                    value.action(), value.targetType(), value.targetId(), value.idempotencyKey(),
                    value.correlationId(), value.issuedAt(), value.expiresAt(), null, null, null);
        });

        PlatformStepUpService.ChallengeEmission emitted = service.challenge(PRINCIPAL,
                " TENANT_STATUS ", " TENANT ", " tenant-42 ", " request-1 ", CORRELATION_ID);

        assertThat(emitted.challengeId()).isEqualTo(CHALLENGE_ID);
        assertThat(emitted.expiresAt()).isEqualTo(NOW.plus(Duration.ofMinutes(3)));
        assertThat(requested.getValue().userId()).isEqualTo(PRINCIPAL.userId());
        assertThat(requested.getValue().sessionId()).isEqualTo(SESSION_ID);
        assertThat(requested.getValue().action()).isEqualTo("TENANT_STATUS");
        assertThat(requested.getValue().targetType()).isEqualTo("TENANT");
        assertThat(requested.getValue().targetId()).isEqualTo("tenant-42");
        assertThat(requested.getValue().idempotencyKey()).isEqualTo("request-1");
        assertThat(requested.getValue().correlationId()).isEqualTo(CORRELATION_ID);
    }

    @Test
    void challengeRejectsUnsafeDescriptorAndUsedOrVerifiedIdempotencyKey() {
        assertThatThrownBy(() -> service.challenge(PRINCIPAL, "TENANT_STATUS\n", "TENANT",
                "tenant-42", "request-1", CORRELATION_ID))
                .isInstanceOf(IllegalArgumentException.class);
        verify(challenges, never()).createOrFind(any());

        var alreadyVerified = challenge(NOW.plusSeconds(60), "hash", NOW, null);
        when(challenges.createOrFind(any())).thenReturn(alreadyVerified);
        assertThatThrownBy(() -> service.challenge(PRINCIPAL, "TENANT_STATUS", "TENANT",
                "tenant-42", "request-1", CORRELATION_ID))
                .isInstanceOf(PlatformPreconditionRequiredException.class)
                .hasMessageContaining("consumido o vencido");
    }

    @Test
    void verifyRequiresSameUserAndSessionThenPersistsOnlyProofHash() {
        var available = challenge(NOW.plusSeconds(120), null, null, null);
        when(challenges.lockById(CHALLENGE_ID, PRINCIPAL.userId(), SESSION_ID))
                .thenReturn(Optional.of(available));
        when(mfa.verifyTotp(PRINCIPAL.userId(), "123456")).thenReturn(NOW);
        when(challenges.verify(eq(CHALLENGE_ID), any(String.class), eq(NOW))).thenReturn(true);

        PlatformStepUpService.ProofEmission proof = service.verify(PRINCIPAL, CHALLENGE_ID, "123456");

        assertThat(proof.stepUpToken()).matches("[A-Za-z0-9_-]{43}");
        assertThat(proof.expiresAt()).isEqualTo(available.expiresAt());
        ArgumentCaptor<String> persistedHash = ArgumentCaptor.forClass(String.class);
        verify(challenges).verify(eq(CHALLENGE_ID), persistedHash.capture(), eq(NOW));
        assertThat(persistedHash.getValue()).isEqualTo(PlatformStepUpService.hash(proof.stepUpToken()));
        assertThat(persistedHash.getValue()).doesNotContain(proof.stepUpToken());
    }

    @Test
    void expiredVerifiedAndReplayedChallengesCannotProduceProof() {
        for (PlatformStepUpRepository.Challenge unavailable : new PlatformStepUpRepository.Challenge[]{
                challenge(NOW, null, null, null),
                challenge(NOW.plusSeconds(60), "hash", NOW.minusSeconds(1), null),
                challenge(NOW.plusSeconds(60), "hash", NOW.minusSeconds(2), NOW.minusSeconds(1))
        }) {
            when(challenges.lockById(CHALLENGE_ID, PRINCIPAL.userId(), SESSION_ID))
                    .thenReturn(Optional.of(unavailable));
            assertThatThrownBy(() -> service.verify(PRINCIPAL, CHALLENGE_ID, "123456"))
                    .isInstanceOf(PlatformPreconditionRequiredException.class);
        }
        verify(mfa, never()).verifyTotp(anyLong(), any());
    }

    @Test
    void proofCanBeConsumedOnceAndOnlyForExactPurposeTargetAndIdempotencyKey() {
        String rawProof = "proof-value";
        String expectedHash = PlatformStepUpService.hash(rawProof);
        when(challenges.consume(PRINCIPAL.userId(), SESSION_ID, "TENANT_STATUS", "TENANT",
                "tenant-42", "request-1", expectedHash, NOW)).thenReturn(true, false);

        service.requireAndConsume(PRINCIPAL, rawProof, "TENANT_STATUS", "TENANT",
                "tenant-42", "request-1");

        assertThatThrownBy(() -> service.requireAndConsume(PRINCIPAL, rawProof,
                "TENANT_STATUS", "TENANT", "tenant-42", "request-1"))
                .isInstanceOf(PlatformPreconditionRequiredException.class);

        assertThatThrownBy(() -> service.requireAndConsume(PRINCIPAL, rawProof,
                "TENANT_UPDATE", "TENANT", "tenant-42", "request-1"))
                .isInstanceOf(PlatformPreconditionRequiredException.class);
        verify(challenges).consume(PRINCIPAL.userId(), SESSION_ID, "TENANT_UPDATE", "TENANT",
                "tenant-42", "request-1", expectedHash, NOW);
    }

    private PlatformStepUpRepository.Challenge challenge(
            Instant expiresAt, String proofHash, Instant verifiedAt, Instant consumedAt) {
        return new PlatformStepUpRepository.Challenge(CHALLENGE_ID, PRINCIPAL.userId(), SESSION_ID,
                "TENANT_STATUS", "TENANT", "tenant-42", "request-1", CORRELATION_ID,
                NOW.minusSeconds(10), expiresAt, proofHash, verifiedAt, consumedAt);
    }

    private PlatformSecurityProperties properties() {
        return new PlatformSecurityProperties("gestudio-platform", Duration.ofMinutes(5),
                Duration.ofHours(8), Duration.ofMinutes(3),
                Base64.getEncoder().encodeToString(
                        "0123456789abcdef0123456789abcdef".getBytes(StandardCharsets.US_ASCII)),
                1, new PlatformSecurityProperties.RefreshCookie(
                "platform_refresh", true, "Strict", null, "/api/platform/auth"));
    }
}
