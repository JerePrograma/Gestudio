package gestudio.tenancy;

import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.Repository;
import org.springframework.data.repository.query.Param;

import java.util.Collection;
import java.util.UUID;

public interface TenantMembershipRoleRepository extends Repository<TenantMembershipRole, TenantMembershipRoleId> {
    <S extends TenantMembershipRole> Iterable<S> saveAll(Iterable<S> assignments);

    @Modifying
    @Query("delete from TenantMembershipRole a where a.membership.id = :membershipId")
    int deleteByMembershipId(@Param("membershipId") UUID membershipId);
}
