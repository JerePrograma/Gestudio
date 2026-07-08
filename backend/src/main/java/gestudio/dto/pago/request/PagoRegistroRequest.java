package gestudio.dto.pago.request;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import java.util.List;

public record PagoRegistroRequest(
        @NotNull Long alumnoId,
        @NotNull Long metodoPagoId,
        @NotBlank @Pattern(regexp = "^(0|[1-9]\\d*)(\\.\\d{1,2})?$") String montoRecibido,
        @NotBlank @Size(max = 100) String idempotencyKey,
        @Size(max = 500) String observaciones,
        @NotNull List<@Valid AplicacionPagoRequest> aplicaciones,
        boolean generarCredito
) {
}
