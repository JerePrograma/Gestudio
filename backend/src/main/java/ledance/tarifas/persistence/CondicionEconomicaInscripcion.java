package ledance.tarifas.persistence;

import jakarta.persistence.*;
import ledance.entidades.Bonificacion;
import ledance.entidades.Inscripcion;
import ledance.entidades.Usuario;
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
@Table(name = "inscripcion_condiciones_economicas")
public class CondicionEconomicaInscripcion {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY) private Long id;
    @ManyToOne(optional = false) @JoinColumn(name = "inscripcion_id", nullable = false) private Inscripcion inscripcion;
    @Column(name = "vigente_desde", nullable = false) private LocalDate vigenteDesde;
    @Column(name = "costo_particular", precision = 19, scale = 2) private BigDecimal costoParticular;
    @ManyToOne @JoinColumn(name = "bonificacion_id") private Bonificacion bonificacion;
    @Column(name = "bonificacion_descripcion_snapshot", length = 150) private String bonificacionDescripcionSnapshot;
    @Column(name = "bonificacion_porcentaje_snapshot", precision = 7, scale = 4, nullable = false)
    private BigDecimal bonificacionPorcentajeSnapshot;
    @Column(name = "bonificacion_valor_fijo_snapshot", precision = 19, scale = 2, nullable = false)
    private BigDecimal bonificacionValorFijoSnapshot;
    @Column(length = 500, nullable = false) private String motivo;
    @ManyToOne(optional = false) @JoinColumn(name = "creada_por_usuario_id", nullable = false) private Usuario creadaPor;
    @Column(name = "created_at", nullable = false, updatable = false) private Instant createdAt;
    @Version @Column(nullable = false) private Long version;
}
