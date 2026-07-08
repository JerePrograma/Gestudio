package gestudio.dto.asistencia.response;

import gestudio.dto.alumno.response.AlumnoResponse;
import gestudio.entidades.EstadoAsistencia;
import java.time.LocalDate;

public record AsistenciaDiariaDetalleResponse(
        Long id,
        LocalDate fecha,
        EstadoAsistencia estado,
        AlumnoResponse alumno,
        Long asistenciaMensualId,
        Long disciplinaId,
        Long asistenciaAlumnoMensualId  // Campo agregado
) { }


