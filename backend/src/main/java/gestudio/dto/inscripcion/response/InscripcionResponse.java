package gestudio.dto.inscripcion.response;

import java.time.LocalDate;

public record InscripcionResponse(
        Long id,
        Long alumnoId,
        String alumno,
        Long disciplinaId,
        String disciplina,
        Long bonificacionId,
        LocalDate fechaInscripcion,
        LocalDate fechaBaja,
        String estado,
        String costoParticular
) {
}
