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

import java.math.BigDecimal;

@Entity
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Table(name = "recargos")
public class Recargo {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @Column(length = 150, nullable = false)
    private String descripcion;
    @Column(precision = 7, scale = 4, nullable = false)
    private BigDecimal porcentaje = BigDecimal.ZERO;
    @Column(precision = 19, scale = 2, nullable = false)
    private BigDecimal valorFijo = BigDecimal.ZERO;
    private Integer diaDelMesAplicacion;
    @Column(nullable = false)
    private Boolean activo = true;
}
