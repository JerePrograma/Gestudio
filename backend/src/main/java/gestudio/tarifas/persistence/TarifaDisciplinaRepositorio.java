package gestudio.tarifas.persistence;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

public interface TarifaDisciplinaRepositorio extends JpaRepository<TarifaDisciplina, Long> {
    Optional<TarifaDisciplina> findFirstByDisciplinaIdAndVigenteDesdeLessThanEqualOrderByVigenteDesdeDesc(
            Long disciplinaId, LocalDate fecha);
    List<TarifaDisciplina> findByDisciplinaIdOrderByVigenteDesdeDesc(Long disciplinaId);
    boolean existsByDisciplinaIdAndVigenteDesde(Long disciplinaId, LocalDate vigenteDesde);
    @Query(value = "SELECT EXISTS(SELECT 1 FROM cargo_liquidaciones WHERE tarifa_disciplina_id = :id)", nativeQuery = true)
    boolean estaUtilizada(@Param("id") Long id);
}
