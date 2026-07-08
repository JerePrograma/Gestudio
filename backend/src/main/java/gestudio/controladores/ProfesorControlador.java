package gestudio.controladores;

import gestudio.dto.alumno.response.AlumnoResponse;
import gestudio.dto.profesor.request.ProfesorModificacionRequest;
import gestudio.dto.profesor.request.ProfesorRegistroRequest;
import gestudio.dto.disciplina.response.DisciplinaResponse;
import gestudio.dto.profesor.response.ProfesorResponse;
import gestudio.dto.profesor.response.ProfesorResponse;
import gestudio.servicios.profesor.ProfesorServicio;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/profesores")
@Validated
public class ProfesorControlador {

    private static final Logger log = LoggerFactory.getLogger(ProfesorControlador.class);
    private final ProfesorServicio profesorServicio;

    public ProfesorControlador(ProfesorServicio profesorServicio) {
        this.profesorServicio = profesorServicio;
    }

    /**
     * ✅ Registrar un nuevo profesor.
     */
    @PostMapping
    public ResponseEntity<ProfesorResponse> registrarProfesor(@RequestBody @Validated ProfesorRegistroRequest request) {
        log.info("Registrando profesor: {} {}", request.nombre(), request.apellido());
        ProfesorResponse response = profesorServicio.registrarProfesor(request);
        return ResponseEntity.ok(response);
    }

    /**
     * ✅ Obtener un profesor por ID.
     */
    @GetMapping("/{id}")
    public ResponseEntity<ProfesorResponse> obtenerProfesorPorId(@PathVariable Long id) {
        ProfesorResponse response = profesorServicio.obtenerProfesorPorId(id);
        return ResponseEntity.ok(response);
    }

    /**
     * ✅ Listar todos los profesores.
     */
    @GetMapping
    public ResponseEntity<List<ProfesorResponse>> listarProfesores() {
        List<ProfesorResponse> profesores = profesorServicio.listarProfesores();
        return ResponseEntity.ok(profesores);
    }

    /**
     * ✅ Listar profesores activos.
     */
    @GetMapping("/activos")
    public ResponseEntity<List<ProfesorResponse>> listarProfesoresActivos() {
        List<ProfesorResponse> profesores = profesorServicio.listarProfesoresActivos();
        return ResponseEntity.ok(profesores);
    }

    /**
     * ✅ Actualizar un profesor.
     */
    @PutMapping("/{id}")
    public ResponseEntity<ProfesorResponse> actualizarProfesor(@PathVariable Long id,
                                                               @RequestBody @Validated ProfesorModificacionRequest request) {
        log.info("Actualizando profesor con id: {}", id);
        ProfesorResponse response = profesorServicio.actualizarProfesor(id, request);
        return ResponseEntity.ok(response);
    }

    /**
     * ✅ Eliminar un profesor (baja logica).
     */
    @DeleteMapping("/{id}")
    public ResponseEntity<Void> eliminarProfesor(@PathVariable Long id) {
        log.info("Eliminando profesor con id: {}", id);
        profesorServicio.eliminarProfesor(id);
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/{profesorId}/disciplinas")
    public ResponseEntity<List<DisciplinaResponse>> obtenerDisciplinasDeProfesor(@PathVariable Long profesorId) {
        List<DisciplinaResponse> disciplinas = profesorServicio.obtenerDisciplinasDeProfesor(profesorId);
        return ResponseEntity.ok(disciplinas);
    }

    @GetMapping("/buscar")
    public ResponseEntity<List<ProfesorResponse>> buscarPorNombre(@RequestParam String nombre) {
        List<ProfesorResponse> resultado = profesorServicio.buscarPorNombre(nombre);
        return ResponseEntity.ok(resultado);
    }

    /**
     * GET /api/profesores/{profesorId}/alumnos
     * Devuelve todos los alumnos de las disciplinas que dicta ese profesor.
     */
    @GetMapping("/{profesorId}/alumnos")
    public ResponseEntity<List<AlumnoResponse>> listarAlumnosPorProfesor(@PathVariable Long profesorId) {
        List<AlumnoResponse> lista = profesorServicio.obtenerAlumnosDeProfesor(profesorId);
        return lista.isEmpty()
                ? ResponseEntity.noContent().build()
                : ResponseEntity.ok(lista);
    }
}
