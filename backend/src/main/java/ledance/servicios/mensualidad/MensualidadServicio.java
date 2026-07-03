package ledance.servicios.mensualidad;

import jakarta.persistence.EntityNotFoundException;
import ledance.dto.mensualidad.request.MensualidadRegistroRequest;
import ledance.dto.mensualidad.response.MensualidadResponse;
import ledance.entidades.Bonificacion;
import ledance.entidades.Cargo;
import ledance.entidades.EstadoCargo;
import ledance.entidades.EstadoInscripcion;
import ledance.entidades.EstadoOrigenCargo;
import ledance.entidades.Inscripcion;
import ledance.entidades.Mensualidad;
import ledance.entidades.Recargo;
import ledance.infra.errores.TratadorDeErrores.OperacionNoPermitidaException;
import ledance.repositorios.BonificacionRepositorio;
import ledance.repositorios.CargoRepositorio;
import ledance.repositorios.InscripcionRepositorio;
import ledance.repositorios.MensualidadRepositorio;
import ledance.repositorios.RecargoRepositorio;
import ledance.servicios.cargo.CargoServicio;
import ledance.servicios.cargo.CargoSaldoServicio;
import ledance.servicios.cargo.SaldoCargo;
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
    private static final BigDecimal CIEN = new BigDecimal("100");
    private final MensualidadRepositorio mensualidades;
    private final InscripcionRepositorio inscripciones;
    private final BonificacionRepositorio bonificaciones;
    private final RecargoRepositorio recargos;
    private final CargoRepositorio cargos;
    private final CargoServicio cargoServicio;
    private final CargoSaldoServicio saldos;
    private final Clock clock;

    public MensualidadServicio(MensualidadRepositorio mensualidades,
                               InscripcionRepositorio inscripciones,
                               BonificacionRepositorio bonificaciones,
                               RecargoRepositorio recargos,
                               CargoRepositorio cargos,
                               CargoServicio cargoServicio,
                               CargoSaldoServicio saldos,
                               Clock clock) {
        this.mensualidades = mensualidades;
        this.inscripciones = inscripciones;
        this.bonificaciones = bonificaciones;
        this.recargos = recargos;
        this.cargos = cargos;
        this.cargoServicio = cargoServicio;
        this.saldos = saldos;
        this.clock = clock;
    }

    @Transactional
    public MensualidadResponse crearMensualidad(MensualidadRegistroRequest request) {
        Inscripcion inscripcion = inscripciones.findByIdForUpdate(request.inscripcionId())
                .orElseThrow(() -> new EntityNotFoundException("Inscripción no encontrada"));
        return respuesta(generar(inscripcion, request.anio(), request.mes(), request.bonificacionId(), request.recargoId()));
    }

    @Transactional(readOnly = true)
    public MensualidadResponse obtenerMensualidad(Long id) {
        return respuesta(mensualidades.findById(id).orElseThrow(() -> new EntityNotFoundException("Mensualidad no encontrada")));
    }

    @Transactional(readOnly = true)
    public List<MensualidadResponse> listarPorInscripcion(Long inscripcionId) {
        return mensualidades.findByInscripcionIdOrderByAnioDescMesDesc(inscripcionId).stream()
                .map(this::respuesta).toList();
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
                mensualidad = generarNueva(inscripcion, periodo.getYear(), periodo.getMonthValue(), null, null);
            }
            resultado.add(respuesta(mensualidad));
        }
        log.info("Mensualidades generadas período={} cantidad={}", periodo, resultado.size());
        return resultado;
    }

    private Mensualidad generar(Inscripcion inscripcion, int anio, int mes, Long bonificacionId, Long recargoId) {
        if (inscripcion.getEstado() != EstadoInscripcion.ACTIVA || !Boolean.TRUE.equals(inscripcion.getAlumno().getActivo())) {
            throw new OperacionNoPermitidaException("La inscripción o el alumno están inactivos");
        }
        Mensualidad previa = mensualidades.findByInscripcionIdAndAnioAndMes(inscripcion.getId(), anio, mes).orElse(null);
        if (previa != null) {
            return previa;
        }
        return generarNueva(inscripcion, anio, mes, bonificacionId, recargoId);
    }

    private Mensualidad generarNueva(Inscripcion inscripcion, int anio, int mes,
                                      Long bonificacionId, Long recargoId) {
        Bonificacion bonificacion = bonificacionId == null ? inscripcion.getBonificacion()
                : bonificaciones.findById(bonificacionId).orElseThrow(() -> new EntityNotFoundException("Bonificación no encontrada"));
        Recargo recargo = recargoId == null ? null
                : recargos.findById(recargoId).orElseThrow(() -> new EntityNotFoundException("Recargo no encontrado"));
        YearMonth periodo = YearMonth.of(anio, mes);
        Mensualidad mensualidad = new Mensualidad();
        mensualidad.setInscripcion(inscripcion);
        mensualidad.setBonificacion(bonificacion);
        mensualidad.setRecargo(recargo);
        mensualidad.setAnio(anio);
        mensualidad.setMes(mes);
        mensualidad.setFechaGeneracion(LocalDate.now(clock));
        mensualidad.setFechaVencimiento(periodo.atDay(Math.min(10, periodo.lengthOfMonth())));
        mensualidad.setDescripcion(inscripcion.getDisciplina().getNombre() + " " + periodo);
        mensualidad.setEstado(EstadoOrigenCargo.EMITIDA);
        mensualidades.save(mensualidad);
        cargoServicio.crearParaMensualidad(mensualidad, importe(inscripcion, bonificacion));
        return mensualidad;
    }

    private BigDecimal importe(Inscripcion inscripcion, Bonificacion bonificacion) {
        BigDecimal base = inscripcion.getCostoParticular() == null
                ? inscripcion.getDisciplina().getValorCuota() : inscripcion.getCostoParticular();
        BigDecimal descuento = BigDecimal.ZERO;
        if (bonificacion != null) {
            descuento = base.multiply(bonificacion.getPorcentajeDescuento())
                    .divide(CIEN, 2, RoundingMode.HALF_UP)
                    .add(bonificacion.getValorFijo());
        }
        BigDecimal total = base.subtract(descuento).setScale(2, RoundingMode.HALF_UP);
        if (total.signum() < 0) {
            throw new OperacionNoPermitidaException("La bonificación supera el valor de la mensualidad");
        }
        return total;
    }

    private MensualidadResponse respuesta(Mensualidad mensualidad) {
        Cargo cargo = cargos.findByMensualidadId(mensualidad.getId()).orElse(null);
        SaldoCargo saldo = cargo == null ? null : saldos.calcular(cargo);
        return new MensualidadResponse(mensualidad.getId(), mensualidad.getInscripcion().getId(), mensualidad.getAnio(),
                mensualidad.getMes(), mensualidad.getFechaGeneracion(), mensualidad.getFechaVencimiento(),
                mensualidad.getEstado().name(), mensualidad.getDescripcion(), cargo == null ? null : cargo.getId(),
                saldo == null ? "0.00" : decimal(saldo.importeOriginal()),
                saldo == null ? "0.00" : decimal(saldo.saldo()));
    }

    private static String decimal(BigDecimal valor) {
        return valor.setScale(2, RoundingMode.UNNECESSARY).toPlainString();
    }
}
