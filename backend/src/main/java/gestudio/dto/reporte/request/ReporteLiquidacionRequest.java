package gestudio.dto.reporte.request;

import com.fasterxml.jackson.annotation.JsonFormat;
import jakarta.validation.constraints.NotNull;

import java.math.BigDecimal;
import java.time.LocalDate;

public record ReporteLiquidacionRequest(
        @NotNull LocalDate fechaInicio,
        @NotNull LocalDate fechaFin,
        Long disciplinaId,
        Long profesorId,
        @NotNull @JsonFormat(shape = JsonFormat.Shape.STRING) BigDecimal porcentajeEscuela
) {
}
