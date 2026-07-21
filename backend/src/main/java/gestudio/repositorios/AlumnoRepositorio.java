package gestudio.repositorios;

import gestudio.entidades.Alumno;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface AlumnoRepositorio extends JpaRepository<Alumno, Long> {

    boolean existsByNombreIgnoreCaseAndApellidoIgnoreCase(String nombre, String apellido);

    // Nuevo método para buscar solo por ID si está activo
    Optional<Alumno> findByIdAndActivoTrue(Long id);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select a from Alumno a where a.id = :id and a.activo = true")
    Optional<Alumno> findActivoByIdForUpdate(@Param("id") Long id);

    // Búsqueda operativa por referencias humanas, únicamente sobre alumnos activos.
    @Query("""
      SELECT a
        FROM Alumno a
       WHERE a.activo = true
         AND (
              LOWER(a.nombre) LIKE LOWER(CONCAT('%', :nombre, '%'))
           OR LOWER(COALESCE(a.apellido, '')) LIKE LOWER(CONCAT('%', :nombre, '%'))
           OR LOWER(CONCAT(CONCAT(a.nombre, ' '), COALESCE(a.apellido, '')))
                LIKE LOWER(CONCAT('%', :nombre, '%'))
           OR LOWER(CONCAT(CONCAT(COALESCE(a.apellido, ''), ' '), a.nombre))
                LIKE LOWER(CONCAT('%', :nombre, '%'))
           OR LOWER(COALESCE(a.documento, '')) LIKE LOWER(CONCAT('%', :nombre, '%'))
         )
      """)
    Page<Alumno> buscarPorNombreCompleto(@Param("nombre") String nombre, Pageable pageable);
}
