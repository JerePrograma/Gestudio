package gestudio.servicios.profesor;

import gestudio.dto.alumno.AlumnoMapper;
import gestudio.dto.alumno.response.AlumnoResponse;
import gestudio.dto.disciplina.DisciplinaMapper;
import gestudio.dto.disciplina.response.DisciplinaResponse;
import gestudio.dto.profesor.ProfesorMapper;
import gestudio.dto.profesor.request.ProfesorModificacionRequest;
import gestudio.dto.profesor.request.ProfesorRegistroRequest;
import gestudio.dto.profesor.response.ProfesorResponse;
import gestudio.entidades.Profesor;
import gestudio.infra.errores.TratadorDeErrores.RecursoNoEncontradoException;
import gestudio.repositorios.ProfesorRepositorio;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.LocalDate;
import java.time.Period;
import java.util.List;

@Service
public class ProfesorServicio {
    private final ProfesorRepositorio profesores;
    private final ProfesorMapper mapper;
    private final DisciplinaMapper disciplinaMapper;
    private final AlumnoMapper alumnoMapper;
    private final Clock clock;

    public ProfesorServicio(ProfesorRepositorio profesores,
                            ProfesorMapper mapper,
                            DisciplinaMapper disciplinaMapper,
                            AlumnoMapper alumnoMapper,
                            Clock clock) {
        this.profesores = profesores;
        this.mapper = mapper;
        this.disciplinaMapper = disciplinaMapper;
        this.alumnoMapper = alumnoMapper;
        this.clock = clock;
    }

    @Transactional
    public ProfesorResponse registrarProfesor(ProfesorRegistroRequest request) {
        if (profesores.existsByNombreAndApellido(request.nombre(), request.apellido())) {
            throw new IllegalArgumentException("El profesor ya existe");
        }
        Profesor profesor = mapper.toEntity(request);
        return respuesta(profesores.save(profesor));
    }

    @Transactional
    public ProfesorResponse actualizarProfesor(Long id, ProfesorModificacionRequest request) {
        Profesor profesor = obtener(id);
        mapper.updateEntityFromRequest(request, profesor);
        return respuesta(profesor);
    }

    @Transactional(readOnly = true)
    public ProfesorResponse obtenerProfesorPorId(Long id) {
        return respuesta(obtener(id));
    }

    @Transactional(readOnly = true)
    public List<ProfesorResponse> listarProfesores() {
        return profesores.findAll().stream().map(this::respuesta).toList();
    }

    @Transactional(readOnly = true)
    public List<ProfesorResponse> listarProfesoresActivos() {
        return profesores.findByActivoTrue().stream().map(this::respuesta).toList();
    }

    @Transactional
    public void eliminarProfesor(Long id) {
        obtener(id).setActivo(false);
    }

    @Transactional(readOnly = true)
    public List<DisciplinaResponse> obtenerDisciplinasDeProfesor(Long profesorId) {
        obtener(profesorId);
        return profesores.findDisciplinasPorProfesor(profesorId).stream().map(disciplinaMapper::toResponse).toList();
    }

    @Transactional(readOnly = true)
    public List<ProfesorResponse> buscarPorNombre(String nombre) {
        return profesores.buscarPorNombreCompleto(nombre).stream().map(this::respuesta).toList();
    }

    @Transactional(readOnly = true)
    public List<AlumnoResponse> obtenerAlumnosDeProfesor(Long profesorId) {
        return profesores.findAlumnosPorProfesor(profesorId).stream().map(alumnoMapper::toResponse).toList();
    }

    private Profesor obtener(Long id) {
        return profesores.findById(id)
                .orElseThrow(() -> new RecursoNoEncontradoException("Profesor no encontrado"));
    }

    private ProfesorResponse respuesta(Profesor profesor) {
        return new ProfesorResponse(profesor.getId(), profesor.getNombre(), profesor.getApellido(),
                profesor.getFechaNacimiento(), edad(profesor.getFechaNacimiento()), profesor.getTelefono(),
                profesor.getActivo(), List.of());
    }

    private int edad(LocalDate nacimiento) {
        return nacimiento == null ? 0 : Period.between(nacimiento, LocalDate.now(clock)).getYears();
    }
}
