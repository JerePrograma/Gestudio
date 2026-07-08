package gestudio.controladores;

import gestudio.dto.asistencia.request.AsistenciaDiariaRegistroRequest;
import gestudio.dto.asistencia.request.AsistenciaDiariaModificacionRequest;
import gestudio.dto.asistencia.response.AsistenciaDiariaDetalleResponse;
import gestudio.servicios.asistencia.AsistenciaDiariaServicio;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import jakarta.validation.Valid;

import java.time.LocalDate;
import java.util.List;

@RestController
@RequestMapping("/api/asistencias-diarias")
public class AsistenciaDiariaControlador {

    private static final Logger log = LoggerFactory.getLogger(AsistenciaDiariaControlador.class);
    private final AsistenciaDiariaServicio asistenciaDiariaServicio;

    public AsistenciaDiariaControlador(AsistenciaDiariaServicio asistenciaDiariaServicio) {
        this.asistenciaDiariaServicio = asistenciaDiariaServicio;
    }

    @PutMapping("/registrar")
    public ResponseEntity<AsistenciaDiariaDetalleResponse> registrarAsistencia(
            @Valid @RequestBody AsistenciaDiariaRegistroRequest request) {
        log.info("Registrando asistencia para alumnoId={} en fecha={}", request.id(), request.fecha());
        return ResponseEntity.ok(asistenciaDiariaServicio.registrarOActualizarAsistencia(request));
    }

    @PutMapping("/{id}")
    public ResponseEntity<AsistenciaDiariaDetalleResponse> modificarAsistencia(
            @PathVariable Long id, @Valid @RequestBody AsistenciaDiariaModificacionRequest request) {
        log.info("Modificando asistencia con id={} para fecha={}", id, request.fecha());
        return ResponseEntity.ok(asistenciaDiariaServicio.actualizarAsistencia(id, request));
    }

    @GetMapping("/por-asistencia-mensual/{asistenciaMensualId}")
    public ResponseEntity<List<AsistenciaDiariaDetalleResponse>> obtenerAsistenciasPorAsistenciaMensual(
            @PathVariable Long asistenciaMensualId) {
        log.info("Obteniendo asistencias diarias para asistenciaMensualId={}", asistenciaMensualId);
        return ResponseEntity.ok(asistenciaDiariaServicio.obtenerAsistenciasPorAsistenciaMensual(asistenciaMensualId));
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> eliminarAsistencia(@PathVariable Long id) {
        log.warn("Eliminando asistencia con id={}", id);
        asistenciaDiariaServicio.eliminarAsistencia(id);
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/por-disciplina-y-fecha")
    public ResponseEntity<Page<AsistenciaDiariaDetalleResponse>> obtenerAsistenciasPorDisciplinaYFecha(
            @RequestParam Long disciplinaId, @RequestParam String fecha, Pageable pageable) {
        LocalDate fechaParsed = LocalDate.parse(fecha);
        log.info("Obteniendo asistencias para disciplinaId={} en fecha={}", disciplinaId, fechaParsed);
        return ResponseEntity.ok(asistenciaDiariaServicio.obtenerAsistenciasPorDisciplinaYFecha(disciplinaId, fechaParsed, pageable));
    }

}
