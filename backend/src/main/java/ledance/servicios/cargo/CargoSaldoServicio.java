package ledance.servicios.cargo;

import jakarta.persistence.EntityNotFoundException;
import ledance.entidades.Cargo;
import ledance.entidades.EstadoAplicacionPago;
import ledance.entidades.EstadoCargo;
import ledance.repositorios.AplicacionPagoRepositorio;
import ledance.repositorios.CargoRepositorio;
import ledance.repositorios.MovimientoCreditoRepositorio;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.function.Function;
import java.util.stream.Collectors;

@Service
public class CargoSaldoServicio {
    private final CargoRepositorio cargos;
    private final AplicacionPagoRepositorio aplicaciones;
    private final MovimientoCreditoRepositorio movimientosCredito;

    public CargoSaldoServicio(CargoRepositorio cargos,
                              AplicacionPagoRepositorio aplicaciones,
                              MovimientoCreditoRepositorio movimientosCredito) {
        this.cargos = cargos;
        this.aplicaciones = aplicaciones;
        this.movimientosCredito = movimientosCredito;
    }

    @Transactional(readOnly = true)
    public SaldoCargo calcular(Long cargoId) {
        return calcular(cargos.findById(cargoId)
                .orElseThrow(() -> new EntityNotFoundException("Cargo no encontrado")));
    }

    @Transactional(readOnly = true)
    public SaldoCargo calcular(Cargo cargo) {
        return resultado(cargo,
                aplicaciones.sumByCargoAndEstado(cargo.getId(), EstadoAplicacionPago.APLICADA),
                movimientosCredito.sumAplicadoByCargoId(cargo.getId()));
    }

    @Transactional(readOnly = true)
    public Map<Long, SaldoCargo> calcularBatch(Collection<Long> cargoIds) {
        List<Long> ids = cargoIds.stream().filter(id -> id != null).distinct().toList();
        if (ids.isEmpty()) return Map.of();

        Map<Long, Cargo> porId = cargos.findAllById(ids).stream()
                .collect(Collectors.toMap(Cargo::getId, Function.identity()));
        if (porId.size() != ids.size()) {
            throw new EntityNotFoundException("Uno o más cargos no existen");
        }
        Map<Long, BigDecimal> pagos = importes(
                aplicaciones.sumByCargoIdsAndEstado(ids, EstadoAplicacionPago.APLICADA));
        Map<Long, BigDecimal> credito = importes(movimientosCredito.sumAplicadoByCargoIds(ids));

        Map<Long, SaldoCargo> resultado = new LinkedHashMap<>();
        ids.forEach(id -> resultado.put(id, resultado(
                porId.get(id), pagos.getOrDefault(id, BigDecimal.ZERO), credito.getOrDefault(id, BigDecimal.ZERO))));
        return resultado;
    }

    private SaldoCargo resultado(Cargo cargo, BigDecimal pagos, BigDecimal credito) {
        BigDecimal importeOriginal = moneda(cargo.getImporteOriginal());
        BigDecimal aplicadoPagos = moneda(pagos);
        BigDecimal aplicadoCredito = moneda(credito);
        BigDecimal saldo = importeOriginal.subtract(aplicadoPagos).subtract(aplicadoCredito)
                .setScale(2, RoundingMode.UNNECESSARY);
        if (saldo.signum() < 0) {
            throw new IllegalStateException("Saldo negativo para cargo " + cargo.getId());
        }
        EstadoCargo esperado = cargo.getEstado() == EstadoCargo.ANULADO ? EstadoCargo.ANULADO
                : saldo.signum() == 0 ? EstadoCargo.PAGADO
                : saldo.compareTo(importeOriginal) == 0 ? EstadoCargo.PENDIENTE : EstadoCargo.PARCIAL;
        return new SaldoCargo(importeOriginal, aplicadoPagos, aplicadoCredito, saldo, esperado);
    }

    private static Map<Long, BigDecimal> importes(List<Object[]> filas) {
        return filas.stream().collect(Collectors.toMap(
                fila -> ((Number) fila[0]).longValue(), fila -> moneda((BigDecimal) fila[1])));
    }

    private static BigDecimal moneda(BigDecimal importe) {
        return (importe == null ? BigDecimal.ZERO : importe).setScale(2, RoundingMode.UNNECESSARY);
    }
}
