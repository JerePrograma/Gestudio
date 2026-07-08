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

@Entity
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Table(name = "movimientos_stock")
public class MovimientoStock {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @ManyToOne(optional = false)
    @JoinColumn(name = "stock_id", nullable = false, updatable = false)
    private Stock stock;
    @Enumerated(EnumType.STRING)
    @Column(length = 16, nullable = false, updatable = false)
    private TipoMovimientoStock tipo;
    @Column(nullable = false, updatable = false)
    private Integer cantidad;
    @ManyToOne
    @JoinColumn(name = "venta_stock_id", updatable = false)
    private VentaStock ventaStock;
    @ManyToOne
    @JoinColumn(name = "movimiento_revertido_id", updatable = false)
    private MovimientoStock movimientoRevertido;
    @ManyToOne(optional = false)
    @JoinColumn(name = "usuario_id", nullable = false, updatable = false)
    private Usuario usuario;
    @Column(name = "idempotency_key", length = 120, nullable = false, updatable = false)
    private String idempotencyKey;
    @Column(length = 500, updatable = false)
    private String motivo;
    @CreationTimestamp
    @Column(nullable = false, updatable = false)
    private Instant createdAt;
}
