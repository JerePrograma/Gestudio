package gestudio.controladores;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.PositiveOrZero;
import gestudio.dto.egreso.request.EgresoAnulacionRequest;
import gestudio.dto.egreso.request.EgresoRegistroRequest;
import gestudio.dto.egreso.response.EgresoResponse;
import gestudio.dto.PageResponse;
import gestudio.entidades.Usuario;
import gestudio.servicios.egreso.EgresoServicio;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.RequestParam;

import java.util.List;

@RestController
@RequestMapping("/api/egresos")
@Validated
public class EgresoControlador {
    private final EgresoServicio egresos;

    public EgresoControlador(EgresoServicio egresos) {
        this.egresos = egresos;
    }

    @PostMapping
    public EgresoResponse registrar(@Valid @RequestBody EgresoRegistroRequest request,
                                    @AuthenticationPrincipal Usuario usuario) {
        return egresos.agregarEgreso(request, usuario);
    }

    @PostMapping("/{id}/anulacion")
    public EgresoResponse anular(@PathVariable Long id,
                                 @Valid @RequestBody EgresoAnulacionRequest request,
                                 @AuthenticationPrincipal Usuario usuario) {
        return egresos.anular(id, request, usuario);
    }

    @GetMapping("/{id}")
    public EgresoResponse obtener(@PathVariable Long id) {
        return egresos.obtenerEgresoPorId(id);
    }

    @GetMapping
    public PageResponse<EgresoResponse> listar(
            @RequestParam(defaultValue = "0") @PositiveOrZero int page,
            @RequestParam(defaultValue = "50") @Min(1) @Max(200) int size) {
        return PageResponse.from(egresos.listarEgresos(
                PageRequest.of(page, size, Sort.by(Sort.Direction.DESC, "fecha", "id"))));
    }
}
