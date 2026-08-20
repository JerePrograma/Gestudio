package gestudio.platform.security;

import gestudio.platform.PlatformMetrics;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.authentication.BadCredentialsException;

import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Base64;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class PlatformMfaServiceTest {
    private static final Instant NOW = Instant.parse("2026-08-12T18:00:00Z");
    private static final byte[] SECRET =
            "12345678901234567890".getBytes(StandardCharsets.US_ASCII);
    private static final String BASE32_SECRET = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ";
    private static final long COUNTER = NOW.getEpochSecond() / TotpService.STEP_SECONDS;
    private static final UUID CREDENTIAL_ID = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");

    @Mock private PlatformIdentityRepository identities;

    private Clock clock;
    private PlatformMfaCrypto crypto;
    private SimpleMeterRegistry registry;
    private PlatformMfaService service;

    @BeforeEach
    void setUp() {
        clock = Clock.fixed(NOW, ZoneOffset.UTC);
        crypto = new PlatformMfaCrypto(properties());
        registry = new SimpleMeterRegistry();
        service = new PlatformMfaService(identities, crypto, new TotpService(clock),
                new PlatformMetrics(registry), clock,
                PlatformSecurityTestSupport.transactionManager());
    }

    @Test
    void validTotpAdvancesCounterAndSameCounterCannotBeReplayed() {
        var encrypted = crypto.encrypt(SECRET);
        var credential = credential(encrypted, null, (short) 0, null, null);
        when(identities.lockActiveMfa(7L)).thenReturn(Optional.of(credential));

        assertThat(service.verifyTotp(7L, TotpService.code(SECRET, COUNTER))).isEqualTo(NOW);
        verify(identities).mfaSucceeded(CREDENTIAL_ID, COUNTER, NOW);

        var replayed = credential(encrypted, COUNTER, (short) 0, null, null);
        when(identities.lockActiveMfa(7L)).thenReturn(Optional.of(replayed));
        assertThatThrownBy(() -> service.verifyTotp(7L, TotpService.code(SECRET, COUNTER)))
                .isInstanceOf(BadCredentialsException.class)
                .hasMessage("Credenciales inválidas");
        verify(identities).mfaFailed(CREDENTIAL_ID, (short) 1, NOW, null);
        assertThat(mfaCount("totp", "success")).isEqualTo(1);
        assertThat(mfaCount("totp", "failure")).isEqualTo(1);
    }

    @Test
    void fifthFailureBlocksForFifteenMinutesAndExistingBlockReturnsRemainingDelay() {
        var encrypted = crypto.encrypt(SECRET);
        Instant window = NOW.minusSeconds(60);
        when(identities.lockActiveMfa(7L)).thenReturn(Optional.of(
                credential(encrypted, null, (short) 4, window, null)));

        assertThatThrownBy(() -> service.verifyTotp(7L, "000000"))
                .isInstanceOf(PlatformMfaRateLimitedException.class)
                .satisfies(error -> assertThat(((PlatformMfaRateLimitedException) error).retryAfter())
                        .isEqualTo(Duration.ofMinutes(15)));
        verify(identities).mfaFailed(CREDENTIAL_ID, (short) 5, window, NOW.plusSeconds(900));

        when(identities.lockActiveMfa(7L)).thenReturn(Optional.of(
                credential(encrypted, null, (short) 5, window, NOW.plusSeconds(300))));
        assertThatThrownBy(() -> service.verifyTotp(7L, "000000"))
                .isInstanceOf(PlatformMfaRateLimitedException.class)
                .satisfies(error -> assertThat(((PlatformMfaRateLimitedException) error).retryAfter())
                        .isEqualTo(Duration.ofMinutes(5)));
        assertThat(mfaCount("totp", "rate_limited")).isEqualTo(2);
    }

    @Test
    void failureWindowRestartsAfterTenMinutes() {
        var encrypted = crypto.encrypt(SECRET);
        when(identities.lockActiveMfa(7L)).thenReturn(Optional.of(
                credential(encrypted, null, (short) 4, NOW.minusSeconds(601), null)));

        assertThatThrownBy(() -> service.verifyTotp(7L, "000000"))
                .isInstanceOf(BadCredentialsException.class);

        verify(identities).mfaFailed(CREDENTIAL_ID, (short) 1, NOW, null);
        assertThat(mfaCount("totp", "failure")).isEqualTo(1);
    }

    @Test
    void recoveryCodeIsNormalizedHashedAndConsumedExactlyOnce() {
        String code = "ABCDEFGH-JKLMNPQR-STUVWXYZ-23";
        String normalizedHash = PlatformMfaService.sha256("ABCDEFGHJKLMNPQRSTUVWXYZ23");
        when(identities.consumeRecoveryCode(7L, normalizedHash, NOW)).thenReturn(true, false);

        assertThat(service.verifyRecovery(7L, code.toLowerCase())).isEqualTo(NOW);
        assertThatThrownBy(() -> service.verifyRecovery(7L, code))
                .isInstanceOf(BadCredentialsException.class);

        assertThatThrownBy(() -> service.verifyRecovery(7L, "not-a-code"))
                .isInstanceOf(BadCredentialsException.class);
        verify(identities).consumeRecoveryCode(7L, PlatformMfaService.sha256("invalid"), NOW);
        assertThat(mfaCount("recovery", "success")).isEqualTo(1);
        assertThat(mfaCount("recovery", "failure")).isEqualTo(2);
    }

    @Test
    void provisioningEncryptsSecretPersistsTenHashedRecoveryCodesAndDoesNotExposeHashes() {
        UUID newCredential = UUID.fromString("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
        when(identities.lockActiveMfa(7L)).thenReturn(Optional.empty());
        when(identities.insertInitialMfa(eq(7L), any(byte[].class), eq(7), eq(NOW), eq(COUNTER)))
                .thenReturn(newCredential);

        PlatformMfaService.ProvisionedMfa provisioned = service.provisionInitial(
                7L, BASE32_SECRET, TotpService.code(SECRET, COUNTER));

        assertThat(provisioned.recoveryCodes()).hasSize(10).doesNotHaveDuplicates()
                .allMatch(code -> code.matches("[A-Z2-7]{8}(?:-[A-Z2-7]{8}){2}-[A-Z2-7]{2}"));
        ArgumentCaptor<byte[]> ciphertext = ArgumentCaptor.forClass(byte[].class);
        verify(identities).insertInitialMfa(eq(7L), ciphertext.capture(), eq(7), eq(NOW), eq(COUNTER));
        assertThat(ciphertext.getValue()).isNotEqualTo(SECRET);
        assertThat(crypto.decrypt(ciphertext.getValue(), 7)).isEqualTo(SECRET);

        @SuppressWarnings("unchecked")
        ArgumentCaptor<List<String>> hashes = ArgumentCaptor.forClass(List.class);
        verify(identities).insertRecoveryCodes(eq(newCredential), hashes.capture());
        assertThat(hashes.getValue()).hasSize(10).doesNotHaveDuplicates()
                .allMatch(hash -> hash.matches("[0-9a-f]{64}"));
        assertThat(hashes.getValue()).doesNotContainAnyElementsOf(provisioned.recoveryCodes());
        assertThat(mfaCount("enrollment", "success")).isEqualTo(1);
    }

    @Test
    void provisioningRejectsInvalidProofAndExistingCredential() {
        assertThatThrownBy(() -> service.provisionInitial(7L, BASE32_SECRET, "000000"))
                .isInstanceOf(BadCredentialsException.class)
                .hasMessageContaining("TOTP");
        verify(identities, never()).insertInitialMfa(anyLong(), any(), anyInt(), any(), anyLong());

        var encrypted = crypto.encrypt(SECRET);
        when(identities.lockActiveMfa(7L)).thenReturn(Optional.of(
                credential(encrypted, null, (short) 0, null, null)));
        assertThatThrownBy(() -> service.provisionInitial(
                7L, BASE32_SECRET, TotpService.code(SECRET, COUNTER)))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("configurado");
        assertThat(mfaCount("enrollment", "failure")).isEqualTo(2);
    }

    private double mfaCount(String method, String result) {
        return registry.get(PlatformMetrics.MFA_EVENTS)
                .tags("method", method, "result", result).counter().count();
    }

    private PlatformIdentityRepository.MfaCredential credential(
            PlatformMfaCrypto.Encrypted encrypted, Long lastCounter, short failures,
            Instant window, Instant blockedUntil) {
        return new PlatformIdentityRepository.MfaCredential(CREDENTIAL_ID, 7L,
                encrypted.ciphertext(), (short) encrypted.keyVersion(), NOW.minusSeconds(3600),
                lastCounter, failures, window, blockedUntil);
    }

    private PlatformSecurityProperties properties() {
        return new PlatformSecurityProperties("gestudio-platform", Duration.ofMinutes(5),
                Duration.ofHours(8), Duration.ofMinutes(3),
                Base64.getEncoder().encodeToString(
                        "0123456789abcdef0123456789abcdef".getBytes(StandardCharsets.US_ASCII)),
                7, new PlatformSecurityProperties.RefreshCookie(
                "platform_refresh", true, "Strict", null, "/api/platform/auth"));
    }
}
