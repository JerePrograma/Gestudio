package gestudio.tenancy;

import jakarta.persistence.Column;
import jakarta.persistence.Embeddable;
import lombok.AllArgsConstructor;
import lombok.EqualsAndHashCode;
import lombok.NoArgsConstructor;

import java.io.Serializable;
import java.util.UUID;

@Embeddable
@EqualsAndHashCode
@NoArgsConstructor
@AllArgsConstructor
public class TenantMembershipRoleId implements Serializable {
    @Column(name = "membership_id")
    private UUID membershipId;

    @Column(name = "role_id")
    private Long roleId;

    @Column(name = "tenant_id")
    private UUID tenantId;
}
