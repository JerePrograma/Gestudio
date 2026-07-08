package gestudio.dto.asistencia.response;

import gestudio.dto.alumno.response.AlumnoResponse;

import java.util.List;

public record AsistenciaAlumnoMensualDetalleResponse(
        Long id,
        Long inscripcionId,
        AlumnoResponse alumno,
        String observacion,
        Long asistenciaMensualId,
        List<AsistenciaDiariaDetalleResponse> asistenciasDiarias
) { }
