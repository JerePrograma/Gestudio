package gestudio.dto.mensualidad;

import gestudio.dto.mensualidad.request.MensualidadRegistroRequest;
import gestudio.entidades.Mensualidad;
import org.mapstruct.Mapper;
import org.mapstruct.Mapping;
import org.mapstruct.MappingTarget;

@Mapper(componentModel = "spring")
public interface MensualidadMapper {
    @Mapping(target = "id", ignore = true)
    @Mapping(target = "inscripcion", ignore = true)
    @Mapping(target = "bonificacion", ignore = true)
    @Mapping(target = "recargo", ignore = true)
    @Mapping(target = "fechaGeneracion", ignore = true)
    @Mapping(target = "fechaVencimiento", ignore = true)
    @Mapping(target = "descripcion", ignore = true)
    @Mapping(target = "estado", ignore = true)
    @Mapping(target = "version", ignore = true)
    Mensualidad toEntity(MensualidadRegistroRequest request);

    @Mapping(target = "id", ignore = true)
    @Mapping(target = "inscripcion", ignore = true)
    @Mapping(target = "bonificacion", ignore = true)
    @Mapping(target = "recargo", ignore = true)
    @Mapping(target = "fechaGeneracion", ignore = true)
    @Mapping(target = "fechaVencimiento", ignore = true)
    @Mapping(target = "descripcion", ignore = true)
    @Mapping(target = "estado", ignore = true)
    @Mapping(target = "version", ignore = true)
    void updateEntityFromRequest(MensualidadRegistroRequest request, @MappingTarget Mensualidad mensualidad);
}
