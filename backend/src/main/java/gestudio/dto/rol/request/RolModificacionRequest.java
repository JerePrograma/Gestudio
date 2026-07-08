package gestudio.dto.rol.request;

import jakarta.validation.constraints.NotBlank;

import java.util.Set;

public record RolModificacionRequest(
        @NotBlank String nombre,
        String descripcionFuncional,
        Boolean activo,
        Set<String> permisos
) {
}