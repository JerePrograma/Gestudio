package gestudio.repositorios;

import jakarta.persistence.LockModeType;
import gestudio.entidades.Cargo;
import gestudio.entidades.EstadoCargo;
import gestudio.entidades.TipoCargo;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

public interface CargoRepositorio extends JpaRepository<Cargo, Long> {
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select c from Cargo c where c.id in :ids order by c.id")
    List<Cargo> findAllByIdForUpdate(@Param("ids") List<Long> ids);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select c from Cargo c where c.id = :id")
    Optional<Cargo> findByIdForUpdate(@Param("id") Long id);

    Page<Cargo> findByAlumnoIdAndEstadoIn(Long alumnoId, List<EstadoCargo> estados, Pageable pageable);
    Page<Cargo> findByEstadoInAndFechaVencimientoBefore(List<EstadoCargo> estados, LocalDate fecha, Pageable pageable);
    Optional<Cargo> findByMensualidadId(Long mensualidadId);
    Optional<Cargo> findByMatriculaId(Long matriculaId);
    Optional<Cargo> findByIdempotencyKey(String idempotencyKey);
    Optional<Cargo> findByVentaStockId(Long ventaStockId);
    List<Cargo> findByTipoAndEstadoInAndFechaVencimientoBeforeOrderById(
            TipoCargo tipo, List<EstadoCargo> estados, LocalDate fecha);

    @Query("""
        select c from Cargo c
        join fetch c.alumno a
        join fetch c.mensualidad m
        join fetch m.inscripcion i
        join fetch i.disciplina d
        join fetch d.profesor p
        where c.tipo = :tipo
          and c.fechaEmision between :desde and :hasta
          and (:disciplinaId is null or d.id = :disciplinaId)
          and (:profesorId is null or p.id = :profesorId)
        order by c.fechaEmision, c.id
        """)
    List<Cargo> findMensualidadesParaReporte(@Param("tipo") TipoCargo tipo,
                                             @Param("desde") LocalDate desde,
                                             @Param("hasta") LocalDate hasta,
                                             @Param("disciplinaId") Long disciplinaId,
                                             @Param("profesorId") Long profesorId);
}
