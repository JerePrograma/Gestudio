package gestudio.dto.reporte.observacion;

import java.time.LocalDate;

public record ObservacionProfesorDTO(
        Long id,
        Long profesorId,
        LocalDate fecha,
        String observacion
) {}
