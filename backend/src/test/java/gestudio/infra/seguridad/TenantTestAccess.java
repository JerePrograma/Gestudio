package gestudio.infra.seguridad;

import gestudio.entidades.Rol;
import gestudio.entidades.Usuario;
import gestudio.tenancy.Tenant;
import gestudio.tenancy.TenantAccess;
import gestudio.tenancy.TenantMembership;
import gestudio.tenancy.TenantMembershipRole;
import gestudio.tenancy.TenantMembershipStatus;
import gestudio.tenancy.TenantStatus;

import java.time.Instant;
import java.util.UUID;

public final class TenantTestAccess {
    private TenantTestAccess() {
    }

    public static TenantAccess from(Usuario user) {
        Tenant tenant = new Tenant();
        tenant.setId(UUID.fromString("10000000-0000-0000-0000-000000000001"));
        tenant.setCode("TEST");
        tenant.setName("Test");
        tenant.setStatus(TenantStatus.ACTIVE);
        tenant.setSecurityVersion(0L);

        TenantMembership membership = new TenantMembership();
        membership.setId(UUID.nameUUIDFromBytes(("membership-" + user.getId())
                .getBytes(java.nio.charset.StandardCharsets.UTF_8)));
        membership.setTenant(tenant);
        membership.setUsuario(user);
        membership.setStatus(TenantMembershipStatus.ACTIVE);
        membership.setSecurityVersion(0L);
        membership.setValidFrom(Instant.EPOCH);
        for (Rol role : user.rolesEfectivos()) {
            membership.getRoleAssignments().add(new TenantMembershipRole(membership, tenant, role));
        }
        return new TenantAccess(membership);
    }
}
