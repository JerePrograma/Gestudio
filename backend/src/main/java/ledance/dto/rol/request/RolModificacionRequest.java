package ledance.dto.rol.request;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record RolModificacionRequest(
        @NotBlank @Size(max = 100) String nombre,
        @Size(max = 255) String descripcionFuncional,
        Boolean activo
) {
}
