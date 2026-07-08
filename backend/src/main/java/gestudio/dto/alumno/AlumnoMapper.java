package gestudio.dto.alumno;

import gestudio.dto.alumno.request.AlumnoRegistroRequest;
import gestudio.dto.alumno.response.AlumnoResponse;
import gestudio.entidades.Alumno;
import org.mapstruct.Mapper;
import org.mapstruct.Mapping;
import org.mapstruct.MappingTarget;
import org.mapstruct.Named;

@Mapper(componentModel = "spring")
public interface AlumnoMapper {
    @Named("toResponse")
    @Mapping(target = "edad", ignore = true)
    @Mapping(target = "inscripciones", ignore = true)
    AlumnoResponse toResponse(Alumno alumno);

    @Mapping(target = "edad", ignore = true)
    @Mapping(target = "inscripciones", ignore = true)
    AlumnoResponse toSimpleResponse(Alumno alumno);

    @Mapping(target = "version", ignore = true)
    @Mapping(target = "activo", constant = "true")
    Alumno toEntity(AlumnoRegistroRequest request);

    @Mapping(target = "id", ignore = true)
    @Mapping(target = "version", ignore = true)
    void updateEntityFromRequest(AlumnoRegistroRequest request, @MappingTarget Alumno alumno);

}
