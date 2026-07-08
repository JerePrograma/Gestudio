package gestudio.dto.bonificacion;

import gestudio.dto.bonificacion.request.BonificacionRegistroRequest;
import gestudio.dto.bonificacion.request.BonificacionModificacionRequest;
import gestudio.dto.bonificacion.response.BonificacionResponse;
import gestudio.entidades.Bonificacion;
import org.mapstruct.*;

@Mapper(componentModel = "spring")
public interface BonificacionMapper {

    /**
     * Mapea una bonificacion de registro a la entidad.
     * - "activo" se asigna automaticamente como `true`.
     */
    @Mapping(target = "id", ignore = true)
    @Mapping(target = "activo", constant = "true")
    Bonificacion toEntity(BonificacionRegistroRequest request);

    /**
     * Mapea una bonificacion a su DTO de respuesta.
     */
    @Mapping(target = "id", source = "id")
    BonificacionResponse toDTO(Bonificacion bonificacion);

    /**
     * Actualiza una bonificacion existente con nuevos datos.
     */
    @Mapping(target = "id", ignore = true)
    void updateEntityFromRequest(BonificacionModificacionRequest request, @MappingTarget Bonificacion bonificacion);
}
