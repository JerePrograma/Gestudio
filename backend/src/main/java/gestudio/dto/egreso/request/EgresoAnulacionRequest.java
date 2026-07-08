package gestudio.dto.egreso.request;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record EgresoAnulacionRequest(
        @NotBlank @Size(max = 100) String idempotencyKey,
        @NotBlank @Size(max = 500) String motivo
) {
}
