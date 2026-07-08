package ledance.dto.usuario.response;

import java.util.List;

public record UsuarioResponse(
        Long id,
        String nombreUsuario,
        List<String> roles,
        List<String> permisos,
        Boolean activo
) {
}