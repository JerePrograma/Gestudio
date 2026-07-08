package gestudio.dto.egreso.request;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import java.time.LocalDate;

public record EgresoRegistroRequest(
        LocalDate fecha,
        @NotBlank @Pattern(regexp = "^(0|[1-9]\\d*)(\\.\\d{1,2})?$") String monto,
        @Size(max = 500) String observaciones,
        @NotNull Long metodoPagoId,
        @NotBlank @Size(max = 100) String idempotencyKey
) {
}
