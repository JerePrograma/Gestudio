package gestudio.controladores;

import gestudio.dto.inscripcion.request.InscripcionRegistroRequest;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.PositiveOrZero;
import gestudio.dto.PageResponse;
import gestudio.dto.inscripcion.response.InscripcionResponse;
import gestudio.servicios.inscripcion.InscripcionServicio;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.*;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;

import java.util.List;

@RestController
@RequestMapping("/api/inscripciones")
@Validated
public class InscripcionControlador {

    private static final Logger log = LoggerFactory.getLogger(InscripcionControlador.class);
    private final InscripcionServicio inscripcionServicio;

    public InscripcionControlador(InscripcionServicio inscripcionServicio) {
        this.inscripcionServicio = inscripcionServicio;
    }

    @PostMapping
    public ResponseEntity<InscripcionResponse> crear(@RequestBody @Validated InscripcionRegistroRequest request) {
        log.info("Creando inscripcion para alumnoId: {} en disciplinaId: {}",
                request.alumnoId(), request.disciplinaId());
        InscripcionResponse response = inscripcionServicio.crearInscripcion(request);
        return ResponseEntity.status(HttpStatus.CREATED).body(response);
    }

    @PutMapping("/{id}")
    public ResponseEntity<InscripcionResponse> actualizar(@PathVariable Long id,
                                                          @RequestBody @Validated InscripcionRegistroRequest request) {
        log.info("Actualizando inscripcion con id: {}", id);
        InscripcionResponse response = inscripcionServicio.actualizarInscripcion(id, request);
        return ResponseEntity.ok(response);
    }


    @GetMapping
    public ResponseEntity<PageResponse<InscripcionResponse>> listar(
            @RequestParam(defaultValue = "") String filtro,
            @RequestParam(defaultValue = "0") @PositiveOrZero int page,
            @RequestParam(defaultValue = "50") @Min(1) @Max(200) int size) {
        return ResponseEntity.ok(PageResponse.from(inscripcionServicio.listarInscripciones(filtro,
                PageRequest.of(page, size, Sort.by(Sort.Direction.DESC, "id")))));
    }

    @GetMapping("/{id}")
    public ResponseEntity<?> obtenerPorId(@PathVariable Long id) {
        try {
            InscripcionResponse response = inscripcionServicio.obtenerPorId(id);
            return ResponseEntity.ok(response);
        } catch (IllegalArgumentException e) {
            log.error("Error al obtener inscripcion con id {}: {}", id, e.getMessage());
            return ResponseEntity.status(HttpStatus.NOT_FOUND).body(e.getMessage());
        }
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<?> eliminar(@PathVariable Long id) {
        try {
            log.info("Eliminando inscripcion con id: {}", id);
            inscripcionServicio.eliminarInscripcion(id);
            return ResponseEntity.ok("Inscripcion eliminada exitosamente.");
        } catch (IllegalArgumentException e) {
            log.error("Error al eliminar inscripcion con id {}: {}", id, e.getMessage());
            return ResponseEntity.status(HttpStatus.NOT_FOUND).body(e.getMessage());
        }
    }

    @GetMapping("/alumno/{alumnoId}/activas")
    public ResponseEntity<List<InscripcionResponse>> obtenerInscripcionesActivas(@PathVariable Long alumnoId) {
        List<InscripcionResponse> responses = inscripcionServicio.listarPorAlumno(alumnoId);
        return ResponseEntity.ok(responses);
    }

}
