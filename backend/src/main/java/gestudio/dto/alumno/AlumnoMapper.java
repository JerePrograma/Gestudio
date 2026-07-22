package gestudio.dto.alumno;

import gestudio.dto.alumno.request.AlumnoRegistroRequest;
import gestudio.dto.alumno.response.AlumnoResponse;
import gestudio.entidades.Alumno;
import org.mapstruct.BeanMapping;
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

    @BeanMapping(ignoreUnmappedSourceProperties = {"id", "activo", "fechaDeBaja", "inscripciones"})
    @Mapping(target = "id", ignore = true)
    @Mapping(target = "version", ignore = true)
    @Mapping(target = "activo", constant = "true")
    @Mapping(target = "fechaDeBaja", ignore = true)
    Alumno toEntity(AlumnoRegistroRequest request);

    @BeanMapping(ignoreUnmappedSourceProperties = {"id", "activo", "fechaDeBaja", "inscripciones"})
    @Mapping(target = "id", ignore = true)
    @Mapping(target = "version", ignore = true)
    @Mapping(target = "activo", ignore = true)
    @Mapping(target = "fechaDeBaja", ignore = true)
    void updateEntityFromRequest(AlumnoRegistroRequest request, @MappingTarget Alumno alumno);

}
