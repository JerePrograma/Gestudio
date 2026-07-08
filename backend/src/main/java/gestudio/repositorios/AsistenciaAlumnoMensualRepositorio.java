package gestudio.repositorios;

import gestudio.entidades.AsistenciaAlumnoMensual;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface AsistenciaAlumnoMensualRepositorio extends JpaRepository<AsistenciaAlumnoMensual, Long> {

    // Obtiene el registro de asistencia mensual de un alumno a partir de su inscripcion y la planilla (asistencia mensual)
    Optional<AsistenciaAlumnoMensual> findByInscripcionIdAndAsistenciaMensualId(Long inscripcionId, Long asistenciaMensualId);

    // Verifica si existe un registro de asistencia para una inscripcion en una planilla dada
    boolean existsByInscripcionIdAndAsistenciaMensualId(Long inscripcionId, Long asistenciaMensualId);

    List<AsistenciaAlumnoMensual> findByInscripcionId(Long inscripcionId);
}
