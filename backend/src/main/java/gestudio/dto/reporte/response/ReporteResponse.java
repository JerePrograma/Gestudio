package gestudio.dto.reporte.response;

import java.time.LocalDate;

public record ReporteResponse(
        Long id,
        String tipo,
        String descripcion,
        LocalDate fechaGeneracion, // ✅ Se almacena la fecha de generacion
        Boolean activo
) {
}