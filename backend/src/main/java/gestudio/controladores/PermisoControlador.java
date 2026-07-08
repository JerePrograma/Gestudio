package gestudio.controladores;

import gestudio.dto.rol.response.PermisoResponse;
import gestudio.servicios.permiso.PermisoServicio;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/permisos")
public class PermisoControlador {

    private final PermisoServicio permisos;

    public PermisoControlador(PermisoServicio permisos) {
        this.permisos = permisos;
    }

    @GetMapping
    public ResponseEntity<List<PermisoResponse>> listarPermisos(
            @RequestParam(required = false) String modulo
    ) {
        return ResponseEntity.ok(permisos.listarPermisos(modulo));
    }
}