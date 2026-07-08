package ledance.dto.permiso.response;

import ledance.entidades.Permiso;

public record PermisoResponse(
        Long id,
        String codigo,
        String descripcion,
        String modulo,
        Boolean activo,
        Boolean sistema
) {
    public static PermisoResponse from(Permiso permiso) {
        return new PermisoResponse(permiso.getId(), permiso.getCodigo(), permiso.getDescripcion(),
                permiso.getModulo(), permiso.getActivo(), permiso.getSistema());
    }
}
