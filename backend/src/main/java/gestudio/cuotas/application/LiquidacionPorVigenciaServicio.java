package gestudio.cuotas.application;

import jakarta.persistence.EntityNotFoundException;
import gestudio.entidades.Inscripcion;
import gestudio.infra.errores.TratadorDeErrores.OperacionNoPermitidaException;
import gestudio.repositorios.InscripcionRepositorio;
import gestudio.tarifas.application.CondicionEconomicaServicio;
import gestudio.tarifas.application.TarifaDisciplinaServicio;
import gestudio.tarifas.persistence.CondicionEconomicaInscripcion;
import gestudio.tarifas.persistence.TarifaDisciplina;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.util.Optional;

@Service
public class LiquidacionPorVigenciaServicio {
    private static final BigDecimal CIEN = new BigDecimal("100");
    private static final int FORMULA_VERSION = 1;

    private final InscripcionRepositorio inscripciones;
    private final TarifaDisciplinaServicio tarifas;
    private final CondicionEconomicaServicio condiciones;

    public LiquidacionPorVigenciaServicio(InscripcionRepositorio inscripciones,
                                          TarifaDisciplinaServicio tarifas,
                                          CondicionEconomicaServicio condiciones) {
        this.inscripciones = inscripciones;
        this.tarifas = tarifas;
        this.condiciones = condiciones;
    }

    @Transactional(readOnly = true)
    public ResultadoLiquidacion liquidarMensualidad(Long inscripcionId, LocalDate fechaEfectiva) {
        return liquidar(inscripcionId, fechaEfectiva, TipoImporte.MENSUALIDAD);
    }

    @Transactional(readOnly = true)
    public ResultadoLiquidacion liquidarMatricula(Long inscripcionId, LocalDate fechaEfectiva) {
        return liquidar(inscripcionId, fechaEfectiva, TipoImporte.MATRICULA);
    }

    private ResultadoLiquidacion liquidar(Long inscripcionId,
                                           LocalDate fechaEfectiva,
                                           TipoImporte tipoImporte) {
        if (fechaEfectiva == null) {
            throw new IllegalArgumentException("La fecha efectiva es obligatoria");
        }

        Inscripcion inscripcion = inscripciones.findById(inscripcionId)
                .orElseThrow(() -> new EntityNotFoundException("Inscripción no encontrada"));
        Long disciplinaId = inscripcion.getDisciplina().getId();
        TarifaDisciplina tarifa = tarifas.vigente(disciplinaId, fechaEfectiva);
        Optional<CondicionEconomicaInscripcion> condicion = condiciones.vigenteOpcional(
                inscripcionId, fechaEfectiva);

        BigDecimal tarifaBase = tipoImporte == TipoImporte.MENSUALIDAD
                ? tarifa.getValorCuota()
                : tarifa.getMatricula();
        BigDecimal costoParticular = condicion.map(CondicionEconomicaInscripcion::getCostoParticular)
                .orElse(null);
        OrigenPrecioLiquidacion origen = costoParticular == null
                ? OrigenPrecioLiquidacion.TARIFA_HISTORICA
                : OrigenPrecioLiquidacion.COSTO_PARTICULAR;
        BigDecimal importeBase = moneda(costoParticular == null ? tarifaBase : costoParticular, "importe base");

        BigDecimal descuentoPorcentaje = condicion
                .map(CondicionEconomicaInscripcion::getBonificacionPorcentajeSnapshot)
                .orElse(BigDecimal.ZERO)
                .setScale(4, RoundingMode.UNNECESSARY);
        BigDecimal descuentoFijo = moneda(condicion
                .map(CondicionEconomicaInscripcion::getBonificacionValorFijoSnapshot)
                .orElse(BigDecimal.ZERO), "descuento fijo");
        BigDecimal descuentoPorcentajeImporte = importeBase.multiply(descuentoPorcentaje)
                .divide(CIEN, 2, RoundingMode.HALF_UP);
        BigDecimal descuentoImporte = descuentoPorcentajeImporte.add(descuentoFijo)
                .setScale(2, RoundingMode.HALF_UP);
        BigDecimal importeFinal = importeBase.subtract(descuentoImporte)
                .setScale(2, RoundingMode.HALF_UP);

        if (importeFinal.signum() < 0) {
            throw new OperacionNoPermitidaException(
                    "El descuento supera el importe base de la liquidación");
        }

        String observaciones = "%s; inscripción=%d; disciplina=%d; fechaEfectiva=%s".formatted(
                tipoImporte.name(), inscripcionId, disciplinaId, fechaEfectiva);

        return new ResultadoLiquidacion(
                fechaEfectiva,
                tarifa,
                condicion,
                origen,
                importeBase,
                descuentoPorcentaje,
                descuentoImporte,
                importeFinal,
                FORMULA_VERSION,
                observaciones
        );
    }

    private static BigDecimal moneda(BigDecimal valor, String nombre) {
        if (valor == null) {
            throw new IllegalStateException("La tarifa no define " + nombre);
        }
        BigDecimal normalizado = valor.setScale(2, RoundingMode.UNNECESSARY);
        if (normalizado.signum() < 0) {
            throw new OperacionNoPermitidaException("El " + nombre + " no puede ser negativo");
        }
        return normalizado;
    }

    private enum TipoImporte {
        MENSUALIDAD,
        MATRICULA
    }
}
