package gestudio.dto.profesor.request;

import jakarta.validation.constraints.NotBlank;
import java.time.LocalDate;

public record ProfesorRegistroRequest(
        @NotBlank String nombre,
        @NotBlank String apellido,
        LocalDate fechaNacimiento, // ✅ NUEVO: Fecha de nacimiento opcional
        String telefono // ✅ NUEVO: Numero de contacto opcional
) {}
