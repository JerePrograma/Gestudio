package gestudio.repositorios;

import gestudio.entidades.Salon;
import org.springframework.data.jpa.repository.JpaRepository;

public interface SalonRepositorio extends JpaRepository<Salon, Long> {
}