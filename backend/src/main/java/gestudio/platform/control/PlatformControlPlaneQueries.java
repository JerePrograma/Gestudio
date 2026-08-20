package gestudio.platform.control;

import gestudio.infra.errores.TratadorDeErrores.RecursoNoEncontradoException;
import gestudio.tenancy.TenantContext;

import java.util.List;
import java.util.UUID;

import static gestudio.platform.control.PlatformControlPlaneService.ACTIVE;
import static gestudio.platform.control.PlatformControlPlaneService.ARCHIVED;
import static gestudio.platform.control.PlatformControlPlaneService.REVOKED;
import static gestudio.platform.control.PlatformControlPlaneService.SUSPENDED;

final class PlatformControlPlaneQueries {
    private final PlatformControlPlaneRepository repository;
    private final PlatformControlPlaneCommandSupport commands;

    PlatformControlPlaneQueries(PlatformControlPlaneRepository repository,
                                PlatformControlPlaneCommandSupport commands) {
        this.repository = repository;
        this.commands = commands;
    }

    PlatformControlPlaneRepository.PageData<PlatformControlPlaneRepository.TenantView> tenants(
            String query, String status, int page, int size) {
        validatePage(page, size);
        validateOptionalStatus(status, List.of(ACTIVE, SUSPENDED, ARCHIVED));
        return repository.tenants(query, status, page, size);
    }

    PlatformControlPlaneRepository.TenantView tenant(UUID tenantId) {
        return inTenant(tenantId, () -> repository.tenant(tenantId).orElseThrow(
                () -> new RecursoNoEncontradoException("Tenant no encontrado")));
    }

    PlatformControlPlaneRepository.PageData<PlatformControlPlaneRepository.MembershipView> memberships(
            UUID tenantId, String query, String status, int page, int size) {
        validatePage(page, size);
        validateOptionalStatus(status, List.of(ACTIVE, SUSPENDED, REVOKED));
        return inTenant(tenantId, () -> {
            requireTenant(tenantId);
            return repository.memberships(tenantId, query, status, page, size);
        });
    }

    List<PlatformControlPlaneRepository.RoleView> roles(UUID tenantId) {
        return inTenant(tenantId, () -> {
            requireTenant(tenantId);
            return repository.roles(tenantId);
        });
    }

    List<PlatformControlPlaneRepository.IdentityView> identities(String query) {
        return repository.identities(query);
    }

    PlatformControlPlaneRepository.PageData<PlatformControlPlaneRepository.AdminView> admins(
            String query, String status, int page, int size) {
        validatePage(page, size);
        validateOptionalStatus(status, List.of(ACTIVE, REVOKED));
        return repository.admins(query, status, page, size);
    }

    PlatformControlPlaneRepository.PageData<PlatformControlPlaneRepository.AuditView> audit(
            PlatformControlPlaneRepository.AuditFilter filter, int page, int size) {
        validatePage(page, size);
        validateOptionalStatus(filter.result(), List.of("SUCCESS", "DENIED", "FAILED"));
        if (filter.from() != null && filter.to() != null && filter.from().isAfter(filter.to())) {
            throw new IllegalArgumentException("El rango temporal de auditoría es inválido");
        }
        return repository.audit(filter, page, size);
    }

    private void validateOptionalStatus(String value, List<String> allowed) {
        if (value != null && !value.isBlank()) commands.requiredStatus(value, allowed);
    }

    private static void validatePage(int page, int size) {
        if (page < 0 || size < 1 || size > 100) {
            throw new IllegalArgumentException("Paginación inválida");
        }
    }

    private PlatformControlPlaneRepository.TenantView requireTenant(UUID tenantId) {
        return repository.tenant(tenantId).orElseThrow(
                () -> new RecursoNoEncontradoException("Tenant no encontrado"));
    }

    private <T> T inTenant(UUID tenantId, Work<T> work) {
        try (TenantContext.Scope ignored = TenantContext.open(tenantId, null)) {
            return work.run();
        }
    }

    @FunctionalInterface
    private interface Work<T> {
        T run();
    }
}
