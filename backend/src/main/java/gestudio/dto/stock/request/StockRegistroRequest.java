package gestudio.dto.stock.request;

import com.fasterxml.jackson.annotation.JsonFormat;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.PositiveOrZero;
import jakarta.validation.constraints.Size;

import java.math.BigDecimal;

public record StockRegistroRequest(
        Long id,
        @NotBlank String nombre,
        @NotNull @JsonFormat(shape = JsonFormat.Shape.STRING) BigDecimal precio,
        @NotNull @PositiveOrZero Integer stock,
        @NotNull Boolean requiereControlDeStock,
        Boolean activo,
        @Size(max = 100) String codigoBarras,
        @NotBlank @Size(max = 100) String idempotencyKey
) {
}
