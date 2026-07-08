package gestudio.dto.metodopago.response;

import com.fasterxml.jackson.annotation.JsonFormat;

import java.math.BigDecimal;

public record MetodoPagoResponse(
        Long id,
        String descripcion,
        Boolean activo,
        @JsonFormat(shape = JsonFormat.Shape.STRING) BigDecimal recargo
) {
}
