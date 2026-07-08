package gestudio.controladores;

import gestudio.dto.matricula.response.MatriculaResponse;
import gestudio.servicios.matricula.MatriculaServicio;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/matriculas")
public class MatriculaControlador {
    private final MatriculaServicio matriculas;

    public MatriculaControlador(MatriculaServicio matriculas) {
        this.matriculas = matriculas;
    }

    @PostMapping("/alumno/{alumnoId}")
    public MatriculaResponse generar(@PathVariable Long alumnoId, @RequestParam int anio) {
        return matriculas.obtenerOMarcarPendienteMatricula(alumnoId, anio);
    }

    @GetMapping("/alumno/{alumnoId}")
    public MatriculaResponse obtener(@PathVariable Long alumnoId, @RequestParam int anio) {
        return matriculas.obtener(alumnoId, anio);
    }

    @PostMapping("/{id}/anulacion")
    public MatriculaResponse anular(@PathVariable Long id) {
        return matriculas.anular(id);
    }
}
