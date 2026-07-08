package gestudio.tarifas.persistence;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

public interface CondicionEconomicaRepositorio extends JpaRepository<CondicionEconomicaInscripcion, Long> {
    Optional<CondicionEconomicaInscripcion> findFirstByInscripcionIdAndVigenteDesdeLessThanEqualOrderByVigenteDesdeDesc(
            Long inscripcionId, LocalDate fecha);
    List<CondicionEconomicaInscripcion> findByInscripcionIdOrderByVigenteDesdeDesc(Long inscripcionId);
    boolean existsByInscripcionIdAndVigenteDesde(Long inscripcionId, LocalDate vigenteDesde);
    @Query(value = "SELECT EXISTS(SELECT 1 FROM cargo_liquidaciones WHERE condicion_inscripcion_id = :id)", nativeQuery = true)
    boolean estaUtilizada(@Param("id") Long id);
}
