package gestudio.servicios.alumno;

import jakarta.persistence.EntityNotFoundException;
import gestudio.dto.alumno.AlumnoMapper;
import gestudio.dto.alumno.request.AlumnoRegistroRequest;
import gestudio.dto.alumno.response.AlumnoResponse;
import gestudio.dto.disciplina.DisciplinaMapper;
import gestudio.dto.disciplina.response.DisciplinaResponse;
import gestudio.entidades.Alumno;
import gestudio.entidades.EstadoInscripcion;
import gestudio.repositorios.AlumnoRepositorio;
import gestudio.repositorios.InscripcionRepositorio;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;

import java.time.Clock;
import java.time.LocalDate;
import java.time.Period;
import java.util.List;

@Service
public class AlumnoServicio {
    private static final Logger log = LoggerFactory.getLogger(AlumnoServicio.class);

    private final AlumnoRepositorio alumnos;
    private final InscripcionRepositorio inscripciones;
    private final AlumnoMapper mapper;
    private final DisciplinaMapper disciplinaMapper;
    private final Clock clock;

    public AlumnoServicio(AlumnoRepositorio alumnos,
                          InscripcionRepositorio inscripciones,
                          AlumnoMapper mapper,
                          DisciplinaMapper disciplinaMapper,
                          Clock clock) {
        this.alumnos = alumnos;
        this.inscripciones = inscripciones;
        this.mapper = mapper;
        this.disciplinaMapper = disciplinaMapper;
        this.clock = clock;
    }

    @Transactional
    public AlumnoResponse registrarAlumno(AlumnoRegistroRequest request) {
        if (alumnos.existsByNombreIgnoreCaseAndApellidoIgnoreCase(request.nombre().trim(), request.apellido().trim())) {
            throw new IllegalStateException("Ya existe un alumno con ese nombre y apellido");
        }
        Alumno alumno = mapper.toEntity(request);
        alumno.setId(null);
        alumno.setFechaIncorporacion(request.fechaIncorporacion() == null
                ? LocalDate.now(clock) : request.fechaIncorporacion());
        alumno = alumnos.save(alumno);
        log.info("Alumno registrado id={}", alumno.getId());
        return respuesta(alumno);
    }

    @Transactional(readOnly = true)
    public AlumnoResponse obtenerAlumnoPorId(Long id) {
        return respuesta(activo(id));
    }

    @Transactional(readOnly = true)
    public Page<AlumnoResponse> listarAlumnos(Pageable pageable) {
        return alumnos.findAll(pageable).map(this::respuesta);
    }

    @Transactional
    public AlumnoResponse actualizarAlumno(Long id, AlumnoRegistroRequest request) {
        Alumno alumno = activo(id);
        mapper.updateEntityFromRequest(request, alumno);
        return respuesta(alumno);
    }

    @Transactional
    public void darBajaAlumno(Long id) {
        Alumno alumno = alumnos.findById(id).orElseThrow(() -> new EntityNotFoundException("Alumno no encontrado"));
        if (Boolean.TRUE.equals(alumno.getActivo())) {
            alumno.setActivo(false);
            alumno.setFechaDeBaja(LocalDate.now(clock));
            log.info("Alumno dado de baja id={}", id);
        }
    }

    @Transactional(readOnly = true)
    public Page<AlumnoResponse> buscarPorNombre(String nombre, Pageable pageable) {
        return alumnos.buscarPorNombreCompleto(nombre, pageable).map(this::respuesta);
    }

    @Transactional(readOnly = true)
    public List<DisciplinaResponse> obtenerDisciplinasDeAlumno(Long alumnoId) {
        activo(alumnoId);
        return inscripciones.findAllByAlumno_IdAndEstado(alumnoId, EstadoInscripcion.ACTIVA).stream()
                .map(i -> disciplinaMapper.toResponse(i.getDisciplina())).toList();
    }

    private Alumno activo(Long id) {
        return alumnos.findByIdAndActivoTrue(id)
                .orElseThrow(() -> new EntityNotFoundException("Alumno no encontrado"));
    }

    private AlumnoResponse respuesta(Alumno alumno) {
        AlumnoResponse base = mapper.toResponse(alumno);
        return new AlumnoResponse(base.id(), base.nombre(), base.apellido(), base.fechaNacimiento(),
                base.fechaIncorporacion(), edad(base.fechaNacimiento()), base.celular1(), base.celular2(),
                base.email(), base.documento(), base.fechaDeBaja(), base.nombrePadres(),
                base.autorizadoParaSalirSolo(), base.activo(), base.otrasNotas(), List.of());
    }

    private int edad(LocalDate nacimiento) {
        return nacimiento == null ? 0 : Period.between(nacimiento, LocalDate.now(clock)).getYears();
    }
}
