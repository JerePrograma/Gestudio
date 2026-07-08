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
import jakarta.persistence.Version;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;

@Entity
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Table(name = "egresos")
public class Egreso {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @Column(nullable = false)
    private LocalDate fecha;
    @Column(precision = 19, scale = 2, nullable = false)
    private BigDecimal monto;
    @Column(length = 500)
    private String observaciones;
    @ManyToOne(optional = false)
    @JoinColumn(name = "metodo_pago_id", nullable = false)
    private MetodoPago metodoPago;
    @Enumerated(EnumType.STRING)
    @Column(length = 10, nullable = false)
    private EstadoPago estado = EstadoPago.REGISTRADO;
    @ManyToOne(optional = false)
    @JoinColumn(name = "usuario_id", nullable = false)
    private Usuario usuario;
    @Column(name = "idempotency_key", length = 100, nullable = false, updatable = false)
    private String idempotencyKey;
    @Column(name = "request_hash", length = 64, nullable = false, updatable = false)
    private String requestHash;
    @Column(name = "reversal_idempotency_key", length = 100)
    private String reversalIdempotencyKey;
    @Column(name = "reversal_request_hash", length = 64)
    private String reversalRequestHash;
    @Column(length = 500)
    private String motivoAnulacion;
    private Instant fechaAnulacion;
    @Version
    @Column(nullable = false)
    private Long version;
}
