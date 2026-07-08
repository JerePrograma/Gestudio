package gestudio.dto.asistencia.request;

import jakarta.validation.constraints.NotNull;
import java.time.LocalDate;
import gestudio.entidades.EstadoAsistencia;

public record AsistenciaDiariaModificacionRequest(
        @NotNull Long id,
        LocalDate fecha,
        @NotNull EstadoAsistencia estado
) {}
