package gestudio.repositorios;

import jakarta.persistence.LockModeType;
import gestudio.entidades.RefreshSession;
import org.springframework.data.jpa.repository.*;
import org.springframework.data.repository.query.Param;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

public interface RefreshSessionRepositorio extends JpaRepository<RefreshSession, UUID> {
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select s from RefreshSession s join fetch s.usuario u join fetch u.rol where s.tokenHash = :hash")
    Optional<RefreshSession> findByTokenHashForUpdate(@Param("hash") String hash);

    @Modifying
    @Query("""
        update RefreshSession s set s.revokedAt = :now, s.revokeReason = :reason
        where s.familyId = :familyId and s.revokedAt is null
        """)
    int revokeFamily(@Param("familyId") UUID familyId, @Param("now") Instant now, @Param("reason") String reason);
}
