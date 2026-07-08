package gestudio.dto.pago.response;

import java.time.LocalDate;

public record PagoResumenResponse(
        Long id,
        LocalDate fecha,
        String montoRecibido,
        String estado
) {
}
