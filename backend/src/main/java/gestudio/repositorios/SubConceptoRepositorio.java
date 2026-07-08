package gestudio.repositorios;

import gestudio.entidades.Concepto;
import gestudio.entidades.SubConcepto;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.stereotype.Repository;

import java.util.Collection;
import java.util.List;
import java.util.Optional;

@Repository
public interface SubConceptoRepositorio extends JpaRepository<SubConcepto, Long> {

    @Query("SELECT s FROM SubConcepto s WHERE LOWER(s.descripcion) LIKE LOWER(CONCAT('%', ?1, '%'))")
    List<SubConcepto> buscarPorDescripcion(String descripcion);

    Optional<SubConcepto> findByDescripcionIgnoreCase(String descripcion);

    List<SubConcepto> findByDescripcionInIgnoreCase(List<String> descripciones);
}
