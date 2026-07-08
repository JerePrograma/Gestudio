package gestudio.repositorios;

import gestudio.entidades.VentaStock;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import jakarta.persistence.LockModeType;

public interface VentaStockRepositorio extends JpaRepository<VentaStock, Long> {
    Optional<VentaStock> findByIdempotencyKey(String idempotencyKey);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select v from VentaStock v where v.id = :id")
    Optional<VentaStock> findByIdForUpdate(@Param("id") Long id);
}
