package gestudio.controladores;

import gestudio.dto.bonificacion.request.BonificacionModificacionRequest;
import gestudio.dto.bonificacion.request.BonificacionRegistroRequest;
import gestudio.dto.bonificacion.response.BonificacionResponse;
import gestudio.servicios.bonificacion.BonificacionServicio;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/bonificaciones")
@Validated
public class BonificacionControlador {

    private static final Logger log = LoggerFactory.getLogger(BonificacionControlador.class);
    private final BonificacionServicio bonificacionService;

    public BonificacionControlador(BonificacionServicio bonificacionService) {
        this.bonificacionService = bonificacionService;
    }

    @PostMapping
    public ResponseEntity<BonificacionResponse> crearBonificacion(@RequestBody @Validated BonificacionRegistroRequest requestDTO) {
        log.info("Creando bonificacion: {}", requestDTO.descripcion());
        return ResponseEntity.ok(bonificacionService.crearBonificacion(requestDTO));
    }

    @GetMapping
    public ResponseEntity<List<BonificacionResponse>> listarBonificaciones() {
        return ResponseEntity.ok(bonificacionService.listarBonificaciones());
    }

    @GetMapping("/{id}")
    public ResponseEntity<BonificacionResponse> obtenerBonificacionPorId(@PathVariable Long id) {
        return ResponseEntity.ok(bonificacionService.obtenerBonificacionPorId(id));
    }

    @PutMapping("/{id}")
    public ResponseEntity<BonificacionResponse> actualizarBonificacion(@PathVariable Long id,
                                                                       @RequestBody @Validated BonificacionModificacionRequest requestDTO) {
        return ResponseEntity.ok(bonificacionService.actualizarBonificacion(id, requestDTO));
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> eliminarBonificacion(@PathVariable Long id) {
        bonificacionService.eliminarBonificacion(id);
        return ResponseEntity.noContent().build();
    }
}
