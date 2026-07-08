package ledance.dto.usuario.request;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;

import java.util.List;

/**
 * DTO para registrar un nuevo usuario.
 */
public record UsuarioRegistroRequest(
        @NotBlank String nombreUsuario,
        @NotBlank String contrasena,
        @NotEmpty List<@NotBlank String> roles
) {}
