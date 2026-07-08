package gestudio.dto.salon.request;

import jakarta.validation.constraints.NotBlank;

public record SalonModificacionRequest(
        @NotBlank String nombre,
        String descripcion
) {}
