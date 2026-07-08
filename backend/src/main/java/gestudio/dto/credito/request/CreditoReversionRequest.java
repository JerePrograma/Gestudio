package gestudio.dto.credito.request;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record CreditoReversionRequest(
        @NotBlank @Size(max = 120) String idempotencyKey,
        @NotBlank @Size(max = 500) String motivo
) {
}
