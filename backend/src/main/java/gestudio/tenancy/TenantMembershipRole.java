package gestudio.tenancy;

import gestudio.entidades.Rol;
import jakarta.persistence.EmbeddedId;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.MapsId;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.Instant;

import gestudio.entidades.Usuario;

@Entity
@Getter
@NoArgsConstructor
@Table(name = "tenant_membership_roles")
public class TenantMembershipRole {
    @EmbeddedId
    private TenantMembershipRoleId id;

    @MapsId("membershipId")
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "membership_id", nullable = false)
    private TenantMembership membership;

    @MapsId("roleId")
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "role_id", nullable = false)
    private Rol role;

    @MapsId("tenantId")
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "tenant_id", nullable = false)
    private Tenant tenant;

    @jakarta.persistence.Column(name = "assigned_at", nullable = false, insertable = false, updatable = false)
    private Instant assignedAt;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "assigned_by_usuario_id")
    private Usuario assignedBy;

    public TenantMembershipRole(TenantMembership membership, Tenant tenant, Rol role) {
        this(membership, tenant, role, null);
    }

    public TenantMembershipRole(TenantMembership membership, Tenant tenant, Rol role, Usuario assignedBy) {
        this.id = new TenantMembershipRoleId(membership.getId(), role.getId(), tenant.getId());
        this.membership = membership;
        this.tenant = tenant;
        this.role = role;
        this.assignedBy = assignedBy;
    }
}
