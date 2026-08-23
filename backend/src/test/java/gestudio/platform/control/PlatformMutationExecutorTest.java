package gestudio.platform.control;

import gestudio.infra.errores.TratadorDeErrores.OperacionNoPermitidaException;
import gestudio.infra.errores.TratadorDeErrores.RecursoNoEncontradoException;
import gestudio.platform.PlatformMetrics;
import gestudio.platform.security.PlatformPreconditionRequiredException;
import gestudio.platform.security.PlatformPrincipal;
import gestudio.tenancy.TenantContext;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.dao.DataAccessResourceFailureException;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

import static gestudio.platform.control.PlatformControlPlaneService.MEMBERSHIP_CREATE;
import static gestudio.platform.control.PlatformControlPlaneService.TENANT_CREATE;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.clearInvocations;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class PlatformMutationExecutorTest {
    private static final UUID TENANT_ID = UUID.fromString("11111111-1111-1111-1111-111111111111");
    private static final UUID CORRELATION_ID = UUID.fromString("22222222-2222-2222-2222-222222222222");
    private static final PlatformPrincipal ACTOR = new PlatformPrincipal(
            7L, "root", 1L, 2L,
            UUID.fromString("33333333-3333-3333-3333-333333333333"), Instant.EPOCH);

    @Mock private PlatformControlPlaneRepository repository;
    @Mock private PlatformAuditService audit;
    @Mock private PlatformMetrics metrics;

    private PlatformMutationExecutor executor;

    @BeforeEach
    void setUp() {
        executor = new PlatformMutationExecutor(repository, audit, metrics);
    }

    @AfterEach
    void clearTenantContext() {
        TenantContext.clear();
    }

    @Test
    void requireTenantAndTenantScopeExposeTheCanonicalResourceOnlyInsideWork() {
        PlatformControlPlaneRepository.TenantView tenant = tenant();
        when(repository.tenant(TENANT_ID)).thenReturn(Optional.of(tenant), Optional.empty());

        assertThat(executor.requireTenant(TENANT_ID)).isSameAs(tenant);
        assertThatThrownBy(() -> executor.requireTenant(TENANT_ID))
                .isInstanceOf(RecursoNoEncontradoException.class)
                .hasMessage("Tenant no encontrado");

        String value = executor.inTenant(TENANT_ID, () -> {
            assertThat(TenantContext.requireTenantId()).isEqualTo(TENANT_ID);
            return "done";
        });
        assertThat(value).isEqualTo("done");
        assertThat(TenantContext.currentTenantId()).isEmpty();
    }

    @Test
    void deniedFailuresKeepCanonicalReasonAndBoundedProvisioningMetrics() {
        assertFailure(TENANT_CREATE, new PlatformPreconditionRequiredException("step-up"),
                "STEP_UP_REQUIRED", true, PlatformMetrics.ProvisioningResource.TENANT,
                PlatformMetrics.ProvisioningFailureReason.DENIED);
        assertFailure(MEMBERSHIP_CREATE, new OperacionNoPermitidaException("forbidden"),
                "OPERATION_NOT_ALLOWED", true, PlatformMetrics.ProvisioningResource.MEMBERSHIP,
                PlatformMetrics.ProvisioningFailureReason.DENIED);
        assertFailure("TENANT_STATUS", new RecursoNoEncontradoException("missing"),
                "RESOURCE_NOT_FOUND", false, null, null);
        assertFailure(TENANT_CREATE, new IllegalArgumentException("bad request"),
                "INVALID_REQUEST", false, PlatformMetrics.ProvisioningResource.TENANT,
                PlatformMetrics.ProvisioningFailureReason.INVALID_REQUEST);
    }

    @Test
    void databaseAndUnexpectedFailuresAreAuditedAsFailuresWithDistinctMetrics() {
        assertFailure(MEMBERSHIP_CREATE, new DataAccessResourceFailureException("database"),
                "DATABASE_FAILURE", false, PlatformMetrics.ProvisioningResource.MEMBERSHIP,
                PlatformMetrics.ProvisioningFailureReason.DATABASE);
        assertFailure(TENANT_CREATE, new IllegalStateException("unexpected"),
                "INTERNAL_FAILURE", false, PlatformMetrics.ProvisioningResource.TENANT,
                PlatformMetrics.ProvisioningFailureReason.INTERNAL);
    }

    @Test
    void auditFailureIsSuppressedWithoutReplacingOriginalFailure() {
        IllegalStateException original = new IllegalStateException("original");
        IllegalStateException auditFailure = new IllegalStateException("audit");
        doThrow(auditFailure).when(audit).failed(eq(ACTOR), eq("OTHER"), eq("TYPE"), eq("target"),
                eq(TENANT_ID), eq(CORRELATION_ID), eq("key"), anyMap());

        assertThatThrownBy(() -> executor.auditedMutation(
                "OTHER", "TYPE", "target", TENANT_ID, ACTOR, "key", CORRELATION_ID,
                () -> { throw original; }))
                .isSameAs(original);
        assertThat(original.getSuppressed()).containsExactly(auditFailure);
    }

    private void assertFailure(String action, RuntimeException failure, String reasonCode,
                               boolean authorizationMetric,
                               PlatformMetrics.ProvisioningResource resource,
                               PlatformMetrics.ProvisioningFailureReason provisioningReason) {
        assertThatThrownBy(() -> executor.auditedMutation(
                action, "TYPE", "target", TENANT_ID, ACTOR, "key", CORRELATION_ID,
                () -> { throw failure; }))
                .isSameAs(failure);

        if (authorizationMetric) {
            verify(metrics).authorizationDenied(PlatformMetrics.AuthorizationReason.OPERATION_DENIED,
                    PlatformMetrics.Scope.PLATFORM, PlatformMetrics.Scope.PLATFORM);
        } else {
            verify(metrics, never()).authorizationDenied(any(), any(), any());
        }
        if (resource == null) {
            verify(metrics, never()).provisioningFailure(any(), any());
        } else {
            verify(metrics).provisioningFailure(resource, provisioningReason);
        }

        if (failure instanceof PlatformPreconditionRequiredException
                || failure instanceof OperacionNoPermitidaException
                || failure instanceof RecursoNoEncontradoException
                || failure instanceof IllegalArgumentException) {
            verify(audit).denied(eq(ACTOR), eq(action), eq("TYPE"), eq("target"), eq(TENANT_ID),
                    eq(CORRELATION_ID), eq("key"),
                    org.mockito.ArgumentMatchers.argThat(
                            metadata -> reasonCode.equals(metadata.get("reasonCode"))));
            verify(audit, never()).failed(any(), any(), any(), any(), any(), any(), any(), anyMap());
        } else {
            verify(audit).failed(eq(ACTOR), eq(action), eq("TYPE"), eq("target"), eq(TENANT_ID),
                    eq(CORRELATION_ID), eq("key"),
                    org.mockito.ArgumentMatchers.argThat(
                            metadata -> reasonCode.equals(metadata.get("reasonCode"))));
            verify(audit, never()).denied(any(), any(), any(), any(), any(), any(), any(), anyMap());
        }
        clearInvocations(audit, metrics);
    }

    private static PlatformControlPlaneRepository.TenantView tenant() {
        return new PlatformControlPlaneRepository.TenantView(
                TENANT_ID, "tenant", "Tenant", "ACTIVE", 1L, Instant.EPOCH, Instant.EPOCH,
                1L, 1L, 1L);
    }
}
