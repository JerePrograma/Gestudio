package gestudio.controladores;

import gestudio.dto.concepto.ConceptoMapper;
import gestudio.dto.concepto.request.ConceptoRegistroRequest;
import gestudio.dto.concepto.response.ConceptoResponse;
import gestudio.entidades.Concepto;
import gestudio.entidades.SubConcepto;
import gestudio.repositorios.ConceptoRepositorio;
import gestudio.servicios.concepto.ConceptoServicio;
import gestudio.servicios.concepto.SubConceptoServicio;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/api/conceptos")
@Validated
public class ConceptoControlador {

    private static final Logger log = LoggerFactory.getLogger(ConceptoControlador.class);
    private final ConceptoServicio conceptoServicio;
    private final SubConceptoServicio subConceptoServicio;
    private final ConceptoRepositorio conceptoRepositorio;
    private final ConceptoMapper conceptoMapper;

    public ConceptoControlador(ConceptoServicio conceptoServicio, SubConceptoServicio subConceptoServicio, ConceptoRepositorio conceptoRepositorio, ConceptoMapper conceptoMapper) {
        this.conceptoServicio = conceptoServicio;
        this.subConceptoServicio = subConceptoServicio;
        this.conceptoRepositorio = conceptoRepositorio;
        this.conceptoMapper = conceptoMapper;
    }

    @PostMapping
    public ResponseEntity<ConceptoResponse> crearConcepto(@RequestBody @Validated ConceptoRegistroRequest request) {
        log.info("Creando concepto: {}", request.descripcion());
        ConceptoResponse nuevo = conceptoServicio.crearConcepto(request);
        return ResponseEntity.ok(nuevo);
    }

    @GetMapping
    public ResponseEntity<List<ConceptoResponse>> listarConceptos() {
        List<ConceptoResponse> conceptos = conceptoServicio.listarConceptos();
        return ResponseEntity.ok(conceptos);
    }

    @GetMapping("/{id}")
    public ResponseEntity<ConceptoResponse> obtenerConceptoPorId(@PathVariable Long id) {
        ConceptoResponse concepto = conceptoServicio.obtenerConceptoPorId(id);
        return ResponseEntity.ok(concepto);
    }

    @PutMapping("/{id}")
    public ResponseEntity<ConceptoResponse> actualizarConcepto(@PathVariable Long id,
                                                               @RequestBody @Validated ConceptoRegistroRequest request) {
        ConceptoResponse actualizado = conceptoServicio.actualizarConcepto(id, request);
        return ResponseEntity.ok(actualizado);
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> eliminarConcepto(@PathVariable Long id) {
        conceptoServicio.eliminarConcepto(id);
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/sub-concepto/{subConceptoSelector}")
    public ResponseEntity<List<ConceptoResponse>> listarConceptosPorSubConcepto(
            @PathVariable String subConceptoSelector) {

        Long subConceptoId = resolverSubConceptoId(subConceptoSelector);
        if (subConceptoId == null) {
            return ResponseEntity.notFound().build();
        }

        List<Concepto> conceptos = conceptoRepositorio.findBySubConceptoId(subConceptoId);
        List<ConceptoResponse> responses = conceptos.stream()
                .map(conceptoMapper::toResponse)
                .collect(Collectors.toList());
        return ResponseEntity.ok(responses);
    }

    private Long resolverSubConceptoId(String selector) {
        try {
            Long id = Long.valueOf(selector);
            try {
                var subConceptoPorId = subConceptoServicio.obtenerSubConceptoPorId(id);
                if (subConceptoPorId != null) {
                    return subConceptoPorId.id();
                }
            } catch (IllegalArgumentException inexistentePorId) {
                // Conserva compatibilidad con descripciones numéricas.
            }
        } catch (NumberFormatException noEsId) {
            // La ruta legacy selecciona por descripción.
        }

        SubConcepto subConcepto = subConceptoServicio.findByDescripcionIgnoreCase(selector);
        return subConcepto == null ? null : subConcepto.getId();
    }
}
