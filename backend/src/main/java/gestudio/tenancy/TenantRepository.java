package gestudio.tenancy;

import org.springframework.data.jpa.repository.Query;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.repository.Repository;
import org.springframework.data.repository.query.Param;
import jakarta.persistence.LockModeType;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface TenantRepository extends Repository<Tenant, UUID> {
    Optional<Tenant> findById(UUID id);

    Optional<Tenant> findByCodeIgnoreCase(String code);

    Tenant save(Tenant tenant);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select t from Tenant t where t.id = :id")
    Optional<Tenant> findByIdForUpdate(UUID id);

    @Query(value = """
            SELECT 1 FROM pg_advisory_xact_lock(
                hashtextextended('gestudio:tenant-admin:' || CAST(:tenantId AS text), 0))
            """, nativeQuery = true)
    int lockAdministratorMutations(@Param("tenantId") UUID tenantId);

    @Query("select t.id from Tenant t where t.status = gestudio.tenancy.TenantStatus.ACTIVE order by t.id")
    List<UUID> findAllActiveIds();

    @Query("select t.id from Tenant t order by t.id")
    List<UUID> findAllIds();
}
