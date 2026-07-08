package ledance.controladores;

import ledance.dto.rol.response.PermisoResponse;
import ledance.servicios.rol.PermisoServicio;
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
    public ResponseEntity<List<PermisoResponse>> listarPermisos() {
        return ResponseEntity.ok(permisos.listarPermisos());
    }
}