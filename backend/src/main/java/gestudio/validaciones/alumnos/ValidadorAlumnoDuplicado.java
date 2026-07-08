package gestudio.validaciones.alumnos;

import gestudio.dto.alumno.request.AlumnoRegistroRequest;
import gestudio.repositorios.AlumnoRepositorio;
import gestudio.validaciones.Validador;
import org.springframework.stereotype.Component;

@Component
public class ValidadorAlumnoDuplicado implements Validador<AlumnoRegistroRequest> {

    private final AlumnoRepositorio alumnoRepositorio;

    public ValidadorAlumnoDuplicado(AlumnoRepositorio alumnoRepositorio) {
        this.alumnoRepositorio = alumnoRepositorio;
    }

    @Override
    public void validar(AlumnoRegistroRequest datos) {
        if (alumnoRepositorio.existsByNombreIgnoreCaseAndApellidoIgnoreCase(datos.nombre(), datos.apellido())) {
            throw new RuntimeException("Alumno ya existe con ese nombre y apellido: "
                    + datos.nombre() + " " + datos.apellido());
        }
    }
}
