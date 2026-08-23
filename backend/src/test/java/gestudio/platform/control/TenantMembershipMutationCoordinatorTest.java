package gestudio.platform.control;

import com.fasterxml.jackson.databind.ObjectMapper;
import gestudio.infra.errores.TratadorDeErrores.OperacionNoPermitidaException;
import gestudio.platform.PlatformMetrics;
import gestudio.platform.control.PlatformControlPlaneService.MutationOutcome;
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
import static gestudio.platform.control.PlatformControlPlaneService.MEMBERSHIP_ROLES;
import static gestudio.platform.control.PlatformControlPlaneService.MEMBERSHIP_STATUS;
import static gestudio.platform.control.PlatformControlPlaneService.SUSPENDED;
import static gestudio.platform.control.PlatformControlPlaneService.TENANT_STATUS;
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
class TenantMembershipMutationCoordinatorTest {
    private static final Instant NOW = Instant.parse("2026-08-21T12:00:00Z");
    private static final UUID TENANT_ID = UUID.fromString("11111111-1111-1111-1111-111111111111");
    private static final UUID MEMBERSHIP_ID = UUID.fromString("22222222-2222-2222-2222-222222222222");
    private static final UUID CORRELATION_ID = UUID.fromString("33333333-3333-3333-3333-333333333333");
    private static final PlatformPrincipal ACTOR = new PlatformPrincipal(
            7L, "root", 1L, 2L,
            UUID.fromString("44444444-4444-4444-4444-444444444444"), NOW.minusSeconds(30));

    @Mock private PlatformControlPlaneRepository repository;
    @Mock private PlatformIdempotencyRepository idempotency;
    @Mock private PlatformStepUpService stepUp;
    @Mock private PlatformAuditService audit;
    @Mock private PlatformMetrics metrics;
    @Mock private PlatformControlPlaneCommandSupport commands;

    private TenantMutationCoordinator tenants;
    private MembershipMutationCoordinator memberships;

    @BeforeEach
    void setUp() {
        TransactionTemplate transactions = transactions();
        PlatformMutationExecutor executor = new PlatformMutationExecutor(repository, audit, metrics);
        Clock clock = Clock.fixed(NOW, ZoneOffset.UTC);
        tenants = new TenantMutationCoordinator(repository, idempotency, stepUp, audit, metrics,
                new ObjectMapper(), clock, transactions, commands, executor);
        memberships = new MembershipMutationCoordinator(repository, idempotency, stepUp, audit,
                metrics, clock, transactions, commands, executor);
    }

    @Test
    void tenantStatusReplayReturnsCurrentTenantWithoutDuplicatingMetricOrStepUp() {
        PlatformControlPlaneRepository.TenantView tenant = tenant();
        when(commands.requiredStatus(eq(ACTIVE), anyList())).thenReturn(ACTIVE);
        when(commands.reason("reactivation requested")).thenReturn("reactivation requested");
        when(commands.validateKey("key")).thenReturn("key");
        when(repository.tenant(TENANT_ID)).thenReturn(Optional.of(tenant));
        when(idempotency.claim(eq(TENANT_STATUS), eq("key"), eq(ACTOR.userId()), anyString()))
                .thenReturn(succeeded(TENANT_STATUS, TENANT_ID.toString()));

        assertThat(tenants.changeTenantStatus(TENANT_ID, ACTIVE, 4L,
                "reactivation requested", ACTOR, "key", "proof", CORRELATION_ID))
                .isSameAs(tenant);

        verify(stepUp, never()).requireAndConsume(any(), any(), any(), any(), any(), any());
        verify(metrics, never()).tenantEvent(any());
        verify(commands, never()).tenantEvent(anyString());
    }

    @Test
    void membershipRoleReplayReturnsCurrentVersionWithoutDuplicatingMetric() {
        PlatformControlPlaneRepository.MembershipView current = membership(ACTIVE,
                List.of("ADMINISTRADOR"), 4L);
        when(commands.normalizedRoles(List.of("ADMINISTRADOR")))
                .thenReturn(List.of("ADMINISTRADOR"));
        when(commands.validateKey("key")).thenReturn("key");
        when(repository.membership(TENANT_ID, MEMBERSHIP_ID)).thenReturn(Optional.of(current));
        when(idempotency.claim(eq(MEMBERSHIP_ROLES), eq("key"), eq(ACTOR.userId()), anyString()))
                .thenReturn(succeeded(MEMBERSHIP_ROLES, MEMBERSHIP_ID.toString()));

        assertThat(memberships.updateMembershipRoles(TENANT_ID, MEMBERSHIP_ID,
                List.of("ADMINISTRADOR"), 4L, ACTOR, "key", "proof", CORRELATION_ID))
                .isSameAs(current);

        verify(stepUp, never()).requireAndConsume(any(), any(), any(), any(), any(), any());
        verify(metrics, never()).membershipEvent(any());
    }

    @Test
    void membershipStatusReplayDoesNotRevokeAgainOrDuplicateMetric() {
        PlatformControlPlaneRepository.MembershipView current = membership(SUSPENDED,
                List.of("OPERADOR"), 5L);
        when(commands.requiredStatus(eq(SUSPENDED), anyList())).thenReturn(SUSPENDED);
        when(commands.reason("temporary suspension")).thenReturn("temporary suspension");
        when(commands.validateKey("key")).thenReturn("key");
        when(repository.membership(TENANT_ID, MEMBERSHIP_ID)).thenReturn(Optional.of(current));
        when(idempotency.claim(eq(MEMBERSHIP_STATUS), eq("key"), eq(ACTOR.userId()), anyString()))
                .thenReturn(succeeded(MEMBERSHIP_STATUS, MEMBERSHIP_ID.toString()));

        assertThat(memberships.changeMembershipStatus(TENANT_ID, MEMBERSHIP_ID, SUSPENDED,
                4L, "temporary suspension", ACTOR, "key", "proof", CORRELATION_ID))
                .isSameAs(current);

        verify(repository, never()).updateMembershipStatus(any(), any(), any(), anyLong(), any(), any());
        verify(metrics, never()).membershipEvent(any());
        verify(commands, never()).membershipEvent(anyString());
    }

    @Test
    void unchangedAdministratorRoleStillRequiresOptimisticVersion() {
        PlatformControlPlaneRepository.MembershipView current = membership(ACTIVE,
                List.of("ADMINISTRADOR"), 4L);
        OperacionNoPermitidaException conflict = new OperacionNoPermitidaException("stale");
        pendingMembershipMutation(MEMBERSHIP_ROLES, current);
        when(commands.normalizedRoles(List.of("ADMINISTRADOR")))
                .thenReturn(List.of("ADMINISTRADOR"));
        when(repository.bumpMembershipVersion(TENANT_ID, MEMBERSHIP_ID, 4L, NOW)).thenReturn(false);
        when(commands.concurrencyConflict()).thenReturn(conflict);

        assertThatThrownBy(() -> memberships.updateMembershipRoles(TENANT_ID, MEMBERSHIP_ID,
                List.of("ADMINISTRADOR"), 4L, ACTOR, "key", "proof", CORRELATION_ID))
                .isSameAs(conflict);

        verify(repository, never()).activeAdministrators(any(), any());
        verify(repository, never()).replaceMembershipRoles(any(), any(), anyList(), anyLong());
    }

    @Test
    void suspendedAdministratorCanChangeRolesWithoutTriggeringLastActiveAdminGuard() {
        PlatformControlPlaneRepository.MembershipView current = membership(SUSPENDED,
                List.of("ADMINISTRADOR"), 4L);
        PlatformControlPlaneRepository.MembershipView updated = membership(SUSPENDED,
                List.of("OPERADOR"), 5L);
        when(commands.normalizedRoles(List.of("OPERADOR"))).thenReturn(List.of("OPERADOR"));
        when(commands.validateKey("key")).thenReturn("key");
        when(idempotency.claim(eq(MEMBERSHIP_ROLES), eq("key"), eq(ACTOR.userId()), anyString()))
                .thenReturn(pending(MEMBERSHIP_ROLES));
        when(repository.membership(TENANT_ID, MEMBERSHIP_ID))
                .thenReturn(Optional.of(current))
                .thenReturn(Optional.of(current))
                .thenReturn(Optional.of(updated));
        when(repository.bumpMembershipVersion(TENANT_ID, MEMBERSHIP_ID, 4L, NOW)).thenReturn(true);

        assertThat(memberships.updateMembershipRoles(TENANT_ID, MEMBERSHIP_ID,
                List.of("OPERADOR"), 4L, ACTOR, "key", "proof", CORRELATION_ID))
                .isSameAs(updated);

        verify(repository, never()).activeAdministrators(any(), any());
        verify(repository).replaceMembershipRoles(
                TENANT_ID, MEMBERSHIP_ID, List.of("OPERADOR"), ACTOR.userId());
        verify(metrics).membershipEvent(PlatformMetrics.MembershipEvent.ROLES_CHANGED);
    }

    @Test
    void statusChangeWithoutAdministratorRoleStillRejectsStaleVersion() {
        PlatformControlPlaneRepository.MembershipView current = membership(ACTIVE,
                List.of("OPERADOR"), 4L);
        OperacionNoPermitidaException conflict = new OperacionNoPermitidaException("stale");
        when(commands.requiredStatus(eq(SUSPENDED), anyList())).thenReturn(SUSPENDED);
        when(commands.reason("temporary suspension")).thenReturn("temporary suspension");
        when(commands.validateKey("key")).thenReturn("key");
        when(idempotency.claim(eq(MEMBERSHIP_STATUS), eq("key"), eq(ACTOR.userId()), anyString()))
                .thenReturn(pending(MEMBERSHIP_STATUS));
        when(repository.membership(TENANT_ID, MEMBERSHIP_ID)).thenReturn(Optional.of(current));
        when(repository.updateMembershipStatus(
                TENANT_ID, MEMBERSHIP_ID, SUSPENDED, 4L, current.validUntil(), NOW))
                .thenReturn(false);
        when(commands.concurrencyConflict()).thenReturn(conflict);

        assertThatThrownBy(() -> memberships.changeMembershipStatus(
                TENANT_ID, MEMBERSHIP_ID, SUSPENDED, 4L, "temporary suspension",
                ACTOR, "key", "proof", CORRELATION_ID))
                .isSameAs(conflict);

        verify(repository, never()).activeAdministrators(any(), any());
    }

    private void pendingMembershipMutation(String operation,
                                           PlatformControlPlaneRepository.MembershipView current) {
        when(commands.validateKey("key")).thenReturn("key");
        when(idempotency.claim(eq(operation), eq("key"), eq(ACTOR.userId()), anyString()))
                .thenReturn(pending(operation));
        when(repository.membership(TENANT_ID, MEMBERSHIP_ID)).thenReturn(Optional.of(current));
    }

    private static TransactionTemplate transactions() {
        PlatformTransactionManager manager = mock(PlatformTransactionManager.class);
        TransactionStatus status = mock(TransactionStatus.class);
        when(manager.getTransaction(any(TransactionDefinition.class))).thenReturn(status);
        return new TransactionTemplate(manager);
    }

    private static PlatformIdempotencyRepository.Claim succeeded(String operation, String resourceId) {
        return new PlatformIdempotencyRepository.Claim(operation, "key", ACTOR.userId(), "hash",
                "SUCCEEDED", "RESOURCE", resourceId, 200, "{}", false);
    }

    private static PlatformIdempotencyRepository.Claim pending(String operation) {
        return new PlatformIdempotencyRepository.Claim(operation, "key", ACTOR.userId(), "hash",
                "PENDING", null, null, null, null, true);
    }

    private static PlatformControlPlaneRepository.TenantView tenant() {
        return new PlatformControlPlaneRepository.TenantView(TENANT_ID, "tenant", "Tenant",
                ACTIVE, 4L, NOW.minusSeconds(60), NOW, 1L, 1L, 6L);
    }

    private static PlatformControlPlaneRepository.MembershipView membership(
            String status, List<String> roles, long version) {
        return new PlatformControlPlaneRepository.MembershipView(MEMBERSHIP_ID, TENANT_ID,
                21L, "member", status, roles, NOW.minusSeconds(3600), null, version);
    }
}
