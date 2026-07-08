package gestudio.repositorios;

import gestudio.entidades.EstadoInscripcion;
import gestudio.entidades.Inscripcion;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.jpa.repository.Lock;
import jakarta.persistence.LockModeType;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;
import java.util.List;
import java.util.Collection;
import java.util.Optional;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;

@Repository
public interface InscripcionRepositorio extends JpaRepository<Inscripcion, Long> {

    @EntityGraph(attributePaths = {"alumno", "disciplina", "bonificacion"})
    @Query(value = """
            SELECT I FROM Inscripcion I
            WHERE :filtro = ''
               OR LOWER(CONCAT(I.alumno.nombre, ' ', I.alumno.apellido, ' ', I.disciplina.nombre))
                  LIKE LOWER(CONCAT('%', :filtro, '%'))
            """, countQuery = """
            SELECT count(I) FROM Inscripcion I
            WHERE :filtro = ''
               OR LOWER(CONCAT(I.alumno.nombre, ' ', I.alumno.apellido, ' ', I.disciplina.nombre))
                  LIKE LOWER(CONCAT('%', :filtro, '%'))
            """)
    Page<Inscripcion> findAllWithDetails(@Param("filtro") String filtro, Pageable pageable);

    List<Inscripcion> findAllByDisciplinaIdAndEstado(Long disciplinaId, EstadoInscripcion estado);

    List<Inscripcion> findAllByAlumno_IdAndEstado(Long alumnoId, EstadoInscripcion estado);

    List<Inscripcion> findByEstado(EstadoInscripcion estado);

    @Query(value = """
            SELECT i.id FROM inscripciones i
            JOIN alumnos a ON a.id = i.alumno_id
            WHERE i.estado = 'ACTIVA' AND a.activo = true
            ORDER BY i.id
            FOR UPDATE OF i
            """, nativeQuery = true)
    List<Long> lockActiveIdsForScheduler();

    @EntityGraph(attributePaths = {"alumno", "disciplina", "bonificacion"})
    @Query("select i from Inscripcion i where i.id in :ids order by i.id")
    List<Inscripcion> findAllForScheduler(@Param("ids") Collection<Long> ids);

    @Query("SELECT I.disciplina.nombre, SUM(I.disciplina.valorCuota) " +
            "FROM Inscripcion I " +
            "WHERE I.disciplina.id = :disciplinaId " +
            "GROUP BY I.disciplina.nombre")
    List<Object[]> obtenerRecaudacionPorDisciplina(@Param("disciplinaId") Long disciplinaId);

    Optional<Inscripcion> findByAlumno_IdAndEstado(Long alumnoId, EstadoInscripcion estado);

    Optional<Inscripcion> findByAlumnoIdAndDisciplinaIdAndEstado(Long alumnoId, Long disciplinaId, EstadoInscripcion estado);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select i from Inscripcion i where i.id = :id")
    Optional<Inscripcion> findByIdForUpdate(@Param("id") Long id);
}
