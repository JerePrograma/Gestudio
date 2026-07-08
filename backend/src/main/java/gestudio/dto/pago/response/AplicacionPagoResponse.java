package gestudio.dto.pago.response;

public record AplicacionPagoResponse(
        Long id,
        Long cargoId,
        String importeAplicado,
        String estado,
        String saldoCargo
) {
}
