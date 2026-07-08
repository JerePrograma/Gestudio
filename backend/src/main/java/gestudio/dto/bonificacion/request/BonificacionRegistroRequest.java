package gestudio.dto.bonificacion.request;

import com.fasterxml.jackson.annotation.JsonFormat;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.math.BigDecimal;

public record BonificacionRegistroRequest(
        @NotBlank String descripcion,
        @NotNull @JsonFormat(shape = JsonFormat.Shape.STRING) BigDecimal porcentajeDescuento,
        @NotNull @JsonFormat(shape = JsonFormat.Shape.STRING) BigDecimal valorFijo,
        Boolean activo,
        String observaciones
) {
}
