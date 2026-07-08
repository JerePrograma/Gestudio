package gestudio.dto.reporte.observacion;

public record ObservacionProfesorRequest(
        Long profesorId,
        String fecha,         // Se espera formato ISO ("2025-03-27")
        String observacion
) {}
