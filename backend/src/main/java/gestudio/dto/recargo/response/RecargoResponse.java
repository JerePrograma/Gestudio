package gestudio.dto.recargo.response;

public record RecargoResponse(
        Long id,
        String descripcion,
        String porcentaje,
        String valorFijo,
        Integer diaDelMesAplicacion,
        Boolean activo
) {
}
