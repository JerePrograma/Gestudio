package gestudio.dto.request;

import jakarta.validation.constraints.NotNull;

public record ObservacionMensualRequest(
        @NotNull Long asistenciaMensualId,
        @NotNull Long alumnoId,
        String observacion
) {}