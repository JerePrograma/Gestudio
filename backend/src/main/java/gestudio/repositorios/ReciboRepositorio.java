package gestudio.repositorios;

import gestudio.entidades.Recibo;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface ReciboRepositorio extends JpaRepository<Recibo, Long> {
    Optional<Recibo> findByPagoId(Long pagoId);
}
