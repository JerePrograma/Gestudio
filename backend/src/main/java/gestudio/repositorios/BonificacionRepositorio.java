package gestudio.repositorios;

import gestudio.entidades.Bonificacion;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface BonificacionRepositorio extends JpaRepository<Bonificacion, Long> {
    List<Bonificacion> findByActivoTrue();

    boolean existsByDescripcion(String descripcion);
}