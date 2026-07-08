package gestudio.dto.asistencia.request;

import java.util.List;

public record AsistenciaAlumnoMensualModificacionRequest(
        Long id, // ID del registro de AsistenciaAlumnoMensual
        String observacion,
        List<AsistenciaDiariaModificacionRequest> asistenciasDiarias
) {}
