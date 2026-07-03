package ledance.tarifas.api;

import java.time.Instant;
import java.time.LocalDate;

public record CondicionEconomicaResponse(
        Long id,
        Long inscripcionId,
        LocalDate vigenteDesde,
        String costoParticular,
        Long bonificacionId,
        String bonificacionDescripcion,
        String bonificacionPorcentaje,
        String bonificacionValorFijo,
        String motivo,
        Long creadaPorUsuarioId,
        String creadaPorUsername,
        Instant createdAt,
        boolean utilizada) {
}
