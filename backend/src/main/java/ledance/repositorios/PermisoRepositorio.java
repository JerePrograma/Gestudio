package ledance.repositorios;

import ledance.entidades.Permiso;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Collection;
import java.util.List;

@Repository
public interface PermisoRepositorio extends JpaRepository<Permiso, Long> {
    List<Permiso> findAllByOrderByModuloAscCodigoAsc();

    List<Permiso> findByModuloIgnoreCaseOrderByCodigoAsc(String modulo);

    List<Permiso> findByCodigoInAndActivoTrue(Collection<String> codigos);
}
