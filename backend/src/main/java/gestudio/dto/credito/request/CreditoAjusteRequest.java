package gestudio.dto.credito.request;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

public record CreditoAjusteRequest(
        @NotNull Long alumnoId,
        @NotBlank @Pattern(regexp = "^(0|[1-9]\\d*)(\\.\\d{1,2})?$") String importe,
        @NotBlank @Pattern(regexp = "CREDITO|DEBITO") String direccion,
        @NotBlank @Size(max = 500) String motivo,
        @NotBlank @Size(max = 120) String idempotencyKey
) {
}
