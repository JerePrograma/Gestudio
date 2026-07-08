package gestudio.dto.credito.response;

public record MovimientoCreditoResponse(
        Long id,
        Long alumnoId,
        Long cargoId,
        String tipo,
        String importe,
        String saldoCredito,
        String saldoCargo,
        String idempotencyKey
) {
}
