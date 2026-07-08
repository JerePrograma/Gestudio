package gestudio.dto.inscripcion.request;

import com.fasterxml.jackson.annotation.JsonFormat;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.PastOrPresent;

import java.math.BigDecimal;
import java.time.LocalDate;

public record InscripcionRegistroRequest(
        Long id,
        @NotNull Long alumnoId,
        @NotNull Long disciplinaId,
        Long bonificacionId,
        @PastOrPresent LocalDate fechaInscripcion,
        @JsonFormat(shape = JsonFormat.Shape.STRING) BigDecimal costoParticular
) {
}
