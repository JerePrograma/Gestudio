package gestudio.repositorios;

import gestudio.entidades.Mensualidad;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;
import java.util.Collection;

public interface MensualidadRepositorio extends JpaRepository<Mensualidad, Long> {
    List<Mensualidad> findByInscripcionIdOrderByAnioDescMesDesc(Long inscripcionId);
    Optional<Mensualidad> findByInscripcionIdAndAnioAndMes(Long inscripcionId, Integer anio, Integer mes);
    List<Mensualidad> findByInscripcionIdInAndAnioAndMes(Collection<Long> inscripcionIds, Integer anio, Integer mes);
}
