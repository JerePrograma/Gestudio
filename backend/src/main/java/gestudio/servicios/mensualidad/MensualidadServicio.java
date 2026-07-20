package gestudio.servicios.mensualidad;

import jakarta.persistence.EntityNotFoundException;
import gestudio.cuotas.application.LiquidacionCargoServicio;
import gestudio.cuotas.application.LiquidacionPorVigenciaServicio;
import gestudio.cuotas.application.ResultadoLiquidacion;
import gestudio.dto.mensualidad.request.MensualidadRegistroRequest;
import gestudio.dto.mensualidad.response.MensualidadResponse;
import gestudio.entidades.Cargo;
import gestudio.entidades.EstadoCargo;
import gestudio.entidades.EstadoInscripcion;
import gestudio.entidades.EstadoOrigenCargo;
import gestudio.entidades.Inscripcion;
import gestudio.entidades.Mensualidad;
import gestudio.entidades.Recargo;
import gestudio.infra.errores.TratadorDeErrores.OperacionNoPermitidaException;
import gestudio.repositorios.CargoRepositorio;
import gestudio.repositorios.InscripcionRepositorio;
import gestudio.repositorios.MensualidadRepositorio;
import gestudio.repositorios.RecargoRepositorio;
import gestudio.servicios.cargo.CargoServicio;
import gestudio.servicios.cargo.CargoSaldoServicio;
import gestudio.servicios.cargo.SaldoCargo;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Clock;
import java.time.LocalDate;
import java.time.YearMonth;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.function.Function;
import java.util.stream.Collectors;

@Service
public class MensualidadServicio {
    private static final Logger log = LoggerFactory.getLogger(MensualidadServicio.class);

    private final MensualidadRepositorio mensualidades;
    private final InscripcionRepositorio inscripciones;
    private final RecargoRepositorio recargos;
    private final CargoRepositorio cargos;
    private final CargoServicio cargoServicio;
    private final CargoSaldoServicio saldos;
    private final LiquidacionPorVigenciaServicio liquidacionesPorVigencia;
    private final LiquidacionCargoServicio liquidacionesCargo;
    private final Clock clock;

    public MensualidadServicio(MensualidadRepositorio mensualidades,
                               InscripcionRepositorio inscripciones,
                               RecargoRepositorio recargos,
                               CargoRepositorio cargos,
                               CargoServicio cargoServicio,
                               CargoSaldoServicio saldos,
                               LiquidacionPorVigenciaServicio liquidacionesPorVigencia,
                               LiquidacionCargoServicio liquidacionesCargo,
                               Clock clock) {
        this.mensualidades = mensualidades;
        this.inscripciones = inscripciones;
        this.recargos = recargos;
        this.cargos = cargos;
        this.cargoServicio = cargoServicio;
        this.saldos = saldos;
        this.liquidacionesPorVigencia = liquidacionesPorVigencia;
        this.liquidacionesCargo = liquidacionesCargo;
        this.clock = clock;
    }

    @Transactional
    public MensualidadResponse crearMensualidad(MensualidadRegistroRequest request) {
        validarBonificacionLegacy(request.bonificacionId());
        Inscripcion inscripcion = inscripciones.findByIdForUpdate(request.inscripcionId())
                .orElseThrow(() -> new EntityNotFoundException("Inscripción no encontrada"));
        return respuesta(generar(inscripcion, request.anio(), request.mes(), request.recargoId()));
    }

    @Transactional(readOnly = true)
    public MensualidadResponse obtenerMensualidad(Long id) {
        return respuesta(mensualidades.findById(id)
                .orElseThrow(() -> new EntityNotFoundException("Mensualidad no encontrada")));
    }

    @Transactional(readOnly = true)
    public List<MensualidadResponse> listarPorInscripcion(Long inscripcionId) {
        return mensualidades.findByInscripcionIdOrderByAnioDescMesDesc(inscripcionId).stream()
                .map(this::respuesta)
                .toList();
    }

    @Transactional
    public void eliminarMensualidad(Long id) {
        Mensualidad mensualidad = mensualidades.findById(id)
                .orElseThrow(() -> new EntityNotFoundException("Mensualidad no encontrada"));
        Cargo cargo = cargos.findByMensualidadId(id)
                .orElseThrow(() -> new IllegalStateException("Mensualidad sin cargo"));
        if (saldos.calcular(cargo).aplicadoTotal().signum() > 0) {
            throw new OperacionNoPermitidaException("No puede anularse una mensualidad con pagos o crédito aplicados");
        }
        mensualidad.setEstado(EstadoOrigenCargo.ANULADA);
        cargo.setEstado(EstadoCargo.ANULADO);
    }

    @Transactional
    public List<MensualidadResponse> generarMensualidadesParaMesVigente() {
        YearMonth periodo = YearMonth.now(clock);
        List<Long> ids = inscripciones.lockActiveIdsForScheduler();
        List<Inscripcion> activas = ids.isEmpty() ? List.of() : inscripciones.findAllForScheduler(ids);
        Map<Long, Mensualidad> existentes = ids.isEmpty() ? Map.of()
                : mensualidades.findByInscripcionIdInAndAnioAndMes(
                                ids, periodo.getYear(), periodo.getMonthValue()).stream()
                        .collect(Collectors.toMap(mensualidad -> mensualidad.getInscripcion().getId(),
                                Function.identity()));
        List<MensualidadResponse> resultado = new ArrayList<>();
        for (Inscripcion inscripcion : activas) {
            Mensualidad mensualidad = existentes.get(inscripcion.getId());
            if (mensualidad == null) {
                mensualidad = generarNueva(inscripcion, periodo.getYear(), periodo.getMonthValue(), null);
            }
            else {
                exigirCargoConLiquidacion(mensualidad);
            }
            resultado.add(respuesta(mensualidad));
        }
        log.info("Mensualidades generadas período={} cantidad={}", periodo, resultado.size());
        return resultado;
    }

    private Mensualidad generar(Inscripcion inscripcion, int anio, int mes, Long recargoId) {
        if (inscripcion.getEstado() != EstadoInscripcion.ACTIVA
                || !Boolean.TRUE.equals(inscripcion.getAlumno().getActivo())) {
            throw new OperacionNoPermitidaException("La inscripción o el alumno están inactivos");
        }
        Mensualidad previa = mensualidades.findByInscripcionIdAndAnioAndMes(
                inscripcion.getId(), anio, mes).orElse(null);
        if (previa != null) {
            exigirCargoConLiquidacion(previa);
            return previa;
        }
        return generarNueva(inscripcion, anio, mes, recargoId);
    }

    private Mensualidad generarNueva(Inscripcion inscripcion, int anio, int mes, Long recargoId) {
        Recargo recargo = recargoId == null ? null
                : recargos.findById(recargoId)
                .orElseThrow(() -> new EntityNotFoundException("Recargo no encontrado"));
        YearMonth periodo = YearMonth.of(anio, mes);
        LocalDate fechaEfectiva = periodo.atDay(1);
        ResultadoLiquidacion liquidacion = liquidacionesPorVigencia.liquidarMensualidad(
                inscripcion.getId(), fechaEfectiva);

        Mensualidad mensualidad = new Mensualidad();
        mensualidad.setInscripcion(inscripcion);
        mensualidad.setBonificacion(null);
        mensualidad.setRecargo(recargo);
        mensualidad.setAnio(anio);
        mensualidad.setMes(mes);
        mensualidad.setFechaGeneracion(LocalDate.now(clock));
        mensualidad.setFechaVencimiento(periodo.atDay(Math.min(10, periodo.lengthOfMonth())));
        mensualidad.setDescripcion(inscripcion.getDisciplina().getNombre() + " " + periodo);
        mensualidad.setEstado(EstadoOrigenCargo.EMITIDA);
        mensualidades.save(mensualidad);

        Cargo cargo = cargoServicio.crearParaMensualidad(mensualidad, liquidacion.importeFinal());
        if (liquidacionesCargo.existe(cargo.getId())) {
            throw new IllegalStateException("El cargo nuevo de mensualidad ya posee una liquidación histórica");
        }
        liquidacionesCargo.registrar(cargo, liquidacion, null);
        return mensualidad;
    }

    private Cargo exigirCargoConLiquidacion(Mensualidad mensualidad) {
        Cargo cargo = cargos.findByMensualidadId(mensualidad.getId())
                .orElseThrow(() -> new IllegalStateException(
                        "Inconsistencia financiera: mensualidad sin cargo"));
        if (!liquidacionesCargo.existe(cargo.getId())) {
            throw new IllegalStateException(
                    "Inconsistencia financiera: cargo de mensualidad sin snapshot; no se recalcula con configuración actual");
        }
        return cargo;
    }

    private MensualidadResponse respuesta(Mensualidad mensualidad) {
        Cargo cargo = exigirCargoConLiquidacion(mensualidad);
        SaldoCargo saldo = saldos.calcular(cargo);
        return new MensualidadResponse(
                mensualidad.getId(),
                mensualidad.getInscripcion().getId(),
                mensualidad.getAnio(),
                mensualidad.getMes(),
                mensualidad.getFechaGeneracion(),
                mensualidad.getFechaVencimiento(),
                mensualidad.getEstado().name(),
                mensualidad.getDescripcion(),
                cargo.getId(),
                decimal(saldo.importeOriginal()),
                decimal(saldo.saldo())
        );
    }

    private static void validarBonificacionLegacy(Long bonificacionId) {
        if (bonificacionId != null) {
            throw new OperacionNoPermitidaException(
                    "bonificacionId ya no define el precio de una mensualidad; registre una condición económica con vigencia");
        }
    }

    private static String decimal(BigDecimal valor) {
        return valor.setScale(2, RoundingMode.UNNECESSARY).toPlainString();
    }
}
