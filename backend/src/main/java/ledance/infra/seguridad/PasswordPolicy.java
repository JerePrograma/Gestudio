package ledance.infra.seguridad;

import ledance.entidades.RolSistema;
import org.springframework.stereotype.Component;

import java.nio.charset.StandardCharsets;

@Component
public class PasswordPolicy {

    public void validar(String password, RolSistema rol) {
        int bytes = password == null ? 0 : password.getBytes(StandardCharsets.UTF_8).length;
        int minimo = rol == RolSistema.SUPERADMIN ? 16 : 12;
        if (bytes < minimo || bytes > 72) {
            throw new IllegalArgumentException(
                    "La contraseña debe tener entre " + minimo + " y 72 bytes UTF-8");
        }
    }
}
