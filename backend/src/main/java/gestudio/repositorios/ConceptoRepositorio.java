package gestudio.repositorios;

import gestudio.dto.pago.PagoMapper;
import gestudio.entidades.Concepto;
import gestudio.entidades.SubConcepto;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Collection;
import java.util.List;
import java.util.Optional;

@Repository
public interface ConceptoRepositorio extends JpaRepository<Concepto, Long> {
    List<Concepto> findBySubConceptoId(Long subConceptoId);

    Optional<Concepto> findByDescripcionIgnoreCase(String descripcion);

    List<Concepto>   findByDescripcionInIgnoreCase(List<String> descripciones);

    Optional<Concepto> findFirstByDescripcionContainingIgnoreCase(String descripcion);

    Optional<Concepto> findFirstBySubConceptoId(Long subId);
}
