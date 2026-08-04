package gestudio.tenancy;

import org.springframework.data.jpa.repository.Query;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.repository.Repository;
import org.springframework.data.repository.query.Param;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import jakarta.persistence.LockModeType;

public interface TenantMembershipRepository extends Repository<TenantMembership, UUID> {
    TenantMembership save(TenantMembership membership);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("""
            select m from TenantMembership m
            join fetch m.tenant
            join fetch m.usuario
            where m.tenant.id = :tenantId and m.usuario.id = :userId
            """)
    Optional<TenantMembership> findByTenantAndUserForUpdate(@Param("tenantId") UUID tenantId,
                                                             @Param("userId") Long userId);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("""
            select m from TenantMembership m
            join fetch m.tenant
            join fetch m.usuario
            where m.tenant.id = :tenantId and m.id = :membershipId
            """)
    Optional<TenantMembership> findByTenantAndIdForUpdate(@Param("tenantId") UUID tenantId,
                                                           @Param("membershipId") UUID membershipId);

    @Query("""
            select distinct m from TenantMembership m
            join fetch m.tenant t
            join fetch m.usuario
            join fetch m.roleAssignments a
            join fetch a.role r
            left join fetch r.permisos
            where t.id = :tenantId and m.usuario.id = :userId
            """)
    Optional<TenantMembership> findForTenantAndUser(@Param("tenantId") UUID tenantId,
                                                     @Param("userId") Long userId);

    @Query("""
            select distinct m from TenantMembership m
            join fetch m.tenant t
            join fetch m.usuario
            join fetch m.roleAssignments a
            join fetch a.role r
            left join fetch r.permisos
            where t.id = :tenantId
            order by m.usuario.nombreUsuario
            """)
    List<TenantMembership> findAllForTenant(@Param("tenantId") UUID tenantId);

    @Query("""
            select count(distinct m.id) from TenantMembership m
            join m.roleAssignments a join a.role r
            where m.tenant.id = :tenantId
              and m.status = gestudio.tenancy.TenantMembershipStatus.ACTIVE
              and r.activo = true and upper(r.codigo) = 'SUPERADMIN'
            """)
    long countActiveSuperadmins(@Param("tenantId") UUID tenantId);

    @Modifying
    @Query(value = """
            UPDATE tenant_memberships m
            SET security_version = security_version + 1,
                updated_at = CURRENT_TIMESTAMP
            WHERE m.tenant_id = :tenantId
              AND EXISTS (
                  SELECT 1 FROM tenant_membership_roles mr
                  WHERE mr.membership_id = m.id
                    AND mr.tenant_id = m.tenant_id
                    AND mr.role_id = :roleId
              )
            """, nativeQuery = true)
    int incrementSecurityVersionForRole(@Param("tenantId") UUID tenantId, @Param("roleId") Long roleId);

    @Query("""
            select distinct new gestudio.tenancy.TenantSelection(t.id, t.code, t.name, t.status)
            from TenantMembership m join m.tenant t
            where m.usuario.id = :userId
              and m.usuario.activo = true
              and m.status = gestudio.tenancy.TenantMembershipStatus.ACTIVE
              and t.status = gestudio.tenancy.TenantStatus.ACTIVE
              and m.validFrom <= :now
              and (m.validUntil is null or m.validUntil > :now)
            order by t.name, t.id
            """)
    List<TenantSelection> findActiveSelections(@Param("userId") Long userId, @Param("now") Instant now);

    @Query("""
            select distinct m from TenantMembership m
            join fetch m.tenant t
            join fetch m.usuario u
            join fetch m.roleAssignments a
            join fetch a.role r
            left join fetch r.permisos p
            where u.id = :userId
              and u.activo = true
              and m.id = :membershipId
              and t.id = :tenantId
              and m.status = gestudio.tenancy.TenantMembershipStatus.ACTIVE
              and t.status = gestudio.tenancy.TenantStatus.ACTIVE
              and m.validFrom <= :now
              and (m.validUntil is null or m.validUntil > :now)
            """)
    Optional<TenantMembership> findActiveAccess(@Param("userId") Long userId,
                                                 @Param("membershipId") UUID membershipId,
                                                 @Param("tenantId") UUID tenantId,
                                                 @Param("now") Instant now);

    @Query("""
            select distinct m from TenantMembership m
            join fetch m.tenant t
            join fetch m.usuario u
            join fetch m.roleAssignments a
            join fetch a.role r
            left join fetch r.permisos p
            where u.id = :userId
              and u.activo = true
              and t.id = :tenantId
              and m.status = gestudio.tenancy.TenantMembershipStatus.ACTIVE
              and t.status = gestudio.tenancy.TenantStatus.ACTIVE
              and m.validFrom <= :now
              and (m.validUntil is null or m.validUntil > :now)
            """)
    Optional<TenantMembership> findActiveAccess(@Param("userId") Long userId,
                                                 @Param("tenantId") UUID tenantId,
                                                 @Param("now") Instant now);
}
