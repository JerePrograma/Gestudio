package gestudio.repositorios;

import gestudio.entidades.AsistenciaDiaria;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;
import java.time.LocalDate;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

@Repository
public interface AsistenciaDiariaRepositorio extends JpaRepository<AsistenciaDiaria, Long> {

    // Recupera las asistencias diarias filtradas por disciplina (a traves de la planilla)
    Page<AsistenciaDiaria> findByAsistenciaAlumnoMensual_AsistenciaMensual_Disciplina_IdAndFecha(Long disciplinaId, LocalDate fecha, Pageable pageable);

    // Busca una asistencia por id, alumno (a traves del registro) y fecha
    Optional<AsistenciaDiaria> findByIdAndAsistenciaAlumnoMensual_Inscripcion_Alumno_IdAndFecha(Long id, Long alumnoId, LocalDate fecha);

    @Query("SELECT a.asistenciaAlumnoMensual.inscripcion.alumno.id, COUNT(a) " +
            "FROM AsistenciaDiaria a " +
            "WHERE a.asistenciaAlumnoMensual.asistenciaMensual.disciplina.id = :disciplinaId " +
            "AND a.fecha BETWEEN :fechaInicio AND :fechaFin " +
            "GROUP BY a.asistenciaAlumnoMensual.inscripcion.alumno.id")
    List<Object[]> contarAsistenciasPorAlumnoRaw(@Param("disciplinaId") Long disciplinaId,
                                                 @Param("fechaInicio") LocalDate fechaInicio,
                                                 @Param("fechaFin") LocalDate fechaFin);

    default Map<Long, Integer> contarAsistenciasPorAlumno(Long disciplinaId, LocalDate fechaInicio, LocalDate fechaFin) {
        List<Object[]> resultados = contarAsistenciasPorAlumnoRaw(disciplinaId, fechaInicio, fechaFin);
        Map<Long, Integer> mapa = new HashMap<>();
        for (Object[] row : resultados) {
            Long alumnoId = (Long) row[0];
            Integer count = ((Long) row[1]).intValue();
            mapa.put(alumnoId, count);
        }
        return mapa;
    }

    // Verifica si ya existe una asistencia para un alumno en una fecha
    boolean existsByAsistenciaAlumnoMensual_Inscripcion_Alumno_IdAndFecha(Long alumnoId, LocalDate fecha);

    // Busca una asistencia para un alumno en una fecha
    Optional<AsistenciaDiaria> findByAsistenciaAlumnoMensual_Inscripcion_Alumno_IdAndFecha(Long alumnoId, LocalDate fecha);

    // Recupera todas las asistencias asociadas a una planilla (a traves de AsistenciaAlumnoMensual)
    List<AsistenciaDiaria> findByAsistenciaAlumnoMensual_AsistenciaMensual_Id(Long asistenciaMensualId);

    List<AsistenciaDiaria> findByAsistenciaAlumnoMensual_AsistenciaMensual_IdAndFechaGreaterThanEqual(Long asistenciaMensualId, LocalDate fecha);

    // Verifica si ya existen registros para un alumno en una planilla
    boolean existsByAsistenciaAlumnoMensual_Inscripcion_Alumno_IdAndAsistenciaAlumnoMensual_AsistenciaMensual_Id(Long alumnoId, Long planillaId);

    List<AsistenciaDiaria> findByAsistenciaAlumnoMensual_IdAndFechaGreaterThanEqual(Long asistenciaAlumnoMensualId, LocalDate fechaCambio);

    boolean existsByAsistenciaAlumnoMensualId(Long id);

    boolean existsByAsistenciaAlumnoMensualIdAndFecha(Long id, LocalDate fecha);

    Optional<AsistenciaDiaria> findByAsistenciaAlumnoMensualIdAndFecha(Long id, LocalDate fecha);

    List<AsistenciaDiaria> findByAsistenciaAlumnoMensualId(Long id);
}
