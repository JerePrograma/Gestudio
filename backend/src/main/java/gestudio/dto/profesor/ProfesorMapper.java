package gestudio.dto.profesor;

import gestudio.dto.profesor.request.ProfesorRegistroRequest;
import gestudio.dto.profesor.request.ProfesorModificacionRequest;
import gestudio.dto.profesor.response.ProfesorResponse;
import gestudio.entidades.Profesor;
import gestudio.entidades.Salon;
import org.mapstruct.*;

@Mapper(componentModel = "spring")
public interface ProfesorMapper {

    @Mapping(target = "id", ignore = true)
    @Mapping(target = "activo", constant = "true")
    @Mapping(target = "usuario", ignore = true)
    @Mapping(target = "version", ignore = true)
    @Mapping(target = "fechaNacimiento", source = "fechaNacimiento")
    @Mapping(target = "telefono", source = "telefono")
    Profesor toEntity(ProfesorRegistroRequest request);

    @Mapping(target = "id", ignore = true)
    @Mapping(target = "usuario", ignore = true)
    @Mapping(target = "version", ignore = true)
    @Mapping(target = "fechaNacimiento", source = "fechaNacimiento")
    @Mapping(target = "telefono", source = "telefono")
    void updateEntityFromRequest(ProfesorModificacionRequest request, @MappingTarget Profesor profesor);

    @Mapping(target = "edad", ignore = true)
    @Mapping(target = "disciplinas", ignore = true)
    ProfesorResponse toResponse(Profesor profesor);

    default String mapSalonToString(Salon salon) {
        if (salon == null) {
            return null;
        }
        // Ajusta segun la propiedad que quieras usar
        // Por ejemplo, si tu Salon tiene un campo "nombre" o "descripcion":
        return salon.getNombre();
    }
}
