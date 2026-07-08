package gestudio.servicios.bonificacion;

import gestudio.dto.bonificacion.BonificacionMapper;
import gestudio.dto.bonificacion.request.BonificacionModificacionRequest;
import gestudio.dto.bonificacion.request.BonificacionRegistroRequest;
import gestudio.dto.bonificacion.response.BonificacionResponse;
import gestudio.entidades.Bonificacion;
import gestudio.repositorios.BonificacionRepositorio;
import jakarta.transaction.Transactional;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.stream.Collectors;

@Service
public class BonificacionServicio {

    private static final Logger log = LoggerFactory.getLogger(BonificacionServicio.class);

    private final BonificacionRepositorio bonificacionRepositorio;
    private final BonificacionMapper bonificacionMapper;

    public BonificacionServicio(BonificacionRepositorio bonificacionRepositorio, BonificacionMapper bonificacionMapper) {
        this.bonificacionRepositorio = bonificacionRepositorio;
        this.bonificacionMapper = bonificacionMapper;
    }

    @Transactional
    public BonificacionResponse crearBonificacion(BonificacionRegistroRequest requestDTO) {
        log.info("Creando bonificacion: {}", requestDTO.descripcion());
        if (bonificacionRepositorio.existsByDescripcion(requestDTO.descripcion())) {
            throw new IllegalArgumentException("Ya existe una bonificacion con la misma descripcion.");
        }
        Bonificacion bonificacion = bonificacionMapper.toEntity(requestDTO);
        Bonificacion guardada = bonificacionRepositorio.save(bonificacion);
        return bonificacionMapper.toDTO(guardada);
    }

    public List<BonificacionResponse> listarBonificaciones() {
        return bonificacionRepositorio.findByActivoTrue().stream()
                .map(bonificacionMapper::toDTO)
                .collect(Collectors.toList());
    }

    public BonificacionResponse obtenerBonificacionPorId(Long id) {
        Bonificacion bonificacion = bonificacionRepositorio.findById(id)
                .orElseThrow(() -> new IllegalArgumentException("Bonificacion no encontrada."));
        return bonificacionMapper.toDTO(bonificacion);
    }

    @Transactional
    public BonificacionResponse actualizarBonificacion(Long id, BonificacionModificacionRequest requestDTO) {
        log.info("Actualizando bonificacion con id: {}", id);
        Bonificacion bonificacion = bonificacionRepositorio.findById(id)
                .orElseThrow(() -> new IllegalArgumentException("Bonificacion no encontrada."));
        bonificacionMapper.updateEntityFromRequest(requestDTO, bonificacion);
        Bonificacion actualizada = bonificacionRepositorio.save(bonificacion);
        return bonificacionMapper.toDTO(actualizada);
    }

    @Transactional
    public void eliminarBonificacion(Long id) {
        log.info("Dando de baja la bonificacion con id: {}", id);
        Bonificacion bonificacion = bonificacionRepositorio.findById(id)
                .orElseThrow(() -> new IllegalArgumentException("Bonificacion no encontrada."));
        if (!bonificacion.getActivo()) {
            throw new IllegalStateException("La bonificacion ya esta inactiva.");
        }
        bonificacion.setActivo(false);
        bonificacionRepositorio.save(bonificacion);
    }
}
