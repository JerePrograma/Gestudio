package gestudio.dto.pago;

import gestudio.dto.pago.response.PagoResponse;
import gestudio.entidades.Pago;
import org.springframework.stereotype.Component;

import java.util.List;

@Component
public class PagoMapper {
    public PagoResponse toDTO(Pago pago) {
        return new PagoResponse(pago.getId(), pago.getAlumno().getId(), pago.getMetodoPago().getId(),
                pago.getUsuario().getId(), pago.getFecha(), pago.getMontoRecibido().toPlainString(),
                pago.getEstado().name(), pago.getIdempotencyKey(), pago.getObservaciones(), "0.00", List.of());
    }

    public List<PagoResponse> toDTOList(List<Pago> pagos) {
        return pagos.stream().map(this::toDTO).toList();
    }
}
