package gestudio.dto.asistencia.request;

import jakarta.validation.constraints.NotNull;
import java.util.List;

public record AsistenciaMensualRegistroRequest(
        @NotNull Integer mes,
        @NotNull Integer anio,
        @NotNull Long disciplinaId,  // Cambiado de inscripcionId a disciplinaId
        List<AsistenciaDiariaRegistroRequest> asistenciasDiarias // Opcional; puede generarse automaticamente si esta vacio
) {}
