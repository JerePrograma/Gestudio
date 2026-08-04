package gestudio.tenancy;

import java.util.UUID;

public record TenantSelection(UUID id, String code, String name, TenantStatus status) {
}
