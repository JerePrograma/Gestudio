package gestudio.controladores;

import jakarta.validation.Valid;
import gestudio.dto.credito.request.CreditoAjusteRequest;
import gestudio.dto.credito.request.CreditoConsumoRequest;
import gestudio.dto.credito.request.CreditoReversionRequest;
import gestudio.dto.credito.response.MovimientoCreditoResponse;
import gestudio.entidades.Usuario;
import gestudio.servicios.credito.CreditoServicio;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/creditos")
public class CreditoControlador {
    private final CreditoServicio creditos;

    public CreditoControlador(CreditoServicio creditos) {
        this.creditos = creditos;
    }

    @PostMapping("/consumos")
    public ResponseEntity<MovimientoCreditoResponse> consumir(@Valid @RequestBody CreditoConsumoRequest request,
                                                               @AuthenticationPrincipal Usuario usuario) {
        return ResponseEntity.status(HttpStatus.CREATED).body(creditos.consumir(request, usuario));
    }

    @PostMapping("/consumos/{id}/reversion")
    public MovimientoCreditoResponse revertir(@PathVariable Long id,
                                               @Valid @RequestBody CreditoReversionRequest request,
                                               @AuthenticationPrincipal Usuario usuario) {
        return creditos.revertirConsumo(id, request, usuario);
    }

    @PostMapping("/ajustes")
    public ResponseEntity<MovimientoCreditoResponse> ajustar(@Valid @RequestBody CreditoAjusteRequest request,
                                                              @AuthenticationPrincipal Usuario usuario) {
        return ResponseEntity.status(HttpStatus.CREATED).body(creditos.ajustar(request, usuario));
    }

    @GetMapping("/alumno/{alumnoId}/saldo")
    public String saldo(@PathVariable Long alumnoId) {
        return creditos.saldo(alumnoId);
    }
}
