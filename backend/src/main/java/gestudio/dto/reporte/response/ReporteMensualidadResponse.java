package gestudio.dto.reporte.response;

import java.time.LocalDate;

public record ReporteMensualidadResponse(
        Long cargoId,
        LocalDate fechaEmision,
        String alumno,
        String disciplina,
        String profesor,
        String importeOriginal,
        String importeCobrado,
        String saldo,
        String estado
) {
}
