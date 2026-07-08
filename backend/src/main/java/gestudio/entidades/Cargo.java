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
import jakarta.persistence.OneToOne;
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
@Table(name = "cargos")
public class Cargo {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @ManyToOne(optional = false)
    @JoinColumn(name = "alumno_id", nullable = false)
    private Alumno alumno;
    @Enumerated(EnumType.STRING)
    @Column(length = 20, nullable = false, updatable = false)
    private TipoCargo tipo;
    @Column(length = 255, nullable = false, updatable = false)
    private String descripcion;
    @Column(name = "importe_original", precision = 19, scale = 2, nullable = false, updatable = false)
    private BigDecimal importeOriginal;
    @Column(nullable = false, updatable = false)
    private LocalDate fechaEmision;
    @Column(nullable = false)
    private LocalDate fechaVencimiento;
    @Enumerated(EnumType.STRING)
    @Column(length = 10, nullable = false)
    private EstadoCargo estado = EstadoCargo.PENDIENTE;
    @OneToOne
    @JoinColumn(name = "mensualidad_id")
    private Mensualidad mensualidad;
    @OneToOne
    @JoinColumn(name = "matricula_id")
    private Matricula matricula;
    @ManyToOne
    @JoinColumn(name = "concepto_id")
    private Concepto concepto;
    @OneToOne
    @JoinColumn(name = "venta_stock_id")
    private VentaStock ventaStock;
    @ManyToOne
    @JoinColumn(name = "cargo_origen_id")
    private Cargo cargoOrigen;
    @Column(name = "idempotency_key", length = 100, updatable = false)
    private String idempotencyKey;
    @Version
    @Column(nullable = false)
    private Long version;
    @CreationTimestamp
    @Column(nullable = false, updatable = false)
    private Instant createdAt;
}
