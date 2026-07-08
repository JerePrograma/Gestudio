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
import org.hibernate.annotations.CreationTimestamp;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;

@Entity
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Table(name = "aplicaciones_pago")
public class AplicacionPago {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @ManyToOne(optional = false)
    @JoinColumn(name = "pago_id", nullable = false, updatable = false)
    private Pago pago;
    @ManyToOne(optional = false)
    @JoinColumn(name = "cargo_id", nullable = false, updatable = false)
    private Cargo cargo;
    @ManyToOne(optional = false)
    @JoinColumn(name = "usuario_id", nullable = false, updatable = false)
    private Usuario usuario;
    @Column(name = "importe_aplicado", precision = 19, scale = 2, nullable = false, updatable = false)
    private BigDecimal importeAplicado;
    @Enumerated(EnumType.STRING)
    @Column(length = 10, nullable = false)
    private EstadoAplicacionPago estado = EstadoAplicacionPago.APLICADA;
    @Column(nullable = false, updatable = false)
    private LocalDate fecha;
    @Column(length = 500)
    private String motivoReversion;
    private Instant fechaReversion;
    @Version
    @Column(nullable = false)
    private Long version;
    @CreationTimestamp
    @Column(nullable = false, updatable = false)
    private Instant createdAt;
}
