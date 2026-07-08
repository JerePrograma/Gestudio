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

import java.math.BigDecimal;
import java.time.Instant;

@Entity
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Table(name = "movimientos_credito")
public class MovimientoCredito {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @ManyToOne(optional = false)
    @JoinColumn(name = "alumno_id", nullable = false, updatable = false)
    private Alumno alumno;
    @Enumerated(EnumType.STRING)
    @Column(length = 15, nullable = false, updatable = false)
    private TipoMovimientoCredito tipo;
    @Column(precision = 19, scale = 2, nullable = false, updatable = false)
    private BigDecimal importe;
    @ManyToOne
    @JoinColumn(name = "pago_id", updatable = false)
    private Pago pago;
    @ManyToOne
    @JoinColumn(name = "cargo_id", updatable = false)
    private Cargo cargo;
    @ManyToOne
    @JoinColumn(name = "movimiento_revertido_id", updatable = false)
    private MovimientoCredito movimientoRevertido;
    @ManyToOne(optional = false)
    @JoinColumn(name = "usuario_id", nullable = false, updatable = false)
    private Usuario usuario;
    @Column(name = "idempotency_key", length = 120, nullable = false, updatable = false)
    private String idempotencyKey;
    @Column(name = "request_hash", length = 64, nullable = false, updatable = false)
    private String requestHash;
    @Column(length = 500, updatable = false)
    private String motivo;
    @CreationTimestamp
    @Column(nullable = false, updatable = false)
    private Instant createdAt;
}
