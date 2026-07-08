package gestudio.servicios.matricula;

import jakarta.persistence.EntityNotFoundException;
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

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Clock;
import java.time.LocalDate;
import java.time.Year;
import java.util.List;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.function.Function;
import java.util.stream.Collectors;

@Service
public class MatriculaServicio {
    private static final Logger log = LoggerFactory.getLogger(MatriculaServicio.class);
    private final MatriculaRepositorio matriculas;
    private final AlumnoRepositorio alumnos;
    private final InscripcionRepositorio inscripciones;
    private final CargoRepositorio cargos;
    private final CargoServicio cargoServicio;
    private final CargoSaldoServicio saldos;
    private final Clock clock;

    public MatriculaServicio(MatriculaRepositorio matriculas,
                             AlumnoRepositorio alumnos,
                             InscripcionRepositorio inscripciones,
                             CargoRepositorio cargos,
                             CargoServicio cargoServicio,
                             CargoSaldoServicio saldos,
                             Clock clock) {
        this.matriculas = matriculas;
        this.alumnos = alumnos;
        this.inscripciones = inscripciones;
        this.cargos = cargos;
        this.cargoServicio = cargoServicio;
        this.saldos = saldos;
        this.clock = clock;
    }

    @Transactional
    public MatriculaResponse obtenerOMarcarPendienteMatricula(Long alumnoId, int anio) {
        Alumno alumno = alumnos.findActivoByIdForUpdate(alumnoId)
                .orElseThrow(() -> new OperacionNoPermitidaException("El alumno no existe o está inactivo"));
        Matricula matricula = matriculas.findByAlumnoIdAndAnio(alumnoId, anio).orElseGet(() -> {
            Matricula nueva = new Matricula();
            nueva.setAlumno(alumno);
            nueva.setAnio(anio);
            nueva.setFechaEmision(LocalDate.now(clock));
            nueva.setEstado(EstadoOrigenCargo.EMITIDA);
            matriculas.save(nueva);
            BigDecimal importe = inscripciones.findAllByAlumno_IdAndEstado(alumnoId, EstadoInscripcion.ACTIVA).stream()
                    .map(Inscripcion::getDisciplina)
                    .map(d -> d.getMatricula() == null ? BigDecimal.ZERO : d.getMatricula())
                    .max(BigDecimal::compareTo).orElse(BigDecimal.ZERO)
                    .setScale(2, RoundingMode.UNNECESSARY);
            cargoServicio.crearParaMatricula(nueva, importe, LocalDate.of(anio, 1, 31));
            return nueva;
        });
        return respuesta(matricula);
    }

    @Transactional
    public MatriculaResponse anular(Long matriculaId) {
        Matricula matricula = matriculas.findById(matriculaId)
                .orElseThrow(() -> new EntityNotFoundException("Matrícula no encontrada"));
        Cargo cargo = cargos.findByMatriculaId(matriculaId)
                .orElseThrow(() -> new IllegalStateException("Matrícula sin cargo"));
        if (saldos.calcular(cargo).aplicadoTotal().signum() > 0) {
            throw new OperacionNoPermitidaException("No puede anularse una matrícula con pagos o crédito aplicados");
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
                        inscripcion -> inscripcion.getAlumno().getId(), LinkedHashMap::new, Collectors.toList()));
        Map<Long, Matricula> existentes = porAlumno.isEmpty() ? Map.of()
                : matriculas.findByAlumnoIdInAndAnio(porAlumno.keySet(), anio).stream()
                        .collect(Collectors.toMap(matricula -> matricula.getAlumno().getId(), Function.identity()));
        int creadas = 0;
        for (var entry : porAlumno.entrySet()) {
            if (existentes.containsKey(entry.getKey())) continue;
            List<Inscripcion> inscripcionesAlumno = entry.getValue();
            Matricula nueva = new Matricula();
            nueva.setAlumno(inscripcionesAlumno.getFirst().getAlumno());
            nueva.setAnio(anio);
            nueva.setFechaEmision(LocalDate.now(clock));
            nueva.setEstado(EstadoOrigenCargo.EMITIDA);
            matriculas.save(nueva);
            BigDecimal importe = inscripcionesAlumno.stream().map(Inscripcion::getDisciplina)
                    .map(disciplina -> disciplina.getMatricula() == null ? BigDecimal.ZERO : disciplina.getMatricula())
                    .max(BigDecimal::compareTo).orElse(BigDecimal.ZERO).setScale(2, RoundingMode.UNNECESSARY);
            cargoServicio.crearParaMatricula(nueva, importe, LocalDate.of(anio, 1, 31));
            creadas++;
        }
        log.info("Matrículas procesadas año={} alumnos={} creadas={}", anio, porAlumno.size(), creadas);
    }

    @Transactional(readOnly = true)
    public MatriculaResponse obtener(Long alumnoId, int anio) {
        return respuesta(matriculas.findByAlumnoIdAndAnio(alumnoId, anio)
                .orElseThrow(() -> new EntityNotFoundException("Matrícula no encontrada")));
    }

    private MatriculaResponse respuesta(Matricula matricula) {
        return new MatriculaResponse(matricula.getId(), matricula.getAnio(), matricula.getFechaEmision(),
                matricula.getEstado().name(), matricula.getAlumno().getId());
    }
}
