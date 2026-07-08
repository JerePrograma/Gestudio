package gestudio.dto.asistencia;

import gestudio.dto.alumno.AlumnoMapper;
import gestudio.dto.asistencia.request.AsistenciaDiariaRegistroRequest;
import gestudio.dto.asistencia.request.AsistenciaDiariaModificacionRequest;
import gestudio.dto.asistencia.response.AsistenciaDiariaDetalleResponse;
import gestudio.entidades.AsistenciaDiaria;
import org.mapstruct.Mapper;
import org.mapstruct.Mapping;

@Mapper(componentModel = "spring", uses = AlumnoMapper.class)
public interface AsistenciaDiariaMapper {

    @Mapping(target = "id", source = "id")
    @Mapping(target = "fecha", source = "fecha")
    @Mapping(target = "estado", source = "estado")
    // Se asigna el objeto AlumnoResponse a partir de la inscripcion del alumno
    @Mapping(target = "alumno", source = "asistenciaAlumnoMensual.inscripcion.alumno", qualifiedByName = "toResponse")
    // Se obtiene el id del registro mensual del alumno
    @Mapping(target = "asistenciaAlumnoMensualId", source = "asistenciaAlumnoMensual.id")
    @Mapping(target = "asistenciaMensualId", source = "asistenciaAlumnoMensual.asistenciaMensual.id")
    @Mapping(target = "disciplinaId", source = "asistenciaAlumnoMensual.asistenciaMensual.disciplina.id")
    AsistenciaDiariaDetalleResponse toDTO(AsistenciaDiaria asistenciaDiaria);

    @Mapping(target = "id", ignore = false)
    // La relacion con asistenciaAlumnoMensual se establecera por separado en el servicio
    @Mapping(target = "asistenciaAlumnoMensual", ignore = true)
    @Mapping(target = "vigente", constant = "true")
    AsistenciaDiaria toEntity(AsistenciaDiariaRegistroRequest request);

    @Mapping(target = "id", source = "id")
    @Mapping(target = "asistenciaAlumnoMensual", ignore = true)
    @Mapping(target = "vigente", ignore = true)
    void updateEntityFromRequest(AsistenciaDiariaModificacionRequest request,
                                 @org.mapstruct.MappingTarget AsistenciaDiaria asistenciaDiaria);

}
