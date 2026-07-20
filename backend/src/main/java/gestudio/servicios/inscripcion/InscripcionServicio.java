package gestudio.servicios.inscripcion;

import jakarta.persistence.EntityNotFoundException;
import gestudio.dto.inscripcion.request.InscripcionRegistroRequest;
import gestudio.dto.inscripcion.response.InscripcionResponse;
import gestudio.dto.mensualidad.request.MensualidadRegistroRequest;
import gestudio.entidades.Alumno;
import gestudio.entidades.Disciplina;
import gestudio.entidades.EstadoInscripcion;
import gestudio.entidades.Inscripcion;
import gestudio.infra.errores.TratadorDeErrores.OperacionNoPermitidaException;
import gestudio.repositorios.AlumnoRepositorio;
import gestudio.repositorios.DisciplinaRepositorio;
import gestudio.repositorios.InscripcionRepositorio;
import gestudio.servicios.matricula.MatriculaServicio;
import gestudio.servicios.mensualidad.MensualidadServicio;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

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
    private final MensualidadServicio mensualidades;
    private final MatriculaServicio matriculas;
    private final Clock clock;

    public InscripcionServicio(InscripcionRepositorio inscripciones,
                               AlumnoRepositorio alumnos,
                               DisciplinaRepositorio disciplinas,
                               MensualidadServicio mensualidades,
                               MatriculaServicio matriculas,
                               Clock clock) {
        this.inscripciones = inscripciones;
        this.alumnos = alumnos;
        this.disciplinas = disciplinas;
        this.mensualidades = mensualidades;
        this.matriculas = matriculas;
        this.clock = clock;
    }

    @Transactional
    public InscripcionResponse crearInscripcion(InscripcionRegistroRequest request) {
        validarFuentesLegacy(request);
        Alumno alumno = alumnos.findActivoByIdForUpdate(request.alumnoId())
                .orElseThrow(() -> new OperacionNoPermitidaException(
                        "El alumno no existe o está inactivo"));
        Disciplina disciplina = disciplinas.findById(request.disciplinaId())
                .filter(d -> Boolean.TRUE.equals(d.getActivo()))
                .orElseThrow(() -> new OperacionNoPermitidaException(
                        "La disciplina no existe o está inactiva"));
        if (inscripciones.findByAlumnoIdAndDisciplinaIdAndEstado(
                alumno.getId(), disciplina.getId(), EstadoInscripcion.ACTIVA).isPresent()) {
            throw new OperacionNoPermitidaException(
                    "El alumno ya posee una inscripción activa en la disciplina");
        }

        Inscripcion inscripcion = new Inscripcion();
        inscripcion.setAlumno(alumno);
        inscripcion.setDisciplina(disciplina);
        inscripcion.setBonificacion(null);
        inscripcion.setCostoParticular(null);
        inscripcion.setFechaInscripcion(request.fechaInscripcion() == null
                ? LocalDate.now(clock)
                : request.fechaInscripcion());
        inscripcion.setEstado(EstadoInscripcion.ACTIVA);
        inscripciones.save(inscripcion);

        YearMonth periodo = YearMonth.now(clock);
        mensualidades.crearMensualidad(new MensualidadRegistroRequest(
                inscripcion.getId(),
                periodo.getYear(),
                periodo.getMonthValue(),
                null,
                null
        ));
        matriculas.obtenerOMarcarPendienteMatricula(alumno.getId(), periodo.getYear());
        log.info("Inscripción creada id={} alumnoId={} disciplinaId={}",
                inscripcion.getId(), alumno.getId(), disciplina.getId());
        return respuesta(inscripcion);
    }

    @Transactional
    public InscripcionResponse actualizarInscripcion(Long id, InscripcionRegistroRequest request) {
        validarFuentesLegacy(request);
        Inscripcion inscripcion = inscripciones.findByIdForUpdate(id)
                .orElseThrow(() -> new EntityNotFoundException("Inscripción no encontrada"));
        if (!inscripcion.getAlumno().getId().equals(request.alumnoId())
                || !inscripcion.getDisciplina().getId().equals(request.disciplinaId())) {
            throw new OperacionNoPermitidaException(
                    "Alumno y disciplina no pueden cambiarse; cree otra inscripción");
        }
        return respuesta(inscripcion);
    }

    @Transactional(readOnly = true)
    public Page<InscripcionResponse> listarInscripciones(String filtro, Pageable pageable) {
        return inscripciones.findAllWithDetails(
                filtro == null ? "" : filtro.trim(), pageable).map(this::respuesta);
    }

    @Transactional(readOnly = true)
    public InscripcionResponse obtenerPorId(Long id) {
        return respuesta(inscripciones.findById(id)
                .orElseThrow(() -> new EntityNotFoundException("Inscripción no encontrada")));
    }

    @Transactional(readOnly = true)
    public List<InscripcionResponse> listarPorAlumno(Long alumnoId) {
        return inscripciones.findAllByAlumno_IdAndEstado(
                        alumnoId, EstadoInscripcion.ACTIVA).stream()
                .map(this::respuesta)
                .toList();
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

    private InscripcionResponse respuesta(Inscripcion inscripcion) {
        String alumno = (inscripcion.getAlumno().getNombre() + " "
                + inscripcion.getAlumno().getApellido()).trim();
        return new InscripcionResponse(
                inscripcion.getId(),
                inscripcion.getAlumno().getId(),
                alumno,
                inscripcion.getDisciplina().getId(),
                inscripcion.getDisciplina().getNombre(),
                inscripcion.getBonificacion() == null
                        ? null
                        : inscripcion.getBonificacion().getId(),
                inscripcion.getFechaInscripcion(),
                inscripcion.getFechaBaja(),
                inscripcion.getEstado().name(),
                inscripcion.getCostoParticular() == null
                        ? null
                        : inscripcion.getCostoParticular().toPlainString()
        );
    }

    private static void validarFuentesLegacy(InscripcionRegistroRequest request) {
        if (request.bonificacionId() != null) {
            throw new OperacionNoPermitidaException(
                    "bonificacionId ya no puede editarse desde la inscripción; registre una condición económica con vigencia");
        }
        if (request.costoParticular() != null) {
            throw new OperacionNoPermitidaException(
                    "costoParticular ya no puede editarse desde la inscripción; registre una condición económica con vigencia");
        }
    }
}
