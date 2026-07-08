package ledance.entidades;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.FetchType;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.JoinTable;
import jakarta.persistence.ManyToMany;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.util.LinkedHashSet;
import java.util.Set;

@Entity
@Getter
@Setter
@NoArgsConstructor
@Table(name = "roles")
public class Rol {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @Column(length = 50, nullable = false)
    private String codigo;
    @Column(length = 100, nullable = false)
    private String nombre;
    @Column(name = "descripcion_funcional", length = 255)
    private String descripcionFuncional;
    @Column(length = 50, nullable = false)
    private String descripcion;
    @Column(nullable = false)
    private Boolean activo = true;
    @Column(nullable = false)
    private Boolean sistema = false;
    @Column(nullable = false)
    private Boolean editable = true;
    @ManyToMany(fetch = FetchType.EAGER)
    @JoinTable(name = "rol_permisos",
            joinColumns = @JoinColumn(name = "rol_id"),
            inverseJoinColumns = @JoinColumn(name = "permiso_id"))
    private Set<Permiso> permisos = new LinkedHashSet<>();

    public Rol(Long id, String descripcion, Boolean activo) {
        this.id = id;
        this.codigo = descripcion;
        this.nombre = descripcion;
        this.descripcion = descripcion;
        this.activo = activo;
    }
}
