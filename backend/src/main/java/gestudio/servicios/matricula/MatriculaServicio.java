package gestudio.servicios.matricula;

import jakarta.persistence.EntityNotFoundException;
import gestudio.cuotas.application.LiquidacionCargoServicio;
import gestudio.cuotas.application.LiquidacionPorVigenciaServicio;
import gestudio.cuotas.application.ResultadoLiquidacion;
import gestudio.dto.matricula.response.MatriculaResponse;
import gestudio.entidades.Alumno;
import gestudio.entidades.Cargo;
import gestudio.entidades.EstadoCargo;
import gestudio.entidades.EstadoInscripcion;
import gestudio.entidades.EstadoOrigenCargo;
import gestudio.entidades.Inscripcion;
import gestudio.entidades.Matricula;
import gestudio.infra.errores.TratadorDeErrores.OperacionNoPermitidaException;
import gestudio.repositorios.AlumnoRepositorio;
import gestudio.repositorios.CargoRepositorio;
import gestudio.repositorios.InscripcionRepositorio;
import gestudio.repositorios.MatriculaRepositorio;
import gestudio.servicios.cargo.CargoServicio;
import gestudio.servicios.cargo.CargoSaldoServicio;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.LocalDate;
import java.time.Year;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.function.Function;
import java.util.stream.Collectors;

@Service
public class MatriculaServicio {
    private static final Logger log = LoggerFactory.getLogger(MatriculaServicio.class);
    private static final String CRITERIO_SELECCION =
            "MAX_IMPORTE_FINAL; DESEMPATE_MENOR_ID_INSCRIPCION";

    private final MatriculaRepositorio matriculas;
    private final AlumnoRepositorio alumnos;
    private final InscripcionRepositorio inscripciones;
    private final CargoRepositorio cargos;
    private final CargoServicio cargoServicio;
    private final CargoSaldoServicio saldos;
    private final LiquidacionPorVigenciaServicio liquidacionesPorVigencia;
    private final LiquidacionCargoServicio liquidacionesCargo;
    private final Clock clock;

    public MatriculaServicio(MatriculaRepositorio matriculas,
                             AlumnoRepositorio alumnos,
                             InscripcionRepositorio inscripciones,
                             CargoRepositorio cargos,
                             CargoServicio cargoServicio,
                             CargoSaldoServicio saldos,
                             LiquidacionPorVigenciaServicio liquidacionesPorVigencia,
                             LiquidacionCargoServicio liquidacionesCargo,
                             Clock clock) {
        this.matriculas = matriculas;
        this.alumnos = alumnos;
        this.inscripciones = inscripciones;
        this.cargos = cargos;
        this.cargoServicio = cargoServicio;
        this.saldos = saldos;
        this.liquidacionesPorVigencia = liquidacionesPorVigencia;
        this.liquidacionesCargo = liquidacionesCargo;
        this.clock = clock;
    }

    @Transactional
    public MatriculaResponse obtenerOMarcarPendienteMatricula(Long alumnoId, int anio) {
        Alumno alumno = alumnos.findActivoByIdForUpdate(alumnoId)
                .orElseThrow(() -> new OperacionNoPermitidaException(
                        "El alumno no existe o está inactivo"));
        Matricula existente = matriculas.findByAlumnoIdAndAnio(alumnoId, anio).orElse(null);
        if (existente != null) {
            exigirCargoConLiquidacion(existente);
            return respuesta(existente);
        }

        List<Inscripcion> activas = inscripciones.findAllByAlumno_IdAndEstado(
                alumnoId, EstadoInscripcion.ACTIVA);
        return respuesta(crear(alumno, anio, activas));
    }

    @Transactional
    public MatriculaResponse anular(Long matriculaId) {
        Matricula matricula = matriculas.findById(matriculaId)
                .orElseThrow(() -> new EntityNotFoundException("Matrícula no encontrada"));
        Cargo cargo = cargos.findByMatriculaId(matriculaId)
                .orElseThrow(() -> new IllegalStateException("Matrícula sin cargo"));
        if (saldos.calcular(cargo).aplicadoTotal().signum() > 0) {
            throw new OperacionNoPermitidaException(
                    "No puede anularse una matrícula con pagos o crédito aplicados");
        }
        matricula.setEstado(EstadoOrigenCargo.ANULADA);
        cargo.setEstado(EstadoCargo.ANULADO);
        return respuesta(matricula);
    }

    @Transactional
    public void generarMatriculasAnioVigente() {
        int anio = Year.now(clock).getValue();
        List<Long> ids = inscripciones.lockActiveIdsForScheduler();
        List<Inscripcion> activas = ids.isEmpty() ? List.of() : inscripciones.findAllForScheduler(ids);
        Map<Long, List<Inscripcion>> porAlumno = activas.stream().collect(Collectors.groupingBy(
                inscripcion -> inscripcion.getAlumno().getId(),
                LinkedHashMap::new,
                Collectors.toList()
        ));
        Map<Long, Matricula> existentes = porAlumno.isEmpty() ? Map.of()
                : matriculas.findByAlumnoIdInAndAnio(porAlumno.keySet(), anio).stream()
                .collect(Collectors.toMap(
                        matricula -> matricula.getAlumno().getId(),
                        Function.identity()
                ));

        int creadas = 0;
        for (var entry : porAlumno.entrySet()) {
            Matricula existente = existentes.get(entry.getKey());
            if (existente != null) {
                exigirCargoConLiquidacion(existente);
                continue;
            }
            crear(entry.getValue().getFirst().getAlumno(), anio, entry.getValue());
            creadas++;
        }
        log.info("Matrículas procesadas año={} alumnos={} creadas={}",
                anio, porAlumno.size(), creadas);
    }

    @Transactional(readOnly = true)
    public MatriculaResponse obtener(Long alumnoId, int anio) {
        Matricula matricula = matriculas.findByAlumnoIdAndAnio(alumnoId, anio)
                .orElseThrow(() -> new EntityNotFoundException("Matrícula no encontrada"));
        exigirCargoConLiquidacion(matricula);
        return respuesta(matricula);
    }

    private Matricula crear(Alumno alumno, int anio, List<Inscripcion> activas) {
        if (activas.isEmpty()) {
            throw new OperacionNoPermitidaException(
                    "No puede emitirse una matrícula sin inscripciones activas");
        }

        LocalDate fechaEfectiva = LocalDate.of(anio, 1, 1);
        Candidato ganador = activas.stream()
                .map(inscripcion -> new Candidato(
                        inscripcion.getId(),
                        liquidacionesPorVigencia.liquidarMatricula(
                                inscripcion.getId(), fechaEfectiva)
                ))
                .sorted(Comparator
                        .comparing((Candidato candidato) -> candidato.resultado().importeFinal())
                        .reversed()
                        .thenComparing(Candidato::inscripcionId))
                .findFirst()
                .orElseThrow();

        ResultadoLiquidacion liquidacionGanadora = conObservacionesDeSeleccion(
                ganador, activas.size());
        Matricula matricula = new Matricula();
        matricula.setAlumno(alumno);
        matricula.setAnio(anio);
        matricula.setFechaEmision(LocalDate.now(clock));
        matricula.setEstado(EstadoOrigenCargo.EMITIDA);
        matriculas.save(matricula);

        Cargo cargo = cargoServicio.crearParaMatricula(
                matricula,
                liquidacionGanadora.importeFinal(),
                LocalDate.of(anio, 1, 31)
        );
        if (liquidacionesCargo.existe(cargo.getId())) {
            throw new IllegalStateException(
                    "El cargo nuevo de matrícula ya posee una liquidación histórica");
        }
        liquidacionesCargo.registrar(cargo, liquidacionGanadora, null);
        return matricula;
    }

    private ResultadoLiquidacion conObservacionesDeSeleccion(Candidato ganador,
                                                              int cantidadCandidatas) {
        ResultadoLiquidacion resultado = ganador.resultado();
        String observaciones = "%s; selección=%s; inscripciónGanadora=%d; candidatas=%d".formatted(
                resultado.observaciones(),
                CRITERIO_SELECCION,
                ganador.inscripcionId(),
                cantidadCandidatas
        );
        return new ResultadoLiquidacion(
                resultado.fechaEfectiva(),
                resultado.tarifa(),
                resultado.condicion(),
                resultado.origen(),
                resultado.importeBase(),
                resultado.descuentoPorcentaje(),
                resultado.descuentoImporte(),
                resultado.importeFinal(),
                resultado.formulaVersion(),
                observaciones
        );
    }

    private Cargo exigirCargoConLiquidacion(Matricula matricula) {
        Cargo cargo = cargos.findByMatriculaId(matricula.getId())
                .orElseThrow(() -> new IllegalStateException(
                        "Inconsistencia financiera: matrícula sin cargo"));
        if (!liquidacionesCargo.existe(cargo.getId())) {
            throw new IllegalStateException(
                    "Inconsistencia financiera: cargo de matrícula sin snapshot; no se recalcula con configuración actual");
        }
        return cargo;
    }

    private MatriculaResponse respuesta(Matricula matricula) {
        return new MatriculaResponse(
                matricula.getId(),
                matricula.getAnio(),
                matricula.getFechaEmision(),
                matricula.getEstado().name(),
                matricula.getAlumno().getId()
        );
    }

    private record Candidato(Long inscripcionId, ResultadoLiquidacion resultado) {
    }
}
