package gestudio.dto.disciplina.request;

import com.fasterxml.jackson.annotation.JsonFormat;
import jakarta.validation.constraints.NotNull;

import java.math.BigDecimal;
import java.util.List;

public record DisciplinaModificacionRequest(
        @NotNull String nombre,
        @NotNull Long salonId,
        @NotNull Long profesorId,
        @NotNull @JsonFormat(shape = JsonFormat.Shape.STRING) BigDecimal valorCuota,
        @JsonFormat(shape = JsonFormat.Shape.STRING) BigDecimal matricula,
        @JsonFormat(shape = JsonFormat.Shape.STRING) BigDecimal claseSuelta,
        @JsonFormat(shape = JsonFormat.Shape.STRING) BigDecimal clasePrueba,
        Boolean activo,
        List<DisciplinaHorarioModificacionRequest> horarios
) {
}
