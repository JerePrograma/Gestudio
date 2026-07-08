package ledance.controladores;

import ledance.dto.rol.response.RolResponse;
import ledance.dto.rol.response.RolDetalleResponse;
import ledance.dto.rol.request.RolRegistroRequest;
import ledance.dto.rol.request.RolModificacionRequest;
import ledance.dto.rol.request.RolPermisosRequest;
import ledance.entidades.Usuario;
import ledance.servicios.rol.RolServicio;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import org.springframework.security.core.annotation.AuthenticationPrincipal;

@RestController
@RequestMapping("/api/roles")
@Validated
public class RolControlador {

    private final RolServicio rolService;

    public RolControlador(RolServicio rolService) {
        this.rolService = rolService;
    }

    @GetMapping("/{id}")
    public ResponseEntity<RolDetalleResponse> obtenerRolPorId(@PathVariable Long id) {
        RolDetalleResponse response = rolService.obtenerRolPorId(id);
        return ResponseEntity.ok(response);
    }

    @GetMapping
    public ResponseEntity<List<RolResponse>> listarRoles() {
        List<RolResponse> respuesta = rolService.listarRoles();
        return ResponseEntity.ok(respuesta);
    }

    @PostMapping
    public ResponseEntity<RolDetalleResponse> crear(@RequestBody @Validated RolRegistroRequest request,
                                                     @AuthenticationPrincipal Usuario actor) {
        return ResponseEntity.ok(rolService.crear(request, actor));
    }

    @PutMapping("/{id}")
    public ResponseEntity<RolDetalleResponse> modificar(@PathVariable Long id,
                                                         @RequestBody @Validated RolModificacionRequest request,
                                                         @AuthenticationPrincipal Usuario actor) {
        return ResponseEntity.ok(rolService.modificar(id, request, actor));
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> desactivar(@PathVariable Long id, @AuthenticationPrincipal Usuario actor) {
        rolService.desactivar(id, actor);
        return ResponseEntity.noContent().build();
    }

    @PutMapping("/{id}/permisos")
    public ResponseEntity<RolDetalleResponse> asignarPermisos(@PathVariable Long id,
                                                               @RequestBody @Validated RolPermisosRequest request,
                                                               @AuthenticationPrincipal Usuario actor) {
        return ResponseEntity.ok(rolService.asignarPermisos(id, request, actor));
    }
}
