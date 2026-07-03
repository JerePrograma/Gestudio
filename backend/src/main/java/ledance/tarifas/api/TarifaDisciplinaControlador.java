package ledance.tarifas.api;

import jakarta.validation.Valid;
import ledance.entidades.Usuario;
import ledance.tarifas.application.TarifaDisciplinaServicio;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

import java.net.URI;
import java.util.List;

@RestController
@RequestMapping("/api/disciplinas/{disciplinaId}/tarifas")
public class TarifaDisciplinaControlador {
    private final TarifaDisciplinaServicio tarifas;

    public TarifaDisciplinaControlador(TarifaDisciplinaServicio tarifas) {
        this.tarifas = tarifas;
    }

    @GetMapping
    public List<TarifaDisciplinaResponse> listar(@PathVariable Long disciplinaId) {
        return tarifas.listar(disciplinaId);
    }

    @PostMapping
    public ResponseEntity<TarifaDisciplinaResponse> crear(
            @PathVariable Long disciplinaId,
            @Valid @RequestBody TarifaDisciplinaRequest request,
            @AuthenticationPrincipal Usuario actor) {
        TarifaDisciplinaResponse created = tarifas.crear(disciplinaId, request, actor);
        return ResponseEntity.created(URI.create("/api/disciplinas/" + disciplinaId
                + "/tarifas/" + created.id())).body(created);
    }
}
