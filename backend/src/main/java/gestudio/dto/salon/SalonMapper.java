package gestudio.dto.salon;

import gestudio.dto.salon.request.SalonModificacionRequest;
import gestudio.dto.salon.request.SalonRegistroRequest;
import gestudio.dto.salon.response.SalonResponse;
import gestudio.entidades.Salon;
import org.mapstruct.Mapper;
import org.mapstruct.Mapping;

@Mapper(componentModel = "spring")
public interface SalonMapper {

    // Convierte de Request a Entidad
    @Mapping(target = "id", ignore = true) // El ID se genera automaticamente
    @Mapping(target = "activo", constant = "true")
    Salon toEntity(SalonRegistroRequest request);

    // Para modificacion (puede compartir la misma logica)
    @Mapping(target = "id", ignore = true)
    @Mapping(target = "activo", ignore = true)
    Salon toEntity(SalonModificacionRequest request);

    // Convierte la entidad a Response
    SalonResponse toResponse(Salon entity);

}
