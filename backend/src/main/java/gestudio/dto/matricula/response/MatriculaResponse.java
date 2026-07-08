package gestudio.dto.matricula.response;

import java.time.LocalDate;

public record MatriculaResponse(Long id, Integer anio, LocalDate fechaEmision, String estado, Long alumnoId) {
}
