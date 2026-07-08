package gestudio.dto.disciplina.response;

import com.fasterxml.jackson.annotation.JsonFormat;

import java.math.BigDecimal;
import java.util.List;

public record DisciplinaResponse(
        Long id,
        String nombre,
        String salon,
        Long salonId,
        @JsonFormat(shape = JsonFormat.Shape.STRING) BigDecimal valorCuota,
        @JsonFormat(shape = JsonFormat.Shape.STRING) BigDecimal matricula,
        String profesorNombre,
        String profesorApellido,
        Long profesorId,
        Integer inscritos,
        Boolean activo,
        @JsonFormat(shape = JsonFormat.Shape.STRING) BigDecimal claseSuelta,
        @JsonFormat(shape = JsonFormat.Shape.STRING) BigDecimal clasePrueba,
        List<DisciplinaHorarioResponse> horarios
) {
}
