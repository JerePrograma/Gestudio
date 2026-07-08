package gestudio.dto.recargo.request;

import com.fasterxml.jackson.annotation.JsonFormat;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.math.BigDecimal;

public record RecargoRegistroRequest(
        @NotBlank String descripcion,
        @NotNull @JsonFormat(shape = JsonFormat.Shape.STRING) BigDecimal porcentaje,
        @NotNull @JsonFormat(shape = JsonFormat.Shape.STRING) BigDecimal valorFijo,
        Integer diaDelMesAplicacion,
        Boolean activo
) {
}
