package gestudio.repositorios;

import gestudio.entidades.AsistenciaMensual;
import gestudio.entidades.Inscripcion;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.Collection;
import java.util.List;
import java.util.Optional;

@Repository
public interface AsistenciaMensualRepositorio extends JpaRepository<AsistenciaMensual, Long> {

    // Busca la planilla para una disciplina, mes y año dados
    Optional<AsistenciaMensual> findByDisciplina_IdAndMesAndAnio(Long disciplinaId, int mes, int anio);

    @Query("SELECT am FROM AsistenciaMensual am " +
            "JOIN FETCH am.asistenciasAlumnoMensual aam " +
            "JOIN FETCH aam.inscripcion I " +
            "JOIN FETCH I.alumno " +
            "WHERE am.disciplina.id = :disciplinaId " +
            "AND am.mes = :mes AND am.anio = :anio")
    Optional<AsistenciaMensual> findByDisciplina_IdAndMesAndAnioFetch(@Param("disciplinaId") Long disciplinaId,
                                                                      @Param("mes") int mes,
                                                                      @Param("anio") int anio);

    // Para listar planillas (la misma consulta que en buscarAsistencias)
    @Query("SELECT a FROM AsistenciaMensual a " +
            "WHERE (:profesorId IS NULL OR a.disciplina.profesor.id = :profesorId) " +
            "AND (:disciplinaId IS NULL OR a.disciplina.id = :disciplinaId) " +
            "AND (:mes IS NULL OR a.mes = :mes) " +
            "AND (:anio IS NULL OR a.anio = :anio)")
    List<AsistenciaMensual> buscarPlanillas(@Param("profesorId") Long profesorId,
                                            @Param("disciplinaId") Long disciplinaId,
                                            @Param("mes") Integer mes,
                                            @Param("anio") Integer anio);

    List<AsistenciaMensual> findByDisciplinaId(Long id);
}
