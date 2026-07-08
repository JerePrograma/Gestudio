package ledance.dto.rol.request;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record RolRegistroRequest(
        @NotBlank @Size(max = 50) String codigo,
        @NotBlank @Size(max = 100) String nombre,
        @Size(max = 255) String descripcionFuncional
) {
}
