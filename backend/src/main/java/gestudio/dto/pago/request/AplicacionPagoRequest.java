package gestudio.dto.pago.request;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;

public record AplicacionPagoRequest(
        @NotNull Long cargoId,
        @NotBlank @Pattern(regexp = "^(0|[1-9]\\d*)(\\.\\d{1,2})?$") String importe
) {
}
