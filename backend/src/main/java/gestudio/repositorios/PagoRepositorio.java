package gestudio.repositorios;

import jakarta.persistence.LockModeType;
import gestudio.entidades.EstadoPago;
import gestudio.entidades.Pago;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

public interface PagoRepositorio extends JpaRepository<Pago, Long> {
    Optional<Pago> findByIdempotencyKey(String idempotencyKey);
    Optional<Pago> findByReversalIdempotencyKey(String idempotencyKey);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select p from Pago p where p.id = :id")
    Optional<Pago> findByIdForUpdate(@Param("id") Long id);

    Page<Pago> findByAlumnoId(Long alumnoId, Pageable pageable);
    List<Pago> findByFechaBetweenAndEstadoOrderByFechaAscIdAsc(LocalDate desde, LocalDate hasta, EstadoPago estado);
}
