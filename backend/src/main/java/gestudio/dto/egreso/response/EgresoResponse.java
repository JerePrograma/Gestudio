package gestudio.dto.egreso.response;

import java.time.LocalDate;

public record EgresoResponse(
        Long id,
        LocalDate fecha,
        String monto,
        String observaciones,
        Long metodoPagoId,
        Long usuarioId,
        String estado,
        String idempotencyKey
) {
}
