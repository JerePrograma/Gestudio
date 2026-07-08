package gestudio.entidades;

import jakarta.persistence.*;
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

    /**
     * Campo legacy. Se conserva por compatibilidad con usuarios.rol_id
     * y código anterior que todavía puede leer descripcion.
     */
    @Column(length = 50, nullable = false)
    private String descripcion;

    /**
     * Identificador técnico estable.
     * Ejemplos: SUPERADMIN, ADMINISTRADOR, SECRETARIA_TARDE.
     */
    @Column(length = 50, nullable = false, unique = true)
    private String codigo;

    /**
     * Nombre visible en UI.
     */
    @Column(length = 100, nullable = false)
    private String nombre;

    @Column(name = "descripcion_funcional", length = 255)
    private String descripcionFuncional;

    @Column(nullable = false)
    private Boolean activo = true;

    /**
     * true = rol semilla/reservado.
     */
    @Column(nullable = false)
    private Boolean sistema = false;

    /**
     * false = no editable desde panel común.
     */
    @Column(nullable = false)
    private Boolean editable = true;

    @ManyToMany(fetch = FetchType.LAZY)
    @JoinTable(
            name = "rol_permisos",
            joinColumns = @JoinColumn(name = "rol_id"),
            inverseJoinColumns = @JoinColumn(name = "permiso_id")
    )
    private Set<Permiso> permisos = new LinkedHashSet<>();

    /**
     * Constructor de compatibilidad para tests viejos:
     * new Rol(id, "ADMINISTRADOR", true)
     */
    public Rol(Long id, String descripcion, Boolean activo) {
        this.id = id;
        this.descripcion = descripcion;
        this.codigo = descripcion;
        this.nombre = descripcion;
        this.descripcionFuncional = descripcion;
        this.activo = activo;
        this.sistema = "SUPERADMIN".equalsIgnoreCase(descripcion)
                || "ADMINISTRADOR".equalsIgnoreCase(descripcion);
        this.editable = !"SUPERADMIN".equalsIgnoreCase(descripcion);
    }

    public boolean estaActivo() {
        return Boolean.TRUE.equals(activo);
    }

    public boolean esSistema() {
        return Boolean.TRUE.equals(sistema);
    }

    public boolean esEditable() {
        return Boolean.TRUE.equals(editable);
    }

    public boolean esSuperadminSistema() {
        return "SUPERADMIN".equalsIgnoreCase(codigo);
    }
}