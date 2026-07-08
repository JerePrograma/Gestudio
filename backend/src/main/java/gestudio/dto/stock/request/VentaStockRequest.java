package gestudio.dto.stock.request;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.Size;

import java.time.LocalDate;

public record VentaStockRequest(
        @NotNull Long alumnoId,
        @NotNull Long stockId,
        @NotNull @Positive Integer cantidad,
        @NotNull LocalDate fechaVencimiento,
        @NotBlank @Size(max = 100) String idempotencyKey
) {
}
