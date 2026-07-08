package gestudio.entidades;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.Instant;
import java.time.LocalDate;

@Entity
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Table(name = "notificaciones")
public class Notificacion {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    private Long usuarioId;
    @Column(length = 50, nullable = false)
    private String tipo;
    @Column(length = 500, nullable = false)
    private String mensaje;
    @Column(nullable = false)
    private Instant fechaCreacion;
    @Column(nullable = false)
    private LocalDate fechaNegocio;
    @Column(name = "dedup_key", length = 100, nullable = false, updatable = false)
    private String dedupKey;
    @Column(nullable = false)
    private boolean leida;
}
