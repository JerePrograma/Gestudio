package gestudio.dto.pago.response;

import java.time.LocalDate;
import java.util.List;

public record PagoResponse(
        Long id,
        Long alumnoId,
        Long metodoPagoId,
        Long usuarioId,
        LocalDate fecha,
        String montoRecibido,
        String estado,
        String idempotencyKey,
        String observaciones,
        String creditoGenerado,
        List<AplicacionPagoResponse> aplicaciones
) {
}
