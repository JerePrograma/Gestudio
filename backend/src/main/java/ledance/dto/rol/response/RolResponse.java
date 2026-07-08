package ledance.dto.rol.response;

import java.util.List;

public record RolResponse(
        Long id,
        String codigo,
        String nombre,
        String descripcion,
        String descripcionFuncional,
        Boolean activo,
        Boolean sistema,
        Boolean editable,
        List<PermisoResponse> permisos
) {
}