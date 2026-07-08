package gestudio.dto.asistencia.response;

import gestudio.dto.disciplina.response.DisciplinaResponse;

public record AsistenciaMensualListadoResponse(
        Long id,
        Integer mes,
        Integer anio,
        DisciplinaResponse disciplina,
        String profesor,
        Integer cantidadAlumnos
) { }
