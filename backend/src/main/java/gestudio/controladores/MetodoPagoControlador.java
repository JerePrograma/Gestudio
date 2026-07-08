// src/main/java/gestudio/controladores/MetodoPagoControlador.java
package gestudio.controladores;

import gestudio.dto.metodopago.request.MetodoPagoRegistroRequest;
import gestudio.dto.metodopago.request.MetodoPagoRegistroRequest;
import gestudio.dto.metodopago.response.MetodoPagoResponse;
import gestudio.servicios.pago.MetodoPagoServicio;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/metodos-pago")
@Validated
public class MetodoPagoControlador {

    private static final Logger log = LoggerFactory.getLogger(MetodoPagoControlador.class);
    private final MetodoPagoServicio metodoPagoServicio;

    public MetodoPagoControlador(MetodoPagoServicio metodoPagoServicio) {
        this.metodoPagoServicio = metodoPagoServicio;
    }

    /**
     * Registra un nuevo metodo de pago.
     */
    @PostMapping
    public ResponseEntity<MetodoPagoResponse> registrar(@RequestBody @Validated MetodoPagoRegistroRequest request) {
        log.info("Registrando metodo de pago: {}", request.descripcion());
        MetodoPagoResponse response = metodoPagoServicio.registrar(request);
        return ResponseEntity.status(HttpStatus.CREATED).body(response);
    }

    /**
     * Lista todos los metodos de pago.
     */
    @GetMapping
    public ResponseEntity<List<MetodoPagoResponse>> listar() {
        log.info("Listando metodos de pago");
        List<MetodoPagoResponse> responses = metodoPagoServicio.listar();
        return ResponseEntity.ok(responses);
    }

    /**
     * Obtiene un metodo de pago por ID.
     */
    @GetMapping("/{id}")
    public ResponseEntity<MetodoPagoResponse> obtenerPorId(@PathVariable Long id) {
        log.info("Obteniendo metodo de pago con ID: {}", id);
        MetodoPagoResponse response = metodoPagoServicio.obtenerPorId(id);
        return ResponseEntity.ok(response);
    }

    /**
     * Actualiza un metodo de pago existente.
     */
    @PutMapping("/{id}")
    public ResponseEntity<MetodoPagoResponse> actualizar(@PathVariable Long id,
                                                         @RequestBody @Validated MetodoPagoRegistroRequest request) {
        log.info("Actualizando metodo de pago con ID: {}", id);
        MetodoPagoResponse response = metodoPagoServicio.actualizar(id, request);
        return ResponseEntity.ok(response);
    }

    /**
     * Realiza la baja logica de un metodo de pago.
     */
    @DeleteMapping("/{id}")
    public ResponseEntity<Void> eliminar(@PathVariable Long id) {
        log.info("Eliminando metodo de pago con ID: {}", id);
        metodoPagoServicio.eliminar(id);
        return ResponseEntity.noContent().build();
    }

    /**
     * Realiza la baja logica de un metodo de pago.
     */
    @DeleteMapping("/baja/{id}")
    public ResponseEntity<Void> darBaja(@PathVariable Long id) {
        log.info("Eliminando (baja logica) metodo de pago con ID: {}", id);
        metodoPagoServicio.darBaja(id);
        return ResponseEntity.noContent().build();
    }
}
