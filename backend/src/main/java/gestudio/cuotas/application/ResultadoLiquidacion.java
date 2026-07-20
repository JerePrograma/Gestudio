package gestudio.cuotas.application;

import gestudio.tarifas.persistence.CondicionEconomicaInscripcion;
import gestudio.tarifas.persistence.TarifaDisciplina;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.Optional;

public record ResultadoLiquidacion(
        LocalDate fechaEfectiva,
        TarifaDisciplina tarifa,
        Optional<CondicionEconomicaInscripcion> condicion,
        OrigenPrecioLiquidacion origen,
        BigDecimal importeBase,
        BigDecimal descuentoPorcentaje,
        BigDecimal descuentoImporte,
        BigDecimal importeFinal,
        int formulaVersion,
        String observaciones
) {
    public ResultadoLiquidacion {
        condicion = condicion == null ? Optional.empty() : condicion;
    }
}
