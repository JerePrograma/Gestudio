package gestudio.repositorios;

import gestudio.entidades.MetodoPago;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface MetodoPagoRepositorio extends JpaRepository<MetodoPago, Long> {

    List<MetodoPago> findByActivoTrue();

    MetodoPago findByDescripcionContainingIgnoreCase(String efectivo);
}