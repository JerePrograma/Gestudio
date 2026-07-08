package ledance.dto.rol.response;

public record PermisoResponse(
        Long id,
        String codigo,
        String descripcion,
        String modulo,
        Boolean activo,
        Boolean sistema
) {
}