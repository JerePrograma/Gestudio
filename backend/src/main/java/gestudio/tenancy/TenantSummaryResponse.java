package gestudio.tenancy;

import java.util.UUID;

public record TenantSummaryResponse(UUID id, String codigo, String nombre, TenantStatus estado) {
    public static TenantSummaryResponse from(TenantSelection tenant) {
        return new TenantSummaryResponse(tenant.id(), tenant.code(), tenant.name(), tenant.status());
    }
}
