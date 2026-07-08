package gestudio.dto.reporte.observacion;

import gestudio.entidades.ObservacionProfesor;
import org.mapstruct.Mapper;
import org.mapstruct.Mapping;

@Mapper(componentModel = "spring")
public interface ObservacionProfesorMapper {

    @Mapping(source = "profesor.id", target = "profesorId")
    ObservacionProfesorDTO toDTO(ObservacionProfesor entity);

    @Mapping(target = "profesor", ignore = true)
    @Mapping(target = "activa", constant = "true")
    ObservacionProfesor toEntity(ObservacionProfesorDTO dto);
}
