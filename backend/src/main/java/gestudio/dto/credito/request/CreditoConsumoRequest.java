package gestudio.dto.credito.request;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

public record CreditoConsumoRequest(
        @NotNull Long alumnoId,
        @NotNull Long cargoId,
        @NotBlank @Pattern(regexp = "^(0|[1-9]\\d*)(\\.\\d{1,2})?$") String importe,
        @NotBlank @Size(max = 120) String idempotencyKey
) {
}
