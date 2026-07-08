package gestudio.repositorios;

import jakarta.persistence.LockModeType;
import gestudio.entidades.Egreso;
import gestudio.entidades.EstadoPago;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

public interface EgresoRepositorio extends JpaRepository<Egreso, Long> {
    Optional<Egreso> findByIdempotencyKey(String idempotencyKey);
    Optional<Egreso> findByReversalIdempotencyKey(String idempotencyKey);
    List<Egreso> findByFechaBetweenOrderByFechaAscIdAsc(LocalDate desde, LocalDate hasta);
    List<Egreso> findByEstadoOrderByFechaDescIdDesc(EstadoPago estado);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select e from Egreso e where e.id = :id")
    Optional<Egreso> findByIdForUpdate(@Param("id") Long id);
}
