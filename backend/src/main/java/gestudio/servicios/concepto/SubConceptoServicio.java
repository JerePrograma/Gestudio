package gestudio.servicios.concepto;

import gestudio.dto.concepto.request.SubConceptoRegistroRequest;
import gestudio.dto.concepto.response.SubConceptoResponse;
import gestudio.dto.concepto.SubConceptoMapper;
import gestudio.entidades.SubConcepto;
import gestudio.repositorios.SubConceptoRepositorio;
import org.flywaydb.core.internal.util.StringUtils;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.util.List;
import java.util.stream.Collectors;

@Service
public class SubConceptoServicio {

    private final SubConceptoRepositorio subConceptoRepositorio;
    private final SubConceptoMapper subConceptoMapper;

    public SubConceptoServicio(SubConceptoRepositorio subConceptoRepositorio,
                               SubConceptoMapper subConceptoMapper) {
        this.subConceptoRepositorio = subConceptoRepositorio;
        this.subConceptoMapper = subConceptoMapper;
    }

    // Crea un subconcepto nuevo. El mapper se encarga de transformar la descripcion a mayusculas.
    @Transactional
    public SubConceptoResponse crearSubConcepto(SubConceptoRegistroRequest request) {
        SubConcepto subConcepto = subConceptoMapper.toEntity(request);
        SubConcepto saved = subConceptoRepositorio.save(subConcepto);
        return subConceptoMapper.toResponse(saved);
    }

    // Actualiza un subconcepto existente.
    @Transactional
    public SubConceptoResponse actualizarSubConcepto(Long id, SubConceptoRegistroRequest request) {
        SubConcepto subConcepto = subConceptoRepositorio.findById(id)
                .orElseThrow(() -> new IllegalArgumentException("SubConcepto no encontrado con id: " + id));
        subConceptoMapper.updateEntityFromRequest(request, subConcepto);
        SubConcepto updated = subConceptoRepositorio.save(subConcepto);
        return subConceptoMapper.toResponse(updated);
    }

    // Retorna la lista completa de subconceptos.
    @Transactional(readOnly = true)
    public List<SubConceptoResponse> listarSubConceptos() {
        return subConceptoRepositorio.findAll().stream()
                .map(subConceptoMapper::toResponse)
                .collect(Collectors.toList());
    }

    // Retorna un subconcepto por su ID.
    @Transactional(readOnly = true)
    public SubConceptoResponse obtenerSubConceptoPorId(Long id) {
        SubConcepto subConcepto = subConceptoRepositorio.findById(id)
                .orElseThrow(() -> new IllegalArgumentException("SubConcepto no encontrado con id: " + id));
        return subConceptoMapper.toResponse(subConcepto);
    }

    // Elimina (o da de baja) un subconcepto.
    @Transactional
    public void eliminarSubConcepto(Long id) {
        if (!subConceptoRepositorio.existsById(id)) {
            throw new IllegalArgumentException("SubConcepto no encontrado con id: " + id);
        }
        subConceptoRepositorio.deleteById(id);
    }

    // Busca subconceptos por nombre (o parte de el). Utiliza el metodo definido en el repositorio.
    @Transactional(readOnly = true)
    public List<SubConceptoResponse> buscarPorNombre(String nombre) {
        return subConceptoRepositorio.buscarPorDescripcion(nombre).stream()
                .map(subConceptoMapper::toResponse)
                .collect(Collectors.toList());
    }


    public SubConcepto findByDescripcionIgnoreCase(String subConceptoDesc) {
        if (!StringUtils.hasText(subConceptoDesc)) {
            throw new IllegalArgumentException("La descripcion del sub concepto es requerida.");
        }
        return subConceptoRepositorio.findByDescripcionIgnoreCase(subConceptoDesc.trim())
                .orElse(null);
    }
}
