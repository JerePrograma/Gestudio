package gestudio.controladores;

import gestudio.dto.concepto.request.SubConceptoRegistroRequest;
import gestudio.dto.concepto.response.SubConceptoResponse;
import gestudio.servicios.concepto.SubConceptoServicio;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/sub-conceptos")
@Validated
public class SubConceptoControlador {

    private static final Logger log = LoggerFactory.getLogger(SubConceptoControlador.class);
    private final SubConceptoServicio subConceptoServicio;

    public SubConceptoControlador(SubConceptoServicio subConceptoServicio) {
        this.subConceptoServicio = subConceptoServicio;
    }

    @GetMapping("/{id}")
    public ResponseEntity<SubConceptoResponse> obtenerSubConceptoPorId(@PathVariable Long id) {
        SubConceptoResponse subconcepto = subConceptoServicio.obtenerSubConceptoPorId(id);
        return ResponseEntity.ok(subconcepto);
    }

    @PostMapping
    public ResponseEntity<SubConceptoResponse> crearSubConcepto(@RequestBody @Validated SubConceptoRegistroRequest request) {
        log.info("Creando subconcepto: {}", request.descripcion());
        SubConceptoResponse nuevo = subConceptoServicio.crearSubConcepto(request);
        return ResponseEntity.ok(nuevo);
    }

    @GetMapping
    public ResponseEntity<List<SubConceptoResponse>> listarSubConceptos() {
        List<SubConceptoResponse> subconceptos = subConceptoServicio.listarSubConceptos();
        return ResponseEntity.ok(subconceptos);
    }

    @PutMapping("/{id}")
    public ResponseEntity<SubConceptoResponse> actualizarSubConcepto(@PathVariable Long id,
                                                                     @RequestBody @Validated SubConceptoRegistroRequest request) {
        SubConceptoResponse actualizado = subConceptoServicio.actualizarSubConcepto(id, request);
        return ResponseEntity.ok(actualizado);
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> eliminarSubConcepto(@PathVariable Long id) {
        subConceptoServicio.eliminarSubConcepto(id);
        return ResponseEntity.noContent().build();
    }

    // Endpoint para busqueda de subconceptos por nombre (para sugerencias)
    @GetMapping("/buscar")
    public ResponseEntity<List<SubConceptoResponse>> buscarPorNombre(@RequestParam String nombre) {
        List<SubConceptoResponse> resultado = subConceptoServicio.buscarPorNombre(nombre);
        return ResponseEntity.ok(resultado);
    }

}
