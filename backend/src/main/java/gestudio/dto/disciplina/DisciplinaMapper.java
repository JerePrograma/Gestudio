package gestudio.dto.disciplina;

import gestudio.dto.disciplina.request.DisciplinaRegistroRequest;
import gestudio.dto.disciplina.request.DisciplinaModificacionRequest;
import gestudio.dto.disciplina.response.DisciplinaResponse;
import gestudio.entidades.Disciplina;
import gestudio.entidades.Salon;
import org.mapstruct.Mapper;
import org.mapstruct.Mapping;

@Mapper(componentModel = "spring", uses = {DisciplinaHorarioMapper.class})
public interface DisciplinaMapper {

    @Mapping(target = "id", source = "id")
    @Mapping(target = "nombre", source = "nombre")
    @Mapping(target = "salon", source = "salon.nombre")
    @Mapping(target = "salonId", source = "salon.id")
    @Mapping(target = "valorCuota", source = "valorCuota")
    @Mapping(target = "profesorNombre", source = "profesor.nombre")
    @Mapping(target = "profesorApellido", source = "profesor.apellido")
    @Mapping(target = "profesorId", source = "profesor.id")
    @Mapping(target = "inscritos", constant = "0")
    @Mapping(target = "activo", source = "activo")
    @Mapping(target = "horarios", source = "horarios", qualifiedByName = "toResponseList")
    DisciplinaResponse toResponse(Disciplina disciplina);

    @Mapping(target = "salon.id", source = "salonId")
    @Mapping(target = "profesor", ignore = true)
    @Mapping(target = "activo", constant = "true")
    @Mapping(target = "version", ignore = true)
    Disciplina toEntity(DisciplinaRegistroRequest request);

    @Mapping(target = "id", ignore = true)
    @Mapping(target = "salon", ignore = true)
    @Mapping(target = "profesor", ignore = true)
    @Mapping(target = "horarios", ignore = true)
    @Mapping(target = "version", ignore = true)
    void updateEntityFromRequest(DisciplinaModificacionRequest request, @org.mapstruct.MappingTarget Disciplina disciplina);

    default String mapSalonToString(Salon salon) {
        if (salon == null) {
            return null;
        }
        // Ajusta segun la propiedad que quieras usar
        // Por ejemplo, si tu Salon tiene un campo "nombre" o "descripcion":
        return salon.getNombre();
    }

}
