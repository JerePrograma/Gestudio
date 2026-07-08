package ledance.dto.usuario.response;

import ledance.entidades.Permiso;
import ledance.entidades.Rol;
import ledance.entidades.Usuario;

import java.util.List;

/**
 * DTO de respuesta para un usuario.
 */
public record UsuarioResponse(
        Long id,
        String nombreUsuario,
        List<String> roles,
        List<String> permisos,
        Boolean activo
) {
    public static UsuarioResponse from(Usuario usuario) {
        List<Rol> rolesActivos = usuario.getRoles().stream()
                .filter(rol -> Boolean.TRUE.equals(rol.getActivo()))
                .sorted(java.util.Comparator.comparing(Rol::getCodigo))
                .toList();
        return new UsuarioResponse(
                usuario.getId(),
                usuario.getNombreUsuario(),
                rolesActivos.stream().map(Rol::getCodigo).toList(),
                rolesActivos.stream()
                        .flatMap(rol -> rol.getPermisos().stream())
                        .filter(permiso -> Boolean.TRUE.equals(permiso.getActivo()))
                        .map(Permiso::getCodigo)
                        .distinct()
                        .sorted()
                        .toList(),
                usuario.getActivo());
    }
}
