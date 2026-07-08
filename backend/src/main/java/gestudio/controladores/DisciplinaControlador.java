package gestudio.controladores;

import com.lowagie.text.DocumentException;
import gestudio.dto.disciplina.request.DisciplinaModificacionRequest;
import gestudio.dto.disciplina.request.DisciplinaRegistroRequest;
import gestudio.dto.alumno.response.AlumnoResponse;
import gestudio.dto.disciplina.response.DisciplinaResponse;
import gestudio.dto.profesor.response.ProfesorResponse;
import jakarta.validation.Valid;
import gestudio.servicios.disciplina.DisciplinaServicio;
import gestudio.servicios.pdfs.PdfService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.*;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.*;

import java.io.IOException;
import java.time.LocalTime;
import java.util.List;

@RestController
@RequestMapping("/api/disciplinas")
@Validated
public class DisciplinaControlador {

    private static final Logger log = LoggerFactory.getLogger(DisciplinaControlador.class);
    private final DisciplinaServicio disciplinaServicio;
    private final PdfService pdfService;

    public DisciplinaControlador(DisciplinaServicio disciplinaServicio, PdfService pdfService) {
        this.disciplinaServicio = disciplinaServicio;
        this.pdfService = pdfService;
    }

    /**
     * ✅ Registrar una nueva disciplina.
     */
    @PostMapping
    public ResponseEntity<DisciplinaResponse> registrarDisciplina(@Valid @RequestBody DisciplinaRegistroRequest requestDTO) {
        log.info("Registrando disciplina: {}", requestDTO.nombre());
        DisciplinaResponse response = disciplinaServicio.crearDisciplina(requestDTO);
        return ResponseEntity.ok(response);
    }

    /**
     * ✅ Listar TODAS las disciplinas con detalles completos.
     */
    @GetMapping
    public ResponseEntity<List<DisciplinaResponse>> listarDisciplinas() {
        List<DisciplinaResponse> disciplinas = disciplinaServicio.listarDisciplinas();
        return ResponseEntity.ok(disciplinas);
    }

    /**
     * ✅ Obtener una disciplina por ID con detalles completos.
     */
    @GetMapping("/{id}")
    public ResponseEntity<DisciplinaResponse> obtenerDisciplinaPorId(@PathVariable Long id) {
        DisciplinaResponse disciplina = disciplinaServicio.obtenerDisciplinaPorId(id);
        return ResponseEntity.ok(disciplina);
    }

    /**
     * ✅ Actualizar una disciplina por ID.
     */
    @PutMapping("/{id}")
    public ResponseEntity<DisciplinaResponse> actualizarDisciplina(@PathVariable Long id,
                                                                          @Valid @RequestBody DisciplinaModificacionRequest requestDTO) {
        log.info("Actualizando disciplina con id: {}", id);
        DisciplinaResponse disciplinaActualizada = disciplinaServicio.actualizarDisciplina(id, requestDTO);
        return ResponseEntity.ok(disciplinaActualizada);
    }

    /**
     * ✅ Dar de baja (baja logica) a una disciplina.
     */
    @DeleteMapping("/dar-baja/{id}")
    public ResponseEntity<Void> darBajaDisciplina(@PathVariable Long id) {
        log.info("Dando de baja la disciplina con id: {}", id);
        disciplinaServicio.darBajaDisciplina(id);
        return ResponseEntity.noContent().build(); // 204 No Content
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> eliminarDisciplina(@PathVariable Long id) {
        log.info("Eliminando la disciplina con id: {}", id);
        disciplinaServicio.eliminarDisciplina(id);
        return ResponseEntity.noContent().build(); // 204 No Content
    }

    /**
     * ✅ Listar disciplinas activas en formato simplificado.
     */
    @GetMapping("/listado")
    public ResponseEntity<List<DisciplinaResponse>> listarDisciplinasSimplificadas() {
        List<DisciplinaResponse> disciplinas = disciplinaServicio.listarDisciplinasSimplificadas();
        return disciplinas.isEmpty() ? ResponseEntity.noContent().build() : ResponseEntity.ok(disciplinas);
    }

    /**
     * ✅ Obtener disciplinas activas segun una fecha especifica.
     */
    @GetMapping("/por-fecha")
    public ResponseEntity<List<DisciplinaResponse>> obtenerDisciplinasPorFecha(@RequestParam String fecha) {
        List<DisciplinaResponse> disciplinas = disciplinaServicio.obtenerDisciplinasPorFecha(fecha);
        return ResponseEntity.ok(disciplinas);
    }

    /**
     * ✅ Obtener alumnos de una disciplina especifica.
     */
    @GetMapping("/{disciplinaId}/alumnos")
    public ResponseEntity<List<AlumnoResponse>> obtenerAlumnosDeDisciplina(@PathVariable Long disciplinaId) {
        List<AlumnoResponse> alumnos = disciplinaServicio.obtenerAlumnosDeDisciplina(disciplinaId);
        return ResponseEntity.ok(alumnos);
    }

    /**
     * ✅ Obtener el profesor de una disciplina especifica.
     */
    @GetMapping("/{disciplinaId}/profesor")
    public ResponseEntity<ProfesorResponse> obtenerProfesorDeDisciplina(@PathVariable Long disciplinaId) {
        ProfesorResponse profesor = disciplinaServicio.obtenerProfesorDeDisciplina(disciplinaId);
        return ResponseEntity.ok(profesor);
    }

    @GetMapping("/por-horario")
    public ResponseEntity<List<DisciplinaResponse>> obtenerDisciplinasPorHorario(@RequestParam String horario) {
        LocalTime horarioInicio = LocalTime.parse(horario);
        List<DisciplinaResponse> disciplinas = disciplinaServicio.obtenerDisciplinasPorHorario(horarioInicio);
        return ResponseEntity.ok(disciplinas);
    }

    @GetMapping("/buscar")
    public ResponseEntity<List<DisciplinaResponse>> buscarPorNombre(@RequestParam("nombre") String nombre) {
        List<DisciplinaResponse> disciplinas = disciplinaServicio.buscarPorNombre(nombre);
        return ResponseEntity.ok(disciplinas);
    }

    @GetMapping("/{disciplinaId}/alumnos/pdf")
    public ResponseEntity<byte[]> descargarAlumnosPorDisciplinaPdf(
            @PathVariable Long disciplinaId) {
        try {
            byte[] pdfBytes = pdfService.generarAlumnosDisciplinaPdf(disciplinaId);
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_PDF);
            headers.setContentDisposition(
                    ContentDisposition.builder("attachment")
                            .filename("alumnos_disciplina_" + disciplinaId + ".pdf")
                            .build()
            );
            return ResponseEntity.ok()
                    .headers(headers)
                    .body(pdfBytes);
        } catch (RuntimeException e) {
            // loguear y devolver 500
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }
}
