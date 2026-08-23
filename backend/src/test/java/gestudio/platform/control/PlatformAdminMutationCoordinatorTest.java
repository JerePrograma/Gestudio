package gestudio.platform.control;

import gestudio.infra.errores.TratadorDeErrores.OperacionNoPermitidaException;
import gestudio.platform.PlatformMetrics;
import gestudio.platform.control.PlatformControlPlaneService.Activation;
import gestudio.platform.security.PlatformPrincipal;
import gestudio.platform.security.PlatformStepUpService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.TransactionStatus;
import org.springframework.transaction.support.TransactionTemplate;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static gestudio.platform.control.PlatformControlPlaneService.ACTIVE;
import static gestudio.platform.control.PlatformControlPlaneService.PLATFORM_ADMIN_GRANT;
import static gestudio.platform.control.PlatformControlPlaneService.PLATFORM_ADMIN_STATUS;
import static gestudio.platform.control.PlatformControlPlaneService.PLATFORM_MFA_RESET;
import static gestudio.platform.control.PlatformControlPlaneService.REVOKED;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class PlatformAdminMutationCoordinatorTest {
    private static final Instant NOW = Instant.parse("2026-08-21T12:00:00Z");
    private static final long TARGET_USER_ID = 19L;
    private static final UUID CORRELATION_ID = UUID.fromString("11111111-1111-1111-1111-111111111111");
    private static final PlatformPrincipal ACTOR = new PlatformPrincipal(
            7L, "root", 1L, 2L,
            UUID.fromString("22222222-2222-2222-2222-222222222222"), NOW.minusSeconds(30));

    @Mock private PlatformControlPlaneRepository repository;
    @Mock private PlatformIdempotencyRepository idempotency;
    @Mock private PlatformStepUpService stepUp;
    @Mock private PlatformAuditService audit;
    @Mock private PlatformMetrics metrics;
    @Mock private PlatformControlPlaneCommandSupport commands;

    private PlatformAdminMutationCoordinator admins;

    @BeforeEach
    void setUp() {
        PlatformMutationExecutor executor = new PlatformMutationExecutor(repository, audit, metrics);
        admins = new PlatformAdminMutationCoordinator(repository, idempotency, stepUp, audit,
                Clock.fixed(NOW, ZoneOffset.UTC), transactions(), commands, executor);
    }

    @Test
    void grantReplayReturnsExistingAdminWithoutConsumingStepUpAgain() {
        PlatformControlPlaneRepository.AdminView admin = admin(ACTIVE, true, 3L);
        replay(PLATFORM_ADMIN_GRANT);
        when(repository.admin(TARGET_USER_ID)).thenReturn(Optional.of(admin));

        assertThat(admins.grantAdmin(TARGET_USER_ID, ACTOR, "key", "proof", CORRELATION_ID).admin())
                .isSameAs(admin);
        verify(stepUp, never()).requireAndConsume(any(), any(), any(), any(), any(), any());
    }

    @Test
    void grantOfIdentityWithExistingMfaDoesNotIssueAnotherActivation() {
        PlatformControlPlaneRepository.AdminView admin = admin(ACTIVE, true, 1L);
        when(commands.validateKey("key")).thenReturn("key");
        when(idempotency.claim(eq(PLATFORM_ADMIN_GRANT), eq("key"), eq(ACTOR.userId()), anyString()))
                .thenReturn(pending(PLATFORM_ADMIN_GRANT));
        when(repository.identity(TARGET_USER_ID))
                .thenReturn(Optional.of(new PlatformControlPlaneRepository.IdentityView(
                        TARGET_USER_ID, "target", true)));
        when(repository.admin(TARGET_USER_ID)).thenReturn(Optional.of(admin));

        var granted = admins.grantAdmin(
                TARGET_USER_ID, ACTOR, "key", "proof", CORRELATION_ID);

        assertThat(granted.admin()).isSameAs(admin);
        assertThat(granted.activation()).isNull();
        verify(repository).grantAdmin(TARGET_USER_ID, ACTOR.userId(), NOW, true);
        verify(commands, never()).activation(anyLong(), anyString(), anyLong(), any());
    }

    @Test
    void statusReplayReturnsCurrentAdminWithoutChangingVersionAgain() {
        PlatformControlPlaneRepository.AdminView admin = admin(ACTIVE, true, 3L);
        when(commands.requiredStatus(eq(ACTIVE), anyList())).thenReturn(ACTIVE);
        when(commands.reason("reactivation requested")).thenReturn("reactivation requested");
        replay(PLATFORM_ADMIN_STATUS);
        when(repository.admin(TARGET_USER_ID)).thenReturn(Optional.of(admin));

        assertThat(admins.changeAdminStatus(TARGET_USER_ID, ACTIVE, 3L,
                "reactivation requested", ACTOR, "key", "proof", CORRELATION_ID))
                .isSameAs(admin);
        verify(repository, never()).changeAdminStatus(anyLong(), any(Boolean.class), anyLong(), any());
    }

    @Test
    void reactivationWithoutVerifiedMfaIsDeniedBeforeWrite() {
        PlatformControlPlaneRepository.AdminView admin = admin(REVOKED, false, 3L);
        pendingStatus(ACTIVE, admin);

        assertThatThrownBy(() -> admins.changeAdminStatus(TARGET_USER_ID, ACTIVE, 3L,
                "reactivation requested", ACTOR, "key", "proof", CORRELATION_ID))
                .isInstanceOf(OperacionNoPermitidaException.class)
                .hasMessageContaining("sin MFA verificado");
        verify(repository, never()).changeAdminStatus(anyLong(), any(Boolean.class), anyLong(), any());
    }

    @Test
    void validReactivationStillRejectsStaleOptimisticVersion() {
        PlatformControlPlaneRepository.AdminView admin = admin(REVOKED, true, 3L);
        OperacionNoPermitidaException conflict = new OperacionNoPermitidaException("stale");
        pendingStatus(ACTIVE, admin);
        when(repository.changeAdminStatus(TARGET_USER_ID, true, 3L, NOW)).thenReturn(false);
        when(commands.concurrencyConflict()).thenReturn(conflict);

        assertThatThrownBy(() -> admins.changeAdminStatus(TARGET_USER_ID, ACTIVE, 3L,
                "reactivation requested", ACTOR, "key", "proof", CORRELATION_ID))
                .isSameAs(conflict);
    }

    @Test
    void mfaResetReplayNeverReexposesActivationToken() {
        replay(PLATFORM_MFA_RESET);

        assertThatThrownBy(() -> admins.resetAdminMfa(
                TARGET_USER_ID, ACTOR, "key", "proof", CORRELATION_ID))
                .isInstanceOf(OperacionNoPermitidaException.class)
                .hasMessageContaining("replay de reset MFA");
        verify(stepUp, never()).requireAndConsume(any(), any(), any(), any(), any(), any());
    }

    @Test
    void revokedAdminCanReceiveNewMfaEnrollmentWithoutLastActiveAdminGuard() {
        PlatformControlPlaneRepository.AdminView revoked = admin(REVOKED, false, 4L);
        Activation activation = new Activation("one-time-token", NOW.plusSeconds(3600));
        when(commands.validateKey("key")).thenReturn("key");
        when(idempotency.claim(eq(PLATFORM_MFA_RESET), eq("key"), eq(ACTOR.userId()), anyString()))
                .thenReturn(pending(PLATFORM_MFA_RESET));
        when(repository.admin(TARGET_USER_ID)).thenReturn(Optional.of(revoked));
        when(commands.activation(TARGET_USER_ID, PLATFORM_MFA_RESET, ACTOR.userId(), NOW))
                .thenReturn(activation);

        assertThat(admins.resetAdminMfa(
                TARGET_USER_ID, ACTOR, "key", "proof", CORRELATION_ID)).isSameAs(activation);

        verify(repository, never()).activeAdminCount();
        verify(repository).resetMfa(TARGET_USER_ID, NOW);
        verify(idempotency).succeeded(PLATFORM_MFA_RESET, "key", "PLATFORM_ADMIN",
                Long.toString(TARGET_USER_ID), 200, "{}");
    }

    private void replay(String operation) {
        when(commands.validateKey("key")).thenReturn("key");
        when(idempotency.claim(eq(operation), eq("key"), eq(ACTOR.userId()), anyString()))
                .thenReturn(succeeded(operation));
    }

    private void pendingStatus(String status, PlatformControlPlaneRepository.AdminView admin) {
        when(commands.requiredStatus(eq(status), anyList())).thenReturn(status);
        when(commands.reason("reactivation requested")).thenReturn("reactivation requested");
        when(commands.validateKey("key")).thenReturn("key");
        when(idempotency.claim(eq(PLATFORM_ADMIN_STATUS), eq("key"), eq(ACTOR.userId()), anyString()))
                .thenReturn(pending(PLATFORM_ADMIN_STATUS));
        when(repository.admin(TARGET_USER_ID)).thenReturn(Optional.of(admin));
    }

    private static TransactionTemplate transactions() {
        PlatformTransactionManager manager = mock(PlatformTransactionManager.class);
        TransactionStatus status = mock(TransactionStatus.class);
        when(manager.getTransaction(any(TransactionDefinition.class))).thenReturn(status);
        return new TransactionTemplate(manager);
    }

    private static PlatformIdempotencyRepository.Claim succeeded(String operation) {
        return new PlatformIdempotencyRepository.Claim(operation, "key", ACTOR.userId(), "hash",
                "SUCCEEDED", "PLATFORM_ADMIN", Long.toString(TARGET_USER_ID), 200, "{}", false);
    }

    private static PlatformIdempotencyRepository.Claim pending(String operation) {
        return new PlatformIdempotencyRepository.Claim(operation, "key", ACTOR.userId(), "hash",
                "PENDING", null, null, null, null, true);
    }

    private static PlatformControlPlaneRepository.AdminView admin(
            String status, boolean mfaEnabled, long version) {
        return new PlatformControlPlaneRepository.AdminView(TARGET_USER_ID, "target", status,
                mfaEnabled, NOW.minusSeconds(3600), REVOKED.equals(status) ? NOW : null, version);
    }
}
