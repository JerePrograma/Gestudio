package gestudio.dto.usuario.response;

import gestudio.tenancy.TenantSummaryResponse;

import java.util.List;

public record UsuarioResponse(
        Long id,
        String nombreUsuario,
        List<String> roles,
        List<String> permisos,
        Boolean activo,
        TenantSummaryResponse tenantActivo,
        List<TenantSummaryResponse> tenantsDisponibles
) {
    public UsuarioResponse(Long id, String nombreUsuario, List<String> roles,
                           List<String> permisos, Boolean activo) {
        this(id, nombreUsuario, roles, permisos, activo, null, List.of());
    }
}
