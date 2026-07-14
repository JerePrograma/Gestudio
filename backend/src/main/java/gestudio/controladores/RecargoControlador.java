package gestudio.controladores;

import jakarta.validation.Valid;
import gestudio.dto.recargo.request.RecargoRegistroRequest;
import gestudio.dto.recargo.response.RecargoResponse;
import gestudio.servicios.recargo.RecargoServicio;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/recargos")  // URL base de los recargos
public class RecargoControlador {

    private final RecargoServicio recargoServicio;

    public RecargoControlador(RecargoServicio recargoServicio) {
        this.recargoServicio = recargoServicio;
    }

    /**
     * Obtener todos los recargos
     */
    @GetMapping
    public ResponseEntity<List<RecargoResponse>> listarRecargos() {
        List<RecargoResponse> recargos = recargoServicio.listarRecargos();
        return ResponseEntity.ok(recargos);
    }

    /**
     * Obtener un recargo por su ID
     */
    @GetMapping("/{id}")
    public ResponseEntity<RecargoResponse> obtenerRecargo(@PathVariable Long id) {
        RecargoResponse recargo = recargoServicio.obtenerRecargo(id);
        return ResponseEntity.ok(recargo);
    }

    /**
     * Crear un nuevo recargo con sus detalles
     */
    @PostMapping
    public ResponseEntity<RecargoResponse> crearRecargo(@Valid @RequestBody RecargoRegistroRequest request) {
        RecargoResponse nuevoRecargo = recargoServicio.crearRecargo(request);
        return ResponseEntity.ok(nuevoRecargo);
    }

    /**
     * Actualizar un recargo existente
     */
    @PutMapping("/{id}")
    public ResponseEntity<RecargoResponse> actualizarRecargo(
            @PathVariable Long id,
            @Valid @RequestBody RecargoRegistroRequest request
    ) {
        RecargoResponse actualizado = recargoServicio.actualizarRecargo(id, request);
        return ResponseEntity.ok(actualizado);
    }

    /**
     * Eliminar un recargo por su ID
     */
    @DeleteMapping("/{id}")
    public ResponseEntity<Void> eliminarRecargo(@PathVariable Long id) {
        recargoServicio.eliminarRecargo(id);
        return ResponseEntity.noContent().build();
    }
}
