package gestudio.repositorios;

import gestudio.entidades.AplicacionPago;
import gestudio.entidades.EstadoAplicacionPago;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.repository.query.Param;

import java.math.BigDecimal;
import java.util.List;

public interface AplicacionPagoRepositorio extends JpaRepository<AplicacionPago, Long> {
    @EntityGraph(attributePaths = "cargo")
    List<AplicacionPago> findByPagoIdOrderById(Long pagoId);
    List<AplicacionPago> findByPagoIdAndEstadoOrderById(Long pagoId, EstadoAplicacionPago estado);

    @Query("select coalesce(sum(a.importeAplicado), 0) from AplicacionPago a where a.cargo.id = :cargoId and a.estado = :estado")
    BigDecimal sumByCargoAndEstado(@Param("cargoId") Long cargoId, @Param("estado") EstadoAplicacionPago estado);

    @Query("""
        select a.cargo.id, sum(a.importeAplicado)
        from AplicacionPago a
        where a.cargo.id in :cargoIds and a.estado = :estado
        group by a.cargo.id
        """)
    List<Object[]> sumByCargoIdsAndEstado(@Param("cargoIds") List<Long> cargoIds,
                                          @Param("estado") EstadoAplicacionPago estado);
}
