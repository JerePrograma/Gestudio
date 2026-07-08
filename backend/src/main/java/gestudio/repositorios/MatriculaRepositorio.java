package gestudio.repositorios;

import gestudio.entidades.Matricula;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;
import java.util.Collection;
import java.util.List;

public interface MatriculaRepositorio extends JpaRepository<Matricula, Long> {
    Optional<Matricula> findByAlumnoIdAndAnio(Long alumnoId, Integer anio);
    List<Matricula> findByAlumnoIdInAndAnio(Collection<Long> alumnoIds, Integer anio);
}
