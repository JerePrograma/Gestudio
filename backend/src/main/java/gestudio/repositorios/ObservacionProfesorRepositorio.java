package gestudio.repositorios;

import gestudio.entidades.ObservacionProfesor;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.time.LocalDate;
import java.util.List;

@Repository
public interface ObservacionProfesorRepositorio extends JpaRepository<ObservacionProfesor, Long> {
    List<ObservacionProfesor> findByProfesorId(Long profesorId);
    List<ObservacionProfesor> findByFechaBetween(LocalDate inicio, LocalDate fin);
    List<ObservacionProfesor> findByProfesorIdAndFechaBetween(Long profesorId, LocalDate inicio, LocalDate fin);

}
