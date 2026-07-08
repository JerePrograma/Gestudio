package gestudio.controladores;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.PositiveOrZero;
import gestudio.dto.PageResponse;
import gestudio.dto.cargo.response.CargoResponse;
import gestudio.dto.stock.request.ReversionStockRequest;
import gestudio.dto.stock.request.StockRegistroRequest;
import gestudio.dto.stock.request.VentaStockRequest;
import gestudio.dto.stock.response.StockResponse;
import gestudio.entidades.Usuario;
import gestudio.servicios.stock.StockServicio;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/stocks")
@Validated
public class StockControlador {

    private final StockServicio stocks;

    public StockControlador(StockServicio stocks) {
        this.stocks = stocks;
    }

    @PostMapping
    public StockResponse crear(@Valid @RequestBody StockRegistroRequest request,
                               @AuthenticationPrincipal Usuario usuario) {
        return stocks.crearStock(request, usuario);
    }

    @GetMapping
    public PageResponse<StockResponse> listar(
            @RequestParam(defaultValue = "0") @PositiveOrZero int page,
            @RequestParam(defaultValue = "50") @Min(1) @Max(200) int size) {
        return PageResponse.from(stocks.listarStocks(
                PageRequest.of(page, size, Sort.by("nombre", "id"))));
    }

    @GetMapping("/activos")
    public List<StockResponse> listarActivos() {
        return stocks.listarStocksActivos();
    }

    @GetMapping("/{id}")
    public StockResponse obtener(@PathVariable Long id) {
        return stocks.obtenerStockPorId(id);
    }

    @PutMapping("/{id}")
    public StockResponse actualizar(@PathVariable Long id,
                                    @Valid @RequestBody StockRegistroRequest request,
                                    @AuthenticationPrincipal Usuario usuario) {
        return stocks.actualizarStock(id, request, usuario);
    }

    @DeleteMapping("/{id}")
    public void darBaja(@PathVariable Long id,
                        @AuthenticationPrincipal Usuario usuario) {
        stocks.eliminarStock(id, usuario);
    }

    @PostMapping("/ventas")
    public CargoResponse vender(@Valid @RequestBody VentaStockRequest request,
                                @AuthenticationPrincipal Usuario usuario) {
        return stocks.vender(request, usuario);
    }

    @PostMapping("/ventas/{id}/reversion")
    public CargoResponse revertir(@PathVariable Long id,
                                  @Valid @RequestBody ReversionStockRequest request,
                                  @AuthenticationPrincipal Usuario usuario) {
        return stocks.revertirVenta(id, request, usuario);
    }
}