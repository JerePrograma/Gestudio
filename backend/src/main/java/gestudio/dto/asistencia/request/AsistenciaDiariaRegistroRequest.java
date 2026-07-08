package gestudio.dto.asistencia.request;

import jakarta.validation.constraints.NotNull;
import java.time.LocalDate;
import gestudio.entidades.EstadoAsistencia;

public record AsistenciaDiariaRegistroRequest(
        Long id, // Para creacion o actualizacion
        @NotNull LocalDate fecha,
        @NotNull EstadoAsistencia estado,
        Long asistenciaAlumnoMensualId
) {}
