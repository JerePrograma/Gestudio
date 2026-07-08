package gestudio.controladores;

import gestudio.dto.asistencia.request.AsistenciaMensualRegistroRequest;
import gestudio.dto.asistencia.request.AsistenciaMensualModificacionRequest;
import gestudio.dto.asistencia.response.AsistenciaMensualDetalleResponse;
import gestudio.dto.asistencia.response.AsistenciaMensualListadoResponse;
import gestudio.dto.asistencia.response.AsistenciasActivasResponse;
import gestudio.servicios.asistencia.AsistenciaMensualServicio;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import jakarta.validation.Valid;

import java.util.List;
import java.util.NoSuchElementException;

@RestController
@RequestMapping("/api/asistencias-mensuales")
public class AsistenciaMensualControlador {

    private static final Logger log = LoggerFactory.getLogger(AsistenciaMensualControlador.class);
    private final AsistenciaMensualServicio asistenciaMensualServicio;

    public AsistenciaMensualControlador(AsistenciaMensualServicio asistenciaMensualServicio) {
        this.asistenciaMensualServicio = asistenciaMensualServicio;
    }

    @GetMapping
    public ResponseEntity<List<AsistenciaMensualListadoResponse>> listarPlanillas(
            @RequestParam(required = false) Long profesorId,
            @RequestParam(required = false) Long disciplinaId,
            @RequestParam(required = false) Integer mes,
            @RequestParam(required = false) Integer anio) {
        log.info("Listando planillas con filtros: profesorId={}, disciplinaId={}, mes={}, anio={}",
                profesorId, disciplinaId, mes, anio);
        List<AsistenciaMensualListadoResponse> lista =
                asistenciaMensualServicio.listarPlanillas(profesorId, disciplinaId, mes, anio);
        return ResponseEntity.ok(lista);
    }

    @PostMapping
    public ResponseEntity<AsistenciaMensualDetalleResponse> crearPlanilla(
            @Valid @RequestBody AsistenciaMensualRegistroRequest request) {
        log.info("Creando planilla para disciplinaId={} en mes={} y anio={}",
                request.disciplinaId(), request.mes(), request.anio());
        AsistenciaMensualDetalleResponse response =
                asistenciaMensualServicio.crearPlanilla(request.disciplinaId(), request.mes(), request.anio());
        return new ResponseEntity<>(response, HttpStatus.CREATED);
    }

    @PutMapping("/{id}")
    public ResponseEntity<AsistenciaMensualDetalleResponse> actualizarPlanilla(
            @PathVariable Long id, @Valid @RequestBody AsistenciaMensualModificacionRequest request) {
        log.info("Actualizando planilla con id={}", id);
        AsistenciaMensualDetalleResponse response =
                asistenciaMensualServicio.actualizarPlanillaAsistencia(id, request);
        return ResponseEntity.ok(response);
    }

    @GetMapping(value = "/por-disciplina/detalle", produces = "application/json")
    public ResponseEntity<AsistenciaMensualDetalleResponse> obtenerPlanillaPorParametros(
            @RequestParam Long disciplinaId,
            @RequestParam int mes,
            @RequestParam int anio) {
        try {
            AsistenciaMensualDetalleResponse response =
                    asistenciaMensualServicio.obtenerPlanillaPorDisciplinaYMes(disciplinaId, mes, anio);
            return ResponseEntity.ok(response);
        } catch (NoSuchElementException e) {
            return ResponseEntity.notFound().build();
        }
    }

    @PostMapping("/crear-asistencias-activos-detallado")
    public ResponseEntity<AsistenciasActivasResponse> crearAsistenciasParaInscripcionesActivasDetallado() {
        AsistenciasActivasResponse response = asistenciaMensualServicio.crearAsistenciasParaInscripcionesActivasDetallado();
        return new ResponseEntity<>(response, HttpStatus.OK);
    }

}
