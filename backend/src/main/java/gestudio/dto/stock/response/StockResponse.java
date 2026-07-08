package gestudio.dto.stock.response;

public record StockResponse(
        Long id,
        String nombre,
        String precio,
        Integer stock,
        Boolean requiereControlDeStock,
        Boolean activo,
        String codigoBarras
) {
}
