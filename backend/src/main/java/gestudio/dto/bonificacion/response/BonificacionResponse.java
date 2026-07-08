package gestudio.dto.bonificacion.response;

import com.fasterxml.jackson.annotation.JsonFormat;

import java.math.BigDecimal;

public record BonificacionResponse(
        Long id,
        String descripcion,
        @JsonFormat(shape = JsonFormat.Shape.STRING) BigDecimal porcentajeDescuento,
        @JsonFormat(shape = JsonFormat.Shape.STRING) BigDecimal valorFijo,
        Boolean activo,
        String observaciones
) {
}
