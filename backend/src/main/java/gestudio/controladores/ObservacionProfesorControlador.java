package gestudio.controladores;

import gestudio.dto.reporte.observacion.ObservacionProfesorDTO;
import gestudio.dto.reporte.observacion.ObservacionProfesorRequest;
import gestudio.servicios.observaciones.ObservacionProfesorServicio;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDate;
import java.util.List;

@RestController
@RequestMapping("/api/observaciones-profesores")
public class ObservacionProfesorControlador {

    private final ObservacionProfesorServicio observacionProfesorServicio;

    public ObservacionProfesorControlador(ObservacionProfesorServicio observacionProfesorServicio) {
        this.observacionProfesorServicio = observacionProfesorServicio;
    }

    /**
     * Crea una nueva observacion para un profesor.
     *
     * @param request contiene profesorId, fecha (en formato ISO) y observacion
     * @return el DTO de la observacion creada
     */
    @PostMapping
    public ObservacionProfesorDTO crearObservacion(
            @RequestBody ObservacionProfesorRequest request) {
        // Se parsea la fecha desde el request
        return observacionProfesorServicio.crearObservacion(
                request.profesorId(),
                LocalDate.parse(request.fecha()),
                request.observacion()
        );
    }

    /**
     * Elimina una observacion.
     *
     * @param id el id de la observacion a eliminar
     */
    @DeleteMapping("/{id}")
    public void eliminarObservacion(@PathVariable Long id) {
        observacionProfesorServicio.eliminarObservacion(id);
    }

    /**
     * Obtiene una observacion por su id.
     *
     * @param id el id de la observacion
     * @return el DTO de la observacion encontrada
     */
    @GetMapping("/{id}")
    public ObservacionProfesorDTO obtenerObservacion(@PathVariable Long id) {
        return observacionProfesorServicio.obtenerObservacion(id);
    }

    /**
     * Lista todas las observaciones.
     *
     * @return la lista de DTOs de observaciones
     */
    @GetMapping
    public List<ObservacionProfesorDTO> listarObservaciones() {
        return observacionProfesorServicio.listarObservaciones();
    }

    /**
     * Lista las observaciones de un profesor.
     *
     * @param profesorId el id del profesor
     * @return la lista de DTOs de observaciones del profesor
     */
    @GetMapping("/profesor/{profesorId}")
    public List<ObservacionProfesorDTO> listarObservacionesPorProfesor(@PathVariable Long profesorId) {
        return observacionProfesorServicio.listarObservacionesPorProfesor(profesorId);
    }

    /**
     * Lista las observaciones en un rango de fechas.
     *
     * @param inicio fecha de inicio (formato ISO)
     * @param fin    fecha de fin (formato ISO)
     * @return la lista de DTOs de observaciones en el rango indicado
     */
    @GetMapping("/fechas")
    public List<ObservacionProfesorDTO> listarObservacionesEntreFechas(
            @RequestParam String inicio,
            @RequestParam String fin) {

        LocalDate fechaInicio = LocalDate.parse(inicio);
        LocalDate fechaFin = LocalDate.parse(fin);
        return observacionProfesorServicio.listarObservacionesEntreFechas(fechaInicio, fechaFin);
    }

    /**
     * Lista las observaciones de un profesor en un mes especifico.
     *
     * @param profesorId el id del profesor
     * @param mes        el mes (1-12)
     * @param anio       el año
     * @return la lista de DTOs de observaciones para ese profesor y mes
     */
    @GetMapping("/profesor/{profesorId}/mes")
    public List<ObservacionProfesorDTO> listarObservacionesMensuales(
            @PathVariable Long profesorId,
            @RequestParam int mes,
            @RequestParam int anio) {

        return observacionProfesorServicio.listarObservacionesMensuales(profesorId, mes, anio);
    }
}
