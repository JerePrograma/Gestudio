package gestudio.repositorios;

import gestudio.entidades.MovimientoCredito;
import gestudio.entidades.TipoMovimientoCredito;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;

import jakarta.persistence.LockModeType;

public interface MovimientoCreditoRepositorio extends JpaRepository<MovimientoCredito, Long> {
    List<MovimientoCredito> findByPagoId(Long pagoId);
    Optional<MovimientoCredito> findByIdempotencyKey(String idempotencyKey);
    Optional<MovimientoCredito> findByMovimientoRevertidoId(Long movimientoRevertidoId);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select m from MovimientoCredito m where m.id = :id")
    Optional<MovimientoCredito> findByIdForUpdate(@Param("id") Long id);

    @Query("""
        select coalesce(sum(case
            when m.tipo in (gestudio.entidades.TipoMovimientoCredito.GENERACION, gestudio.entidades.TipoMovimientoCredito.AJUSTE_CREDITO) then m.importe
            when m.tipo in (gestudio.entidades.TipoMovimientoCredito.CONSUMO, gestudio.entidades.TipoMovimientoCredito.AJUSTE_DEBITO) then -m.importe
            when r.tipo in (gestudio.entidades.TipoMovimientoCredito.GENERACION, gestudio.entidades.TipoMovimientoCredito.AJUSTE_CREDITO) then -m.importe
            else m.importe end), 0)
        from MovimientoCredito m left join m.movimientoRevertido r where m.alumno.id = :alumnoId
        """)
    BigDecimal saldoByAlumnoId(@Param("alumnoId") Long alumnoId);

    @Query("""
        select coalesce(sum(case
            when m.tipo = gestudio.entidades.TipoMovimientoCredito.CONSUMO then m.importe
            else -m.importe end), 0)
        from MovimientoCredito m left join m.movimientoRevertido r
        where (m.tipo = gestudio.entidades.TipoMovimientoCredito.CONSUMO and m.cargo.id = :cargoId)
           or (m.tipo = gestudio.entidades.TipoMovimientoCredito.REVERSO
               and r.tipo = gestudio.entidades.TipoMovimientoCredito.CONSUMO
               and r.cargo.id = :cargoId)
        """)
    BigDecimal sumAplicadoByCargoId(@Param("cargoId") Long cargoId);

    @Query(value = """
        SELECT cargo_id, sum(importe)
        FROM (
            SELECT cargo_id, importe
            FROM movimientos_credito
            WHERE tipo = 'CONSUMO' AND cargo_id IN (:cargoIds)
            UNION ALL
            SELECT original.cargo_id, -reverso.importe
            FROM movimientos_credito reverso
            JOIN movimientos_credito original ON original.id = reverso.movimiento_revertido_id
            WHERE reverso.tipo = 'REVERSO'
              AND original.tipo = 'CONSUMO'
              AND original.cargo_id IN (:cargoIds)
        ) aplicaciones_credito
        GROUP BY cargo_id
        """, nativeQuery = true)
    List<Object[]> sumAplicadoByCargoIds(@Param("cargoIds") List<Long> cargoIds);
}
