package gestudio.controladores;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.PositiveOrZero;
import gestudio.dto.PageResponse;
import gestudio.dto.cargo.request.CargoConceptoRequest;
import gestudio.dto.cargo.response.CargoResponse;
import gestudio.entidades.Usuario;
import gestudio.servicios.cargo.CargoServicio;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/cargos")
@Validated
public class CargoControlador {

    private final CargoServicio cargos;

    public CargoControlador(CargoServicio cargos) {
        this.cargos = cargos;
    }

    @PostMapping("/concepto")
    public ResponseEntity<CargoResponse> crearPorConcepto(@Valid @RequestBody CargoConceptoRequest request,
                                                          @AuthenticationPrincipal Usuario usuario) {
        return ResponseEntity.status(HttpStatus.CREATED).body(cargos.crearPorConcepto(request, usuario));
    }

    @GetMapping("/{id}")
    public CargoResponse obtener(@PathVariable Long id) {
        return cargos.obtener(id);
    }

    @GetMapping("/alumno/{alumnoId}/pendientes")
    public PageResponse<CargoResponse> listarPendientes(
            @PathVariable Long alumnoId,
            @RequestParam(defaultValue = "0") @PositiveOrZero int page,
            @RequestParam(defaultValue = "50") @Min(1) @Max(200) int size) {
        return PageResponse.from(cargos.listarPendientes(
                alumnoId,
                PageRequest.of(page, size, Sort.by("fechaVencimiento", "id"))
        ));
    }

    @GetMapping("/vencidos")
    public PageResponse<CargoResponse> listarVencidos(
            @RequestParam(defaultValue = "0") @PositiveOrZero int page,
            @RequestParam(defaultValue = "50") @Min(1) @Max(200) int size) {
        return PageResponse.from(cargos.listarVencidos(
                PageRequest.of(page, size, Sort.by("fechaVencimiento", "id"))
        ));
    }
}