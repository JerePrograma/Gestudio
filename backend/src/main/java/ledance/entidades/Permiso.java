package ledance.entidades;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

@Entity
@Getter
@Setter
@NoArgsConstructor
@Table(name = "permisos")
public class Permiso {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(length = 100, nullable = false, unique = true)
    private String codigo;

    @Column(length = 255, nullable = false)
    private String descripcion;

    @Column(length = 50, nullable = false)
    private String modulo;

    @Column(nullable = false)
    private Boolean activo = true;

    @Column(nullable = false)
    private Boolean sistema = true;

    public boolean estaActivo() {
        return Boolean.TRUE.equals(activo);
    }
}