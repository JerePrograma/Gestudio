package gestudio.controladores;

import jakarta.validation.Valid;
import gestudio.dto.mensualidad.request.MensualidadRegistroRequest;
import gestudio.dto.mensualidad.response.MensualidadResponse;
import gestudio.servicios.mensualidad.MensualidadServicio;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/mensualidades")
public class MensualidadControlador {

    private final MensualidadServicio mensualidadServicio;

    public MensualidadControlador(MensualidadServicio mensualidadServicio) {
        this.mensualidadServicio = mensualidadServicio;
    }

    @PostMapping
    public ResponseEntity<MensualidadResponse> crearMensualidad(@Valid @RequestBody MensualidadRegistroRequest request) {
        MensualidadResponse response = mensualidadServicio.crearMensualidad(request);
        return ResponseEntity.ok(response);
    }

    @GetMapping("/{id}")
    public ResponseEntity<MensualidadResponse> obtenerMensualidad(@PathVariable Long id) {
        MensualidadResponse response = mensualidadServicio.obtenerMensualidad(id);
        return ResponseEntity.ok(response);
    }

    @GetMapping("/inscripcion/{inscripcionId}")
    public ResponseEntity<List<MensualidadResponse>> listarPorInscripcion(@PathVariable Long inscripcionId) {
        List<MensualidadResponse> respuestas = mensualidadServicio.listarPorInscripcion(inscripcionId);
        return ResponseEntity.ok(respuestas);
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> eliminarMensualidad(@PathVariable Long id) {
        mensualidadServicio.eliminarMensualidad(id);
        return ResponseEntity.noContent().build();
    }

    @PostMapping("/generar-mensualidades")
    public ResponseEntity<List<MensualidadResponse>> generarMensualidadesParaMesVigente() {
        List<MensualidadResponse> respuestas = mensualidadServicio.generarMensualidadesParaMesVigente();
        return ResponseEntity.status(HttpStatus.CREATED).body(respuestas);
    }
}
