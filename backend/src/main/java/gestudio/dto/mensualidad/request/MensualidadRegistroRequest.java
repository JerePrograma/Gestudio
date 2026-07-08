package gestudio.dto.mensualidad.request;

import jakarta.validation.constraints.NotNull;

public record MensualidadRegistroRequest(
        @NotNull Long inscripcionId,
        @NotNull Integer anio,
        @NotNull Integer mes,
        Long recargoId,
        Long bonificacionId
) {
}
