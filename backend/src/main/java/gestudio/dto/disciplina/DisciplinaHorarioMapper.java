package gestudio.dto.disciplina;

import gestudio.dto.disciplina.request.DisciplinaHorarioRequest;
import gestudio.dto.disciplina.response.DisciplinaHorarioResponse;
import gestudio.entidades.DisciplinaHorario;
import org.mapstruct.Mapper;
import org.mapstruct.Mapping;
import org.mapstruct.Named;

import java.util.List;
import java.util.stream.Collectors;

@Mapper(componentModel = "spring")
public interface DisciplinaHorarioMapper {

    @Mapping(target = "id", source = "id")
    @Mapping(target = "diaSemana", source = "diaSemana")
    @Mapping(target = "horarioInicio", source = "horarioInicio")
    @Mapping(target = "duracion", source = "duracion")
    DisciplinaHorarioResponse toResponse(DisciplinaHorario horario);

    @Named("toResponseList")
    default List<DisciplinaHorarioResponse> toResponseList(List<DisciplinaHorario> horarios) {
        return horarios.stream().map(this::toResponse).collect(Collectors.toList());
    }

    default DisciplinaHorario toEntity(DisciplinaHorarioRequest request) {
        DisciplinaHorario horario = new DisciplinaHorario();
        horario.setDiaSemana(request.diaSemana());
        horario.setHorarioInicio(request.horarioInicio());
        horario.setDuracion(request.duracion());
        // No asignamos disciplina aqui, se hara en el servicio.
        return horario;
    }

}
