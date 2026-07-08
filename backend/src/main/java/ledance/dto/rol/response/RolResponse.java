package ledance.dto.rol.response;

/**
 * DTO de respuesta para un rol.
 */
public record RolResponse(
        Long id,
        String codigo,
        String nombre,
        String descripcionFuncional,
        Boolean activo,
        Boolean sistema,
        Boolean editable,
        int cantidadPermisos
) {}
