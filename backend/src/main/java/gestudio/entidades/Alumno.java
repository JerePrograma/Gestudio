package gestudio.entidades;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.Version;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotNull;
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
@Table(name = "alumnos")
public class Alumno {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @NotNull
    @Column(length = 100, nullable = false)
    private String nombre;

    @Column(length = 100)
    private String apellido;
    private LocalDate fechaNacimiento;

    @Column(length = 30)
    private String celular1;
    @Column(length = 30)
    private String celular2;

    @Email
    @Column(length = 254)
    private String email;

    @Column(length = 30)
    private String documento;
    @NotNull
    @Column(nullable = false)
    private LocalDate fechaIncorporacion;
    private LocalDate fechaDeBaja;

    @Column(length = 200)
    private String nombrePadres;
    private Boolean autorizadoParaSalirSolo;
    @Column(columnDefinition = "text")
    private String otrasNotas;

    @Column(nullable = false)
    private Boolean activo = true;

    @Version
    @Column(nullable = false)
    private Long version;
}
