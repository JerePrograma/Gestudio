package ledance.tarifas.persistence;

import jakarta.persistence.*;
import ledance.entidades.Disciplina;
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
@Table(name = "disciplina_tarifas")
public class TarifaDisciplina {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY) private Long id;
    @ManyToOne(optional = false) @JoinColumn(name = "disciplina_id", nullable = false) private Disciplina disciplina;
    @Column(name = "vigente_desde", nullable = false) private LocalDate vigenteDesde;
    @Column(name = "valor_cuota", precision = 19, scale = 2, nullable = false) private BigDecimal valorCuota;
    @Column(precision = 19, scale = 2, nullable = false) private BigDecimal matricula;
    @Column(name = "clase_suelta", precision = 19, scale = 2, nullable = false) private BigDecimal claseSuelta;
    @Column(name = "clase_prueba", precision = 19, scale = 2, nullable = false) private BigDecimal clasePrueba;
    @Column(length = 500, nullable = false) private String motivo;
    @ManyToOne(optional = false) @JoinColumn(name = "creada_por_usuario_id", nullable = false) private Usuario creadaPor;
    @Column(name = "created_at", nullable = false, updatable = false) private Instant createdAt;
    @Version @Column(nullable = false) private Long version;
}
