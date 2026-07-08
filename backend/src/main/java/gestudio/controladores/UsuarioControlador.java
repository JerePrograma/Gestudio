package gestudio.controladores;

import jakarta.validation.Valid;
import gestudio.dto.usuario.request.UsuarioModificacionRequest;
import gestudio.dto.usuario.request.UsuarioRegistroRequest;
import gestudio.dto.usuario.response.UsuarioResponse;
import gestudio.entidades.Usuario;
import gestudio.servicios.usuario.UsuarioServicio;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.*;

import java.net.URI;
import java.util.List;

@RestController
@RequestMapping("/api/usuarios")
@Validated
public class UsuarioControlador {

    private final UsuarioServicio usuarioService;

    public UsuarioControlador(UsuarioServicio usuarioService) {
        this.usuarioService = usuarioService;
    }

    @PostMapping("/registro")
    public ResponseEntity<UsuarioResponse> registrarUsuario(
            @Valid @RequestBody UsuarioRegistroRequest datosRegistro,
            @AuthenticationPrincipal Usuario actor
    ) {
        UsuarioResponse response = usuarioService.registrarUsuario(datosRegistro, actor);

        return ResponseEntity
                .created(URI.create("/api/usuarios/" + response.id()))
                .body(response);
    }

    @PutMapping("/{id}")
    public ResponseEntity<UsuarioResponse> editarUsuario(
            @PathVariable Long id,
            @Valid @RequestBody UsuarioModificacionRequest modificacionRequest,
            @AuthenticationPrincipal Usuario actor
    ) {
        return ResponseEntity.ok(usuarioService.editarUsuario(id, modificacionRequest, actor));
    }

    @GetMapping("/{id}")
    public ResponseEntity<UsuarioResponse> obtenerUsuario(@PathVariable Long id) {
        return ResponseEntity.ok(usuarioService.obtenerUsuario(id));
    }

    @GetMapping
    public ResponseEntity<List<UsuarioResponse>> listarUsuarios(
            @RequestParam(required = false) String rol,
            @RequestParam(required = false) Boolean activo
    ) {
        List<UsuarioResponse> response = usuarioService.listarUsuarios(rol, activo)
                .stream()
                .map(usuarioService::convertirAUsuarioResponse)
                .toList();

        return ResponseEntity.ok(response);
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> eliminarUsuario(
            @PathVariable Long id,
            @AuthenticationPrincipal Usuario actor
    ) {
        usuarioService.eliminarUsuario(id, actor);
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/perfil")
    public ResponseEntity<UsuarioResponse> obtenerPerfil(@AuthenticationPrincipal Usuario usuario) {
        if (usuario == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }

        return ResponseEntity.ok(usuarioService.convertirAUsuarioResponse(usuario));
    }
}