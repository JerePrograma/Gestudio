package gestudio.dto.asistencia;

import gestudio.dto.alumno.AlumnoMapper;
import gestudio.dto.disciplina.DisciplinaMapper;
import gestudio.dto.asistencia.request.AsistenciaMensualRegistroRequest;
import gestudio.dto.asistencia.request.AsistenciaMensualModificacionRequest;
import gestudio.dto.asistencia.response.*;
import gestudio.entidades.AsistenciaMensual;
import gestudio.entidades.AsistenciaAlumnoMensual;
import gestudio.entidades.Salon;
import org.mapstruct.Mapper;
import org.mapstruct.Mapping;
import org.mapstruct.MappingTarget;

import java.util.List;

@Mapper(componentModel = "spring", uses = {AsistenciaDiariaMapper.class, AlumnoMapper.class, DisciplinaMapper.class})
public interface AsistenciaMensualMapper {

    // Mapea la planilla completa
    @Mapping(target = "disciplina", source = "disciplina")
    @Mapping(target = "profesor", source = "disciplina.profesor.nombre")
    @Mapping(target = "alumnos", source = "asistenciasAlumnoMensual")
    AsistenciaMensualDetalleResponse toDetalleDTO(AsistenciaMensual asistenciaMensual);

    // Metodo de mapeo para convertir Salon a String (su nombre)
    default String map(Salon salon) {
        return (salon != null) ? salon.getNombre() : null;
    }

    // Mapea para listado; se utiliza un objeto anidado para la disciplina.
    @Mapping(target = "disciplina", source = "disciplina")
    @Mapping(target = "profesor", source = "disciplina.profesor.nombre")
    @Mapping(target = "mes", source = "mes")
    @Mapping(target = "anio", source = "anio")
    @Mapping(target = "cantidadAlumnos", expression = "java(asistenciaMensual.getAsistenciasAlumnoMensual().size())")
    AsistenciaMensualListadoResponse toListadoDTO(AsistenciaMensual asistenciaMensual);

    // Para crear una nueva planilla (se ignora la relacion de alumnos, que se establecera posteriormente)
    @Mapping(target = "id", ignore = true)
    @Mapping(target = "disciplina", ignore = true)
    @Mapping(target = "asistenciasAlumnoMensual", ignore = true)
    AsistenciaMensual toEntity(AsistenciaMensualRegistroRequest request);

    /**
     * Actualiza la planilla mensual sin modificar disciplina, mes ni año.
     * La actualizacion de los registros de alumno se hace por separado.
     */
    @Mapping(target = "id", ignore = true)
    @Mapping(target = "disciplina", ignore = true)
    @Mapping(target = "mes", ignore = true)
    @Mapping(target = "anio", ignore = true)
    @Mapping(target = "asistenciasAlumnoMensual", ignore = true)
    void updateEntityFromRequest(AsistenciaMensualModificacionRequest request,
                                 @MappingTarget AsistenciaMensual asistenciaMensual);

    List<AsistenciaAlumnoMensualDetalleResponse> toAlumnoDetalleDTOList(List<AsistenciaAlumnoMensual> alumnos);

    // Aqui se corrige el mapeo para que obtenga el alumno desde inscripcion.alumno
    @Mapping(target = "inscripcionId", source = "inscripcion.id")
    @Mapping(target = "observacion", source = "observacion")
    @Mapping(target = "asistenciaMensualId", source = "asistenciaMensual.id")
    @Mapping(target = "asistenciasDiarias", source = "asistenciasDiarias")
    @Mapping(target = "alumno", source = "inscripcion.alumno", qualifiedByName = "toResponse")
    AsistenciaAlumnoMensualDetalleResponse toAlumnoDetalleDTO(AsistenciaAlumnoMensual alumno);
}
