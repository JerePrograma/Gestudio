package gestudio.dto.usuario.request;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;

import java.util.Set;

public record UsuarioRegistroRequest(
        @NotBlank String nombreUsuario,
        @NotBlank String contrasena,
        @NotEmpty Set<String> roles
) {
}