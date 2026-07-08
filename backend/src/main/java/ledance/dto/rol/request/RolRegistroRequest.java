package ledance.dto.rol.request;

import jakarta.validation.constraints.NotBlank;

import java.util.Set;

public record RolRegistroRequest(
        @NotBlank String codigo,
        @NotBlank String nombre,
        String descripcionFuncional,
        Set<String> permisos
) {
}