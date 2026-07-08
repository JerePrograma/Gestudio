package ledance.infra.seguridad;

import ledance.entidades.RolSistema;
import org.springframework.stereotype.Component;

import java.nio.charset.StandardCharsets;

@Component
public class PasswordPolicy {

    public void validar(String password, RolSistema rol) {
        validar(password, rol == RolSistema.SUPERADMIN);
    }

    public void validar(String password, boolean superadmin) {
        int bytes = password == null ? 0 : password.getBytes(StandardCharsets.UTF_8).length;
        int minimo = superadmin ? 16 : 12;
        if (bytes < minimo || bytes > 72) {
            throw new IllegalArgumentException(
                    "La contraseña debe tener entre " + minimo + " y 72 bytes UTF-8");
        }
    }
}
