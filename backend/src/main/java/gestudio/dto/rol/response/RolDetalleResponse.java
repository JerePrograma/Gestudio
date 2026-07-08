package gestudio.dto.rol.response;

import gestudio.dto.permiso.response.PermisoResponse;

import java.util.List;

public record RolDetalleResponse(
        Long id,
        String codigo,
        String nombre,
        String descripcionFuncional,
        Boolean activo,
        Boolean sistema,
        Boolean editable,
        List<PermisoResponse> permisos
) {
}
