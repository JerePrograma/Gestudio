package ledance.controladores;

import jakarta.validation.Valid;
import ledance.dto.rol.request.RolModificacionRequest;
import ledance.dto.rol.request.RolRegistroRequest;
import ledance.dto.rol.response.RolResponse;
import ledance.entidades.Usuario;
import ledance.servicios.rol.RolServicio;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.*;

import java.net.URI;
import java.util.List;

@RestController
@RequestMapping("/api/roles")
@Validated
public class RolControlador {

    private final RolServicio rolService;

    public RolControlador(RolServicio rolService) {
        this.rolService = rolService;
    }

    @GetMapping("/{id}")
    public ResponseEntity<RolResponse> obtenerRolPorId(@PathVariable Long id) {
        RolResponse response = rolService.obtenerRolPorId(id);
        return ResponseEntity.ok(response);
    }

    @GetMapping
    public ResponseEntity<List<RolResponse>> listarRoles() {
        return ResponseEntity.ok(rolService.listarRoles());
    }

    @PostMapping
    public ResponseEntity<RolResponse> crearRol(@Valid @RequestBody RolRegistroRequest request,
                                                @AuthenticationPrincipal Usuario actor) {
        RolResponse response = rolService.crearRol(request, actor);
        return ResponseEntity.created(URI.create("/api/roles/" + response.id())).body(response);
    }

    @PutMapping("/{id}")
    public ResponseEntity<RolResponse> actualizarRol(@PathVariable Long id,
                                                     @Valid @RequestBody RolModificacionRequest request,
                                                     @AuthenticationPrincipal Usuario actor) {
        return ResponseEntity.ok(rolService.actualizarRol(id, request, actor));
    }

    @PostMapping("/{id}/clonar")
    public ResponseEntity<RolResponse> clonarRol(@PathVariable Long id,
                                                 @Valid @RequestBody RolRegistroRequest request,
                                                 @AuthenticationPrincipal Usuario actor) {
        RolResponse response = rolService.clonarRol(id, request, actor);
        return ResponseEntity.created(URI.create("/api/roles/" + response.id())).body(response);
    }
}