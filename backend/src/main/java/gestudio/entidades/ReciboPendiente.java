package gestudio.entidades;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.hibernate.annotations.CreationTimestamp;

import java.time.Instant;
import java.util.UUID;

@Entity
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Table(name = "recibos_pendientes")
public class ReciboPendiente {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @ManyToOne(optional = false)
    @JoinColumn(name = "pago_id", nullable = false, updatable = false)
    private Pago pago;
    @Enumerated(EnumType.STRING)
    @Column(length = 20, nullable = false, updatable = false)
    private TipoEfectoRecibo tipo = TipoEfectoRecibo.GENERAR_Y_ENVIAR;
    @Enumerated(EnumType.STRING)
    @Column(length = 12, nullable = false)
    private EstadoReciboPendiente estado = EstadoReciboPendiente.PENDIENTE;
    @Column(nullable = false)
    private Integer intentos = 0;
    @Column(nullable = false)
    private Instant nextAttemptAt;
    @Column(length = 120, nullable = false, updatable = false)
    private String idempotencyKey;
    private UUID claimToken;
    private Instant claimedAt;
    private Instant leaseUntil;
    @Column(length = 500)
    private String ultimoError;
    @CreationTimestamp
    @Column(nullable = false, updatable = false)
    private Instant createdAt;
    private Instant processedAt;
}
