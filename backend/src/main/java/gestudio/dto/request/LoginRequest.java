package gestudio.dto.request;

import jakarta.validation.constraints.AssertTrue;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import java.nio.charset.StandardCharsets;

public record LoginRequest(
        @NotBlank @Size(max = 100) String nombreUsuario,
        @NotBlank @Size(max = 72) String contrasena
) {
    @AssertTrue(message = "La contraseña no puede superar 72 bytes UTF-8")
    public boolean isContrasenaDentroDelLimiteBcrypt() {
        return contrasena == null || contrasena.getBytes(StandardCharsets.UTF_8).length <= 72;
    }
}
