package gestudio.dto.caja.response;

import java.time.Instant;
import java.time.LocalDate;

public record MovimientoCajaResponse(
        Long id,
        String tipo,
        LocalDate fecha,
        String importe,
        Long metodoPagoId,
        Long pagoId,
        Long egresoId,
        String motivo,
        Instant createdAt
) {
}
