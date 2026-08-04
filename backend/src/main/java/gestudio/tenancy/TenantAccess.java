package gestudio.tenancy;

import gestudio.entidades.Usuario;
import org.springframework.security.core.GrantedAuthority;

import java.util.List;
import java.util.Set;
import java.util.UUID;

public record TenantAccess(TenantMembership membership) {
    public UUID tenantId() {
        return membership.getTenant().getId();
    }

    public UUID membershipId() {
        return membership.getId();
    }

    public long tenantSecurityVersion() {
        return membership.getTenant().getSecurityVersion();
    }

    public long membershipSecurityVersion() {
        return membership.getSecurityVersion();
    }

    public Usuario usuario() {
        return membership.getUsuario();
    }

    public List<GrantedAuthority> authorities() {
        return membership.authorities();
    }

    public Set<String> roleCodes() {
        return membership.roleCodes();
    }

    public Set<String> permissionCodes() {
        return membership.permissionCodes();
    }

    public String primaryRoleCode() {
        return roleCodes().stream()
                .sorted((left, right) -> {
                    if ("SUPERADMIN".equalsIgnoreCase(left)) return -1;
                    if ("SUPERADMIN".equalsIgnoreCase(right)) return 1;
                    return left.compareTo(right);
                })
                .findFirst()
                .orElseThrow(() -> new IllegalStateException("Membership without active roles"));
    }

    public TenantSelection tenant() {
        Tenant value = membership.getTenant();
        return new TenantSelection(value.getId(), value.getCode(), value.getName(), value.getStatus());
    }
}
