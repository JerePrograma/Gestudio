package gestudio.dto.alumno.response;

import gestudio.dto.inscripcion.response.InscripcionResponse;

import java.time.LocalDate;
import java.util.List;

public record AlumnoResponse(
        Long id,
        String nombre,
        String apellido,
        LocalDate fechaNacimiento,
        LocalDate fechaIncorporacion,
        Integer edad,
        String celular1,
        String celular2,
        String email,
        String documento,
        LocalDate fechaDeBaja,
        String nombrePadres,
        Boolean autorizadoParaSalirSolo,
        Boolean activo,
        String otrasNotas,
        List<InscripcionResponse> inscripciones
) {
}
