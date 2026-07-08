package gestudio.dto.cargo.response;

import java.time.LocalDate;

public record CargoResponse(
        Long id,
        Long alumnoId,
        String tipo,
        String descripcion,
        String importeOriginal,
        String importeAplicado,
        String saldo,
        LocalDate fechaEmision,
        LocalDate fechaVencimiento,
        String estado
) {
}
