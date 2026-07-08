package gestudio.repositorios;

import gestudio.entidades.Notificacion;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDate;
import java.util.List;

public interface NotificacionRepositorio extends JpaRepository<Notificacion, Long> {
    boolean existsByDedupKey(String dedupKey);
    List<Notificacion> findByTipoAndFechaNegocioOrderById(String tipo, LocalDate fechaNegocio);
}
