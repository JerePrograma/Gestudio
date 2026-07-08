package gestudio.dto.asistencia.response;

import java.util.List;

public record AsistenciasActivasResponse(
        int totalInscripcionesProcesadas,
        int totalPlanillasCreadas,
        int totalAsistenciasDiariasGeneradas,
        List<String> detalles
) { }
