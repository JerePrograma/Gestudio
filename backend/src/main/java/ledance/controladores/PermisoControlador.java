package ledance.controladores;

import ledance.dto.permiso.response.PermisoResponse;
import ledance.servicios.permiso.PermisoServicio;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/permisos")
public class PermisoControlador {
    private final PermisoServicio permisos;

    public PermisoControlador(PermisoServicio permisos) {
        this.permisos = permisos;
    }

    @GetMapping
    public ResponseEntity<List<PermisoResponse>> listar(@RequestParam(required = false) String modulo) {
        return ResponseEntity.ok(permisos.listar(modulo));
    }
}
