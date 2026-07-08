package gestudio.dto.metodopago.request;

import com.fasterxml.jackson.annotation.JsonFormat;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.math.BigDecimal;

public record MetodoPagoRegistroRequest(
        Long id,
        @NotBlank String descripcion,
        Boolean activo,
        @NotNull @JsonFormat(shape = JsonFormat.Shape.STRING) BigDecimal recargo
) {
}
