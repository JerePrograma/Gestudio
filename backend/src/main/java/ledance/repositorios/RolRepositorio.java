package ledance.repositorios;

import ledance.entidades.Rol;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface RolRepositorio extends JpaRepository<Rol, Long> {
    Optional<Rol> findByDescripcion(String descripcion);

    boolean existsByDescripcion(String descripcion);

    List<Rol> findByActivoTrue();

    Optional<Rol> findByDescripcionIgnoreCase(String descripcion);

    Optional<Rol> findByCodigoIgnoreCase(String codigo);

    boolean existsByCodigoIgnoreCase(String codigo);

    List<Rol> findAllByOrderByNombreAsc();

}
