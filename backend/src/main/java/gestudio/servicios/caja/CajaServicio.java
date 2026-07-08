package gestudio.servicios.caja;

import gestudio.dto.caja.response.MovimientoCajaResponse;
import gestudio.dto.caja.response.ResumenCajaResponse;
import gestudio.dto.PageResponse;
import gestudio.entidades.MovimientoCaja;
import gestudio.repositorios.MovimientoCajaRepositorio;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.data.domain.Pageable;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;

@Service
public class CajaServicio {
    private final MovimientoCajaRepositorio movimientos;

    public CajaServicio(MovimientoCajaRepositorio movimientos) {
        this.movimientos = movimientos;
    }

    @Transactional(readOnly = true)
    public ResumenCajaResponse obtenerResumen(LocalDate desde, LocalDate hasta, Pageable pageable) {
        if (hasta.isBefore(desde)) {
            throw new IllegalArgumentException("La fecha hasta no puede ser anterior a desde");
        }
        var totales = movimientos.totales(desde, hasta);
        BigDecimal ingresos = totales.getIngresos();
        BigDecimal egresos = totales.getEgresos();
        BigDecimal ajustesIngreso = totales.getAjustesIngreso();
        BigDecimal ajustesEgreso = totales.getAjustesEgreso();
        BigDecimal reversosIngreso = totales.getReversosIngreso();
        BigDecimal reversosEgreso = totales.getReversosEgreso();
        BigDecimal totalIngresos = ingresos.add(ajustesIngreso).add(reversosEgreso);
        BigDecimal totalEgresos = egresos.add(ajustesEgreso).add(reversosIngreso);
        var pagina = movimientos.findByFechaBetween(desde, hasta, pageable).map(this::respuesta);
        return new ResumenCajaResponse(desde, hasta, decimal(ingresos), decimal(egresos),
                decimal(ajustesIngreso), decimal(ajustesEgreso), decimal(reversosIngreso), decimal(reversosEgreso),
                decimal(totalIngresos), decimal(totalEgresos), decimal(totalIngresos.subtract(totalEgresos)),
                PageResponse.from(pagina));
    }

    private MovimientoCajaResponse respuesta(MovimientoCaja movimiento) {
        return new MovimientoCajaResponse(movimiento.getId(), movimiento.getTipo().name(), movimiento.getFecha(),
                decimal(movimiento.getImporte()), movimiento.getMetodoPago().getId(),
                movimiento.getPago() == null ? null : movimiento.getPago().getId(),
                movimiento.getEgreso() == null ? null : movimiento.getEgreso().getId(),
                movimiento.getMotivo(), movimiento.getCreatedAt());
    }

    private static String decimal(BigDecimal importe) {
        return importe.setScale(2, RoundingMode.UNNECESSARY).toPlainString();
    }
}
