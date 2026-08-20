package gestudio.platform.security;

import gestudio.infra.seguridad.InvalidTokenException;
import gestudio.infra.seguridad.TokenType;
import gestudio.platform.PlatformMetrics;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;

import java.time.Instant;
import java.time.Duration;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class PlatformAuthenticationServiceTest {
    private static final Instant MFA_AT = Instant.parse("2026-08-12T18:00:00Z");
    private static final UUID SESSION_ID = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static final PlatformIdentityRepository.Identity IDENTITY =
            new PlatformIdentityRepository.Identity(9L, "root", "hash", true,
                    2L, 6L, true, true);
    private static final PlatformRefreshSessionService.Emission EMISSION =
            new PlatformRefreshSessionService.Emission("access", "refresh", MFA_AT.plusSeconds(3600),
                    SESSION_ID, 9L, "root", MFA_AT);

    @Mock private AuthenticationManager authenticationManager;
    @Mock private PlatformIdentityRepository identities;
    @Mock private PlatformMfaService mfa;
    @Mock private PlatformRefreshSessionService sessions;

    private SimpleMeterRegistry registry;
    private PlatformAuthenticationService service;

    @BeforeEach
    void setUp() {
        registry = new SimpleMeterRegistry();
        service = new PlatformAuthenticationService(authenticationManager, identities, mfa, sessions,
                new PlatformMetrics(registry));
    }

    @Test
    void loginTrimsUsernameRequiresActivePlatformIdentityAndRoutesTotp() {
        when(authenticationManager.authenticate(any())).thenAnswer(invocation -> invocation.getArgument(0));
        when(identities.findActiveByUsername("root")).thenReturn(Optional.of(IDENTITY));
        when(mfa.verifyTotp(9L, "123456")).thenReturn(MFA_AT);
        when(sessions.start(IDENTITY, MFA_AT, "Browser", "192.0.2.1")).thenReturn(EMISSION);

        assertThat(service.login(" root ", "password", PlatformAuthenticationService.MfaMethod.TOTP,
                "123456", "Browser", "192.0.2.1")).isSameAs(EMISSION);
        verify(authenticationManager).authenticate(
                new UsernamePasswordAuthenticationToken("root", "password"));
    }

    @Test
    void loginCanConsumeRecoveryAndCollapsesAuthenticationDetails() {
        when(authenticationManager.authenticate(any())).thenAnswer(invocation -> invocation.getArgument(0));
        when(identities.findActiveByUsername("root")).thenReturn(Optional.of(IDENTITY));
        when(mfa.verifyRecovery(9L, "RECOVERY")).thenReturn(MFA_AT);
        when(sessions.start(IDENTITY, MFA_AT, null, "192.0.2.1")).thenReturn(EMISSION);

        assertThat(service.login("root", "password", PlatformAuthenticationService.MfaMethod.RECOVERY,
                "RECOVERY", null, "192.0.2.1")).isSameAs(EMISSION);

        when(identities.findActiveByUsername("root")).thenReturn(Optional.empty());
        assertThatThrownBy(() -> service.login("root", "password",
                PlatformAuthenticationService.MfaMethod.TOTP, "123456", null, "192.0.2.1"))
                .isInstanceOf(BadCredentialsException.class)
                .hasMessage("Credenciales inválidas");
        assertThat(authFailureCount("login", "invalid_credentials")).isEqualTo(1);
    }

    @Test
    void rateLimitAndInvalidRefreshPublishStableFailureReasons() {
        when(authenticationManager.authenticate(any())).thenAnswer(invocation -> invocation.getArgument(0));
        when(identities.findActiveByUsername("root")).thenReturn(Optional.of(IDENTITY));
        when(mfa.verifyTotp(9L, "123456"))
                .thenThrow(new PlatformMfaRateLimitedException(Duration.ofSeconds(30)));

        assertThatThrownBy(() -> service.login("root", "password",
                PlatformAuthenticationService.MfaMethod.TOTP, "123456", null, "192.0.2.1"))
                .isInstanceOf(PlatformMfaRateLimitedException.class);
        when(sessions.rotate("invalid", null, "192.0.2.1"))
                .thenThrow(new InvalidTokenException());
        assertThatThrownBy(() -> service.refresh("invalid", null, "192.0.2.1"))
                .isInstanceOf(InvalidTokenException.class);

        assertThat(authFailureCount("login", "mfa_rate_limited")).isEqualTo(1);
        assertThat(authFailureCount("refresh", "invalid_session")).isEqualTo(1);
    }

    @Test
    void accessRevalidationRejectsIdentityOrSecurityVersionChanges() {
        PlatformVerifiedToken token = new PlatformVerifiedToken("root", 9L, 2L, 6L,
                SESSION_ID, MFA_AT, UUID.randomUUID().toString(), TokenType.ACCESS,
                MFA_AT, MFA_AT.plusSeconds(300));
        when(identities.findActiveById(9L)).thenReturn(Optional.of(IDENTITY));

        PlatformPrincipal principal = service.revalidate(token);
        assertThat(principal.userId()).isEqualTo(9L);
        assertThat(principal.platformSecurityVersion()).isEqualTo(6L);

        var changed = new PlatformIdentityRepository.Identity(9L, "root", "hash", true,
                2L, 7L, true, true);
        when(identities.findActiveById(9L)).thenReturn(Optional.of(changed));
        assertThatThrownBy(() -> service.revalidate(token)).isInstanceOf(InvalidTokenException.class);
    }

    private double authFailureCount(String operation, String reason) {
        return registry.get(PlatformMetrics.AUTH_FAILURES)
                .tags("operation", operation, "reason", reason).counter().count();
    }
}
