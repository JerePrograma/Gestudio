package gestudio.repositorios;

import gestudio.entidades.Alumno;
import gestudio.entidades.Disciplina;
import gestudio.entidades.Profesor;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface ProfesorRepositorio extends JpaRepository<Profesor, Long> {

    boolean existsByNombreAndApellido(String nombre, String apellido);

    List<Profesor> findByActivoTrue();

    @Query("SELECT d FROM Disciplina d WHERE d.profesor.id = :profesorId")
    List<Disciplina> findDisciplinasPorProfesor(@Param("profesorId") Long profesorId);

    @Query("SELECT p FROM Profesor p " +
            "WHERE LOWER(CONCAT(p.nombre, ' ', p.apellido)) " +
            "LIKE LOWER(CONCAT('%', :nombre, '%'))")
    List<Profesor> buscarPorNombreCompleto(@Param("nombre") String nombre);

    @Query("""
              SELECT I.alumno
                FROM Inscripcion I
               WHERE I.disciplina.profesor.id = :profesorId
                 AND I.alumno.activo = true
            """)
    List<Alumno> findAlumnosPorProfesor(@Param("profesorId") Long profesorId);
}