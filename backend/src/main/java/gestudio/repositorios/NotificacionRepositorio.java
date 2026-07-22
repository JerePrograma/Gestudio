package gestudio.repositorios;

import gestudio.entidades.Notificacion;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;

public interface NotificacionRepositorio extends JpaRepository<Notificacion, Long> {
    @Modifying
    @Query(value = """
            INSERT INTO notificaciones(tipo, mensaje, fecha_creacion, fecha_negocio, dedup_key, leida)
            VALUES (:tipo, :mensaje, :fechaCreacion, :fechaNegocio, :dedupKey, false)
            ON CONFLICT (dedup_key) DO NOTHING
            """, nativeQuery = true)
    int insertarSiAusente(@Param("tipo") String tipo,
                          @Param("mensaje") String mensaje,
                          @Param("fechaCreacion") Instant fechaCreacion,
                          @Param("fechaNegocio") LocalDate fechaNegocio,
                          @Param("dedupKey") String dedupKey);

    List<Notificacion> findByTipoAndFechaNegocioOrderById(String tipo, LocalDate fechaNegocio);
}
