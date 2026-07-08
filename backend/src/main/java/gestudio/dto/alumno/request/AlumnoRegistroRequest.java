package gestudio.dto.alumno.request;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import gestudio.dto.inscripcion.request.InscripcionRegistroRequest;

import java.time.LocalDate;
import java.util.List;

public record AlumnoRegistroRequest(
        Long id,
        @NotBlank String nombre,
        @NotBlank String apellido,
        LocalDate fechaNacimiento,
        LocalDate fechaIncorporacion,
        String celular1,
        String celular2,
        @Email String email,
        String documento,
        LocalDate fechaDeBaja,
        String nombrePadres,
        Boolean autorizadoParaSalirSolo,
        Boolean activo,
        String otrasNotas,
        List<InscripcionRegistroRequest> inscripciones
) {
}
