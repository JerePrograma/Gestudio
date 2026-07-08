package gestudio.repositorios;

import gestudio.entidades.EstadoReciboPendiente;
import gestudio.entidades.ReciboPendiente;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.repository.query.Param;

import java.time.Instant;
import java.util.Optional;
import java.util.List;
import java.util.UUID;

public interface ReciboPendienteRepositorio extends JpaRepository<ReciboPendiente, Long> {
    @Query(value = """
            SELECT * FROM recibos_pendientes r
            WHERE (r.estado = 'PENDIENTE' AND r.next_attempt_at <= :ahora)
               OR (r.estado = 'PROCESANDO' AND r.lease_until <= :ahora)
            ORDER BY r.id
            LIMIT :limite
            FOR UPDATE SKIP LOCKED
            """, nativeQuery = true)
    List<ReciboPendiente> findClaimableForUpdate(@Param("ahora") Instant ahora, @Param("limite") int limite);

    @EntityGraph(attributePaths = {"pago", "pago.alumno", "pago.metodoPago"})
    Optional<ReciboPendiente> findByIdAndClaimToken(Long id, UUID claimToken);
}
