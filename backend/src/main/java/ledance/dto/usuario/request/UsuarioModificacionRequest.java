package ledance.dto.usuario.request;

import java.util.Set;

public record UsuarioModificacionRequest(
        String nombreUsuario,
        String contrasena,
        Set<String> roles,
        Boolean activo
) {
}