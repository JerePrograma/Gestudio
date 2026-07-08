package gestudio.dto.asistencia.request;

import java.util.List;

/**
 * Request para modificar la planilla mensual.
 * Ahora se reciben modificaciones por cada alumno.
 */
public record AsistenciaMensualModificacionRequest(
        List<AsistenciaAlumnoMensualModificacionRequest> asistenciasAlumnoMensual
) {}
