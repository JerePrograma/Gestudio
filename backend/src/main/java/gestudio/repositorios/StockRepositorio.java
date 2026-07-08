package gestudio.repositorios;

import jakarta.persistence.LockModeType;
import gestudio.entidades.Stock;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface StockRepositorio extends JpaRepository<Stock, Long> {
    List<Stock> findByActivoTrue();
    Optional<Stock> findByNombreIgnoreCase(String nombre);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select s from Stock s where s.id = :id and s.activo = true")
    Optional<Stock> findActivoByIdForUpdate(@Param("id") Long id);
}
