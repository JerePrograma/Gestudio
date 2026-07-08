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

import java.time.LocalDate;

@Entity
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Table(name = "mensualidades")
public class Mensualidad {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(optional = false)
    @JoinColumn(name = "inscripcion_id", nullable = false)
    private Inscripcion inscripcion;

    @ManyToOne
    @JoinColumn(name = "bonificacion_id")
    private Bonificacion bonificacion;

    @ManyToOne
    @JoinColumn(name = "recargo_id")
    private Recargo recargo;

    @Column(nullable = false)
    private Integer anio;
    @Column(nullable = false)
    private Integer mes;
    @Column(nullable = false)
    private LocalDate fechaGeneracion;
    @Column(nullable = false)
    private LocalDate fechaVencimiento;
    @Column(length = 255, nullable = false)
    private String descripcion;

    @Enumerated(EnumType.STRING)
    @Column(length = 10, nullable = false)
    private EstadoOrigenCargo estado = EstadoOrigenCargo.EMITIDA;

    @Version
    @Column(nullable = false)
    private Long version;
}
