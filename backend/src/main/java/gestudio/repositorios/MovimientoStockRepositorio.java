package gestudio.repositorios;

import gestudio.entidades.MovimientoStock;
import gestudio.entidades.TipoMovimientoStock;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface MovimientoStockRepositorio extends JpaRepository<MovimientoStock, Long> {
    List<MovimientoStock> findByStockIdOrderByCreatedAtAscIdAsc(Long stockId);
    Optional<MovimientoStock> findByVentaStockIdAndTipo(Long ventaStockId, TipoMovimientoStock tipo);
}
