package gestudio.servicios.inscripcion;

import jakarta.persistence.EntityNotFoundException;
import gestudio.dto.inscripcion.request.InscripcionRegistroRequest;
import gestudio.dto.inscripcion.response.InscripcionResponse;
import gestudio.entidades.Alumno;
import gestudio.entidades.Bonificacion;
import gestudio.entidades.Disciplina;
import gestudio.entidades.EstadoInscripcion;
import gestudio.entidades.Inscripcion;
import gestudio.infra.errores.TratadorDeErrores.OperacionNoPermitidaException;
import gestudio.repositorios.AlumnoRepositorio;
import gestudio.repositorios.BonificacionRepositorio;
import gestudio.repositorios.DisciplinaRepositorio;
import gestudio.repositorios.InscripcionRepositorio;
import gestudio.servicios.matricula.MatriculaServicio;
import gestudio.servicios.mensualidad.MensualidadServicio;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Clock;
import java.time.LocalDate;
import java.time.YearMonth;
import java.util.List;

@Service
public class InscripcionServicio {
    private static final Logger log = LoggerFactory.getLogger(InscripcionServicio.class);
    private final InscripcionRepositorio inscripciones;
    private final AlumnoRepositorio alumnos;
    private final DisciplinaRepositorio disciplinas;
    private final BonificacionRepositorio bonificaciones;
    private final MensualidadServicio mensualidades;
    private final MatriculaServicio matriculas;
    private final Clock clock;

    public InscripcionServicio(InscripcionRepositorio inscripciones,
                               AlumnoRepositorio alumnos,
                               DisciplinaRepositorio disciplinas,
                               BonificacionRepositorio bonificaciones,
                               MensualidadServicio mensualidades,
                               MatriculaServicio matriculas,
                               Clock clock) {
        this.inscripciones = inscripciones;
        this.alumnos = alumnos;
        this.disciplinas = disciplinas;
        this.bonificaciones = bonificaciones;
        this.mensualidades = mensualidades;
        this.matriculas = matriculas;
        this.clock = clock;
    }

    @Transactional
    public InscripcionResponse crearInscripcion(InscripcionRegistroRequest request) {
        Alumno alumno = alumnos.findActivoByIdForUpdate(request.alumnoId())
                .orElseThrow(() -> new OperacionNoPermitidaException("El alumno no existe o está inactivo"));
        Disciplina disciplina = disciplinas.findById(request.disciplinaId())
                .filter(d -> Boolean.TRUE.equals(d.getActivo()))
                .orElseThrow(() -> new OperacionNoPermitidaException("La disciplina no existe o está inactiva"));
        if (inscripciones.findByAlumnoIdAndDisciplinaIdAndEstado(
                alumno.getId(), disciplina.getId(), EstadoInscripcion.ACTIVA).isPresent()) {
            throw new OperacionNoPermitidaException("El alumno ya posee una inscripción activa en la disciplina");
        }
        Bonificacion bonificacion = request.bonificacionId() == null ? null
                : bonificaciones.findById(request.bonificacionId())
                .filter(b -> Boolean.TRUE.equals(b.getActivo()))
                .orElseThrow(() -> new OperacionNoPermitidaException("La bonificación no existe o está inactiva"));
        Inscripcion inscripcion = new Inscripcion();
        inscripcion.setAlumno(alumno);
        inscripcion.setDisciplina(disciplina);
        inscripcion.setBonificacion(bonificacion);
        inscripcion.setFechaInscripcion(request.fechaInscripcion() == null ? LocalDate.now(clock) : request.fechaInscripcion());
        inscripcion.setEstado(EstadoInscripcion.ACTIVA);
        inscripcion.setCostoParticular(monedaOpcional(request.costoParticular()));
        inscripciones.save(inscripcion);

        YearMonth periodo = YearMonth.now(clock);
        mensualidades.crearMensualidad(new gestudio.dto.mensualidad.request.MensualidadRegistroRequest(
                inscripcion.getId(), periodo.getYear(), periodo.getMonthValue(), null, request.bonificacionId()));
        matriculas.obtenerOMarcarPendienteMatricula(alumno.getId(), periodo.getYear());
        log.info("Inscripción creada id={} alumnoId={} disciplinaId={}", inscripcion.getId(), alumno.getId(), disciplina.getId());
        return respuesta(inscripcion);
    }

    @Transactional
    public InscripcionResponse actualizarInscripcion(Long id, InscripcionRegistroRequest request) {
        Inscripcion inscripcion = inscripciones.findByIdForUpdate(id)
                .orElseThrow(() -> new EntityNotFoundException("Inscripción no encontrada"));
        if (!inscripcion.getAlumno().getId().equals(request.alumnoId())
                || !inscripcion.getDisciplina().getId().equals(request.disciplinaId())) {
            throw new OperacionNoPermitidaException("Alumno y disciplina no pueden cambiarse; cree otra inscripción");
        }
        inscripcion.setBonificacion(request.bonificacionId() == null ? null
                : bonificaciones.findById(request.bonificacionId()).orElseThrow());
        inscripcion.setCostoParticular(monedaOpcional(request.costoParticular()));
        return respuesta(inscripcion);
    }

    @Transactional(readOnly = true)
    public Page<InscripcionResponse> listarInscripciones(String filtro, Pageable pageable) {
        return inscripciones.findAllWithDetails(filtro == null ? "" : filtro.trim(), pageable).map(this::respuesta);
    }

    @Transactional(readOnly = true)
    public InscripcionResponse obtenerPorId(Long id) {
        return respuesta(inscripciones.findById(id).orElseThrow(() -> new EntityNotFoundException("Inscripción no encontrada")));
    }

    @Transactional(readOnly = true)
    public List<InscripcionResponse> listarPorAlumno(Long alumnoId) {
        return inscripciones.findAllByAlumno_IdAndEstado(alumnoId, EstadoInscripcion.ACTIVA).stream()
                .map(this::respuesta).toList();
    }

    @Transactional
    public void eliminarInscripcion(Long id) {
        Inscripcion inscripcion = inscripciones.findByIdForUpdate(id)
                .orElseThrow(() -> new EntityNotFoundException("Inscripción no encontrada"));
        if (inscripcion.getEstado() == EstadoInscripcion.ACTIVA) {
            inscripcion.setEstado(EstadoInscripcion.INACTIVA);
            inscripcion.setFechaBaja(LocalDate.now(clock));
        }
    }

    private InscripcionResponse respuesta(Inscripcion i) {
        String alumno = (i.getAlumno().getNombre() + " " + i.getAlumno().getApellido()).trim();
        return new InscripcionResponse(i.getId(), i.getAlumno().getId(), alumno, i.getDisciplina().getId(),
                i.getDisciplina().getNombre(), i.getBonificacion() == null ? null : i.getBonificacion().getId(),
                i.getFechaInscripcion(), i.getFechaBaja(), i.getEstado().name(),
                i.getCostoParticular() == null ? null : i.getCostoParticular().toPlainString());
    }

    private static BigDecimal monedaOpcional(BigDecimal valor) {
        if (valor == null) {
            return null;
        }
        BigDecimal normalizado = valor.setScale(2, RoundingMode.UNNECESSARY);
        if (normalizado.signum() < 0) {
            throw new IllegalArgumentException("El costo particular no puede ser negativo");
        }
        return normalizado;
    }
}
