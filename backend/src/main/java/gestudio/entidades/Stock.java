package gestudio.entidades;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.Version;
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
@Table(name = "stocks")
public class Stock {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @Column(length = 150, nullable = false)
    private String nombre;
    @Column(precision = 19, scale = 2, nullable = false)
    private BigDecimal precio;
    @Column(name = "cantidad_actual", nullable = false)
    private Integer stock = 0;
    @Column(nullable = false)
    private Boolean requiereControlDeStock = true;
    @Column(length = 100)
    private String codigoBarras;
    @Column(nullable = false)
    private Boolean activo = true;
    @Version
    @Column(nullable = false)
    private Long version;
}
