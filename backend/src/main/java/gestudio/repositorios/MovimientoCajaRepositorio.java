package gestudio.repositorios;

import gestudio.entidades.MovimientoCaja;
import gestudio.entidades.TipoMovimientoCaja;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;

import java.math.BigDecimal;

import java.time.LocalDate;
import java.util.Optional;

public interface MovimientoCajaRepositorio extends JpaRepository<MovimientoCaja, Long> {
    Optional<MovimientoCaja> findByPagoIdAndTipo(Long pagoId, TipoMovimientoCaja tipo);
    Optional<MovimientoCaja> findByEgresoIdAndTipo(Long egresoId, TipoMovimientoCaja tipo);
    Page<MovimientoCaja> findByFechaBetween(LocalDate desde, LocalDate hasta, Pageable pageable);

    @Query(value = """
            SELECT coalesce(sum(m.importe) FILTER (WHERE m.tipo = 'INGRESO_PAGO'), 0) AS "ingresos",
                   coalesce(sum(m.importe) FILTER (WHERE m.tipo = 'EGRESO'), 0) AS "egresos",
                   coalesce(sum(m.importe) FILTER (WHERE m.tipo = 'AJUSTE_INGRESO'), 0) AS "ajustesIngreso",
                   coalesce(sum(m.importe) FILTER (WHERE m.tipo = 'AJUSTE_EGRESO'), 0) AS "ajustesEgreso",
                   coalesce(sum(m.importe) FILTER (
                       WHERE m.tipo = 'REVERSO' AND o.tipo IN ('INGRESO_PAGO','AJUSTE_INGRESO')
                   ), 0) AS "reversosIngreso",
                   coalesce(sum(m.importe) FILTER (
                       WHERE m.tipo = 'REVERSO' AND o.tipo IN ('EGRESO','AJUSTE_EGRESO')
                   ), 0) AS "reversosEgreso"
            FROM movimientos_caja m
            LEFT JOIN movimientos_caja o ON o.id = m.movimiento_revertido_id
            WHERE m.fecha BETWEEN :desde AND :hasta
            """, nativeQuery = true)
    CajaTotales totales(@Param("desde") LocalDate desde, @Param("hasta") LocalDate hasta);

    interface CajaTotales {
        BigDecimal getIngresos();
        BigDecimal getEgresos();
        BigDecimal getAjustesIngreso();
        BigDecimal getAjustesEgreso();
        BigDecimal getReversosIngreso();
        BigDecimal getReversosEgreso();
    }
}
