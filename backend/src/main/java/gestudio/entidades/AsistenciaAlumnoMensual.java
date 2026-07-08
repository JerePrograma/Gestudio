package gestudio.entidades;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.OneToMany;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.util.ArrayList;
import java.util.List;

@Entity
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Table(name = "asistencias_alumno_mensual")
public class AsistenciaAlumnoMensual {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @ManyToOne(optional = false)
    @JoinColumn(name = "inscripcion_id", nullable = false)
    private Inscripcion inscripcion;
    @Column(length = 500)
    private String observacion;
    @Column(nullable = false)
    private Boolean activo = true;
    @ManyToOne(optional = false)
    @JoinColumn(name = "asistencia_mensual_id", nullable = false)
    private AsistenciaMensual asistenciaMensual;
    @OneToMany(mappedBy = "asistenciaAlumnoMensual")
    private List<AsistenciaDiaria> asistenciasDiarias = new ArrayList<>();
}
