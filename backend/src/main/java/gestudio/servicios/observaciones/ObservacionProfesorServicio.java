package gestudio.servicios.observaciones;

import gestudio.dto.reporte.observacion.ObservacionProfesorDTO;
import gestudio.dto.reporte.observacion.ObservacionProfesorMapper;
import gestudio.entidades.ObservacionProfesor;
import gestudio.entidades.Profesor;
import gestudio.repositorios.ObservacionProfesorRepositorio;
import gestudio.repositorios.ProfesorRepositorio;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.util.List;
import java.util.stream.Collectors;

@Service
public class ObservacionProfesorServicio {

    private final ObservacionProfesorRepositorio observacionRepo;
    private final ProfesorRepositorio profesorRepo;
    private final ObservacionProfesorMapper observacionProfesorMapper;

    public ObservacionProfesorServicio(ObservacionProfesorRepositorio observacionRepo,
                                       ProfesorRepositorio profesorRepo, ObservacionProfesorMapper observacionProfesorMapper) {
        this.observacionRepo = observacionRepo;
        this.profesorRepo = profesorRepo;
        this.observacionProfesorMapper = observacionProfesorMapper;
    }

    /**
     * Crea una nueva observacion para un profesor.
     *
     * @param profesorId      el id del profesor
     * @param fecha           la fecha de la observacion
     * @param observacionText el texto de la observacion
     * @return el DTO de la observacion creada
     */
    @Transactional
    public ObservacionProfesorDTO crearObservacion(Long profesorId, LocalDate fecha, String observacionText) {
        Profesor profesor = profesorRepo.findById(profesorId)
                .orElseThrow(() -> new RuntimeException("Profesor no encontrado con id: " + profesorId));
        ObservacionProfesor obs = new ObservacionProfesor();
        obs.setProfesor(profesor);
        obs.setFecha(fecha);
        obs.setObservacion(observacionText);
        ObservacionProfesor saved = observacionRepo.save(obs);
        return observacionProfesorMapper.toDTO(saved);
    }

    /**
     * Actualiza una observacion existente.
     *
     * @param observacionId   el id de la observacion a actualizar
     * @param fecha           la nueva fecha
     * @param observacionText el nuevo texto de la observacion
     * @return el DTO de la observacion actualizada
     */
    @Transactional
    public ObservacionProfesorDTO actualizarObservacion(Long observacionId, LocalDate fecha, String observacionText) {
        ObservacionProfesor obs = observacionRepo.findById(observacionId)
                .orElseThrow(() -> new RuntimeException("Observacion no encontrada con id: " + observacionId));
        obs.setFecha(fecha);
        obs.setObservacion(observacionText);
        ObservacionProfesor updated = observacionRepo.save(obs);
        return observacionProfesorMapper.toDTO(updated);
    }

    /**
     * Elimina una observacion por su id.
     *
     * @param observacionId el id de la observacion a eliminar
     */
    @Transactional
    public void eliminarObservacion(Long observacionId) {
        ObservacionProfesor observacion = observacionRepo.findById(observacionId)
                .orElseThrow(() -> new RuntimeException("Observacion no encontrada con id: " + observacionId));
        observacion.setActiva(false);
    }

    /**
     * Obtiene una observacion por su id.
     *
     * @param observacionId el id de la observacion
     * @return el DTO de la observacion encontrada
     */
    public ObservacionProfesorDTO obtenerObservacion(Long observacionId) {
        ObservacionProfesor obs = observacionRepo.findById(observacionId)
                .orElseThrow(() -> new RuntimeException("Observacion no encontrada con id: " + observacionId));
        return observacionProfesorMapper.toDTO(obs);
    }

    /**
     * Lista todas las observaciones.
     *
     * @return la lista de DTOs de observaciones
     */
    public List<ObservacionProfesorDTO> listarObservaciones() {
        return observacionRepo.findAll().stream()
                .map(observacionProfesorMapper::toDTO)
                .collect(Collectors.toList());
    }

    /**
     * Lista las observaciones de un profesor.
     *
     * @param profesorId el id del profesor
     * @return la lista de DTOs de observaciones del profesor
     */
    public List<ObservacionProfesorDTO> listarObservacionesPorProfesor(Long profesorId) {
        return observacionRepo.findByProfesorId(profesorId).stream()
                .map(observacionProfesorMapper::toDTO)
                .collect(Collectors.toList());
    }

    /**
     * Lista las observaciones en un rango de fechas.
     *
     * @param inicio fecha de inicio (inclusive)
     * @param fin    fecha de fin (inclusive)
     * @return la lista de DTOs de observaciones en el rango indicado
     */
    public List<ObservacionProfesorDTO> listarObservacionesEntreFechas(LocalDate inicio, LocalDate fin) {
        return observacionRepo.findByFechaBetween(inicio, fin).stream()
                .map(observacionProfesorMapper::toDTO)
                .collect(Collectors.toList());
    }

    /**
     * Lista las observaciones de un profesor en un mes especifico.
     *
     * @param profesorId el id del profesor
     * @param mes        mes (1-12)
     * @param anio       año
     * @return la lista de DTOs de observaciones para ese profesor y mes
     */
    public List<ObservacionProfesorDTO> listarObservacionesMensuales(Long profesorId, int mes, int anio) {
        LocalDate inicio = LocalDate.of(anio, mes, 1);
        LocalDate fin = inicio.withDayOfMonth(inicio.lengthOfMonth());
        return observacionRepo.findByProfesorIdAndFechaBetween(profesorId, inicio, fin).stream()
                .map(observacionProfesorMapper::toDTO)
                .collect(Collectors.toList());
    }
}
