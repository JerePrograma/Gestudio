package ledance.tarifas.api;

import java.time.Instant;
import java.time.LocalDate;

public record TarifaDisciplinaResponse(
        Long id,
        Long disciplinaId,
        LocalDate vigenteDesde,
        String valorCuota,
        String matricula,
        String claseSuelta,
        String clasePrueba,
        String motivo,
        Long creadaPorUsuarioId,
        String creadaPorUsername,
        Instant createdAt,
        boolean utilizada) {
}
