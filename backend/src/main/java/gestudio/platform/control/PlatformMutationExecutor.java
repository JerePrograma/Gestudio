package gestudio.platform.control;

import gestudio.infra.errores.TratadorDeErrores.OperacionNoPermitidaException;
import gestudio.infra.errores.TratadorDeErrores.RecursoNoEncontradoException;
import gestudio.platform.PlatformMetrics;
import gestudio.platform.security.PlatformPreconditionRequiredException;
import gestudio.platform.security.PlatformPrincipal;
import gestudio.tenancy.TenantContext;
import org.springframework.dao.DataAccessException;

import java.util.Map;
import java.util.UUID;

import static gestudio.platform.control.PlatformControlPlaneService.MEMBERSHIP_CREATE;
import static gestudio.platform.control.PlatformControlPlaneService.TENANT_CREATE;

final class PlatformMutationExecutor {
    private final PlatformControlPlaneRepository repository;
    private final PlatformAuditService auditService;
    private final PlatformMetrics metrics;

    PlatformMutationExecutor(PlatformControlPlaneRepository repository,
                             PlatformAuditService auditService,
                             PlatformMetrics metrics) {
        this.repository = repository;
        this.auditService = auditService;
        this.metrics = metrics;
    }

    PlatformControlPlaneRepository.TenantView requireTenant(UUID tenantId) {
        return repository.tenant(tenantId).orElseThrow(
                () -> new RecursoNoEncontradoException("Tenant no encontrado"));
    }

    <T> T inTenant(UUID tenantId, Work<T> work) {
        try (TenantContext.Scope ignored = TenantContext.open(tenantId, null)) {
            return work.run();
        }
    }

    <T> T auditedMutation(String action, String targetType, String targetId,
                          UUID tenantId, PlatformPrincipal actor, String idempotencyKey,
                          UUID correlationId, Work<T> work) {
        try {
            return work.run();
        } catch (PlatformPreconditionRequiredException | OperacionNoPermitidaException failure) {
            metrics.authorizationDenied(PlatformMetrics.AuthorizationReason.OPERATION_DENIED,
                    PlatformMetrics.Scope.PLATFORM, PlatformMetrics.Scope.PLATFORM);
            recordMutationFailure(action, targetType, targetId, tenantId, actor,
                    idempotencyKey, correlationId, failure);
            throw failure;
        } catch (RuntimeException failure) {
            recordMutationFailure(action, targetType, targetId, tenantId, actor,
                    idempotencyKey, correlationId, failure);
            throw failure;
        }
    }

    private void recordMutationFailure(String action, String targetType, String targetId,
                                       UUID tenantId, PlatformPrincipal actor,
                                       String idempotencyKey, UUID correlationId,
                                       RuntimeException failure) {
        PlatformMetrics.ProvisioningResource provisioningResource = provisioningResource(action);
        if (provisioningResource != null) {
            metrics.provisioningFailure(provisioningResource,
                    provisioningFailureReason(failure));
        }
        try {
            Map<String, String> metadata = Map.of("reasonCode", reasonCode(failure));
            if (isDenied(failure)) {
                auditService.denied(actor, action, targetType, targetId, tenantId,
                        correlationId, idempotencyKey, metadata);
            } else {
                auditService.failed(actor, action, targetType, targetId, tenantId,
                        correlationId, idempotencyKey, metadata);
            }
        } catch (RuntimeException auditFailure) {
            failure.addSuppressed(auditFailure);
        }
    }

    private static boolean isDenied(RuntimeException failure) {
        return failure instanceof PlatformPreconditionRequiredException
                || failure instanceof OperacionNoPermitidaException
                || failure instanceof RecursoNoEncontradoException
                || failure instanceof IllegalArgumentException;
    }

    private static String reasonCode(RuntimeException failure) {
        if (failure instanceof PlatformPreconditionRequiredException) return "STEP_UP_REQUIRED";
        if (failure instanceof OperacionNoPermitidaException) return "OPERATION_NOT_ALLOWED";
        if (failure instanceof RecursoNoEncontradoException) return "RESOURCE_NOT_FOUND";
        if (failure instanceof IllegalArgumentException) return "INVALID_REQUEST";
        if (failure instanceof DataAccessException) return "DATABASE_FAILURE";
        return "INTERNAL_FAILURE";
    }

    private static PlatformMetrics.ProvisioningResource provisioningResource(String action) {
        return switch (action) {
            case TENANT_CREATE -> PlatformMetrics.ProvisioningResource.TENANT;
            case MEMBERSHIP_CREATE -> PlatformMetrics.ProvisioningResource.MEMBERSHIP;
            default -> null;
        };
    }

    private static PlatformMetrics.ProvisioningFailureReason provisioningFailureReason(
            RuntimeException failure) {
        if (failure instanceof DataAccessException) {
            return PlatformMetrics.ProvisioningFailureReason.DATABASE;
        }
        if (failure instanceof IllegalArgumentException) {
            return PlatformMetrics.ProvisioningFailureReason.INVALID_REQUEST;
        }
        if (isDenied(failure)) return PlatformMetrics.ProvisioningFailureReason.DENIED;
        return PlatformMetrics.ProvisioningFailureReason.INTERNAL;
    }

    @FunctionalInterface
    interface Work<T> {
        T run();
    }
}
