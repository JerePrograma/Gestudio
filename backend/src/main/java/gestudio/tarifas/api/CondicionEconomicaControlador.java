package gestudio.tarifas.api;

import jakarta.validation.Valid;
import gestudio.entidades.Usuario;
import gestudio.tarifas.application.CondicionEconomicaServicio;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

import java.net.URI;
import java.util.List;

@RestController
@RequestMapping("/api/inscripciones/{inscripcionId}/condiciones-economicas")
public class CondicionEconomicaControlador {
    private final CondicionEconomicaServicio condiciones;

    public CondicionEconomicaControlador(CondicionEconomicaServicio condiciones) {
        this.condiciones = condiciones;
    }

    @GetMapping
    public List<CondicionEconomicaResponse> listar(@PathVariable Long inscripcionId) {
        return condiciones.listar(inscripcionId);
    }

    @PostMapping
    public ResponseEntity<CondicionEconomicaResponse> crear(
            @PathVariable Long inscripcionId,
            @Valid @RequestBody CondicionEconomicaRequest request,
            @AuthenticationPrincipal Usuario actor) {
        CondicionEconomicaResponse created = condiciones.crear(inscripcionId, request, actor);
        return ResponseEntity.created(URI.create("/api/inscripciones/" + inscripcionId
                + "/condiciones-economicas/" + created.id())).body(created);
    }
}
