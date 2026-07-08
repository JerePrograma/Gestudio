package gestudio.dto.pago.request;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record PagoAnulacionRequest(
        @NotBlank @Size(max = 100) String idempotencyKey,
        @NotBlank @Size(max = 500) String motivo
) {
}
