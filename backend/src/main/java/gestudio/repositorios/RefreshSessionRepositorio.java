package gestudio.repositorios;

import gestudio.entidades.RefreshSession;
import org.springframework.data.jpa.repository.*;
import org.springframework.data.repository.query.Param;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

public interface RefreshSessionRepositorio extends JpaRepository<RefreshSession, UUID> {
    @Query(value = """
            SELECT session.*
            FROM refresh_sessions session
            WHERE session.token_hash = :hash
            FOR NO KEY UPDATE OF session
            """, nativeQuery = true)
    Optional<RefreshSession> findByTokenHashForUpdate(@Param("hash") String hash);

    @Modifying
    @Query("""
        update RefreshSession s set s.revokedAt = :now, s.revokeReason = :reason
        where s.familyId = :familyId and s.revokedAt is null
        """)
    int revokeFamily(@Param("familyId") UUID familyId, @Param("now") Instant now, @Param("reason") String reason);
}
