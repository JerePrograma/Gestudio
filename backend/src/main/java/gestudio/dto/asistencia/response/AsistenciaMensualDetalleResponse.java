package gestudio.dto.asistencia.response;

import gestudio.dto.disciplina.response.DisciplinaResponse;

import java.util.List;

public record AsistenciaMensualDetalleResponse(
        Long id,
        Integer mes,
        Integer anio,
        DisciplinaResponse disciplina,
        String profesor,
        List<AsistenciaAlumnoMensualDetalleResponse> alumnos
) { }
