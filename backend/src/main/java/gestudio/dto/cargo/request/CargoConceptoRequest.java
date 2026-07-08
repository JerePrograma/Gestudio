package gestudio.dto.cargo.request;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import jakarta.validation.constraints.NotBlank;

import java.time.LocalDate;

public record CargoConceptoRequest(
        @NotNull Long alumnoId,
        @NotNull Long conceptoId,
        @NotNull LocalDate fechaVencimiento,
        @Size(max = 255) String descripcion,
        @NotBlank @Size(max = 100) String idempotencyKey
) {
}
