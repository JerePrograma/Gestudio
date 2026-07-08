package gestudio.dto.mensualidad.response;

import java.time.LocalDate;

public record MensualidadResponse(
        Long id,
        Long inscripcionId,
        Integer anio,
        Integer mes,
        LocalDate fechaGeneracion,
        LocalDate fechaVencimiento,
        String estado,
        String descripcion,
        Long cargoId,
        String importeOriginal,
        String saldo
) {
}
