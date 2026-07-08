package gestudio.validaciones.usuarios;

import gestudio.dto.usuario.request.UsuarioRegistroRequest;
import gestudio.validaciones.Validador;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.List;

@Component
public class ValidadorContrasenaSegura implements Validador<UsuarioRegistroRequest> {

    @Override
    public void validar(UsuarioRegistroRequest datos) {
        String contrasena = datos.contrasena();
        List<String> errores = new ArrayList<>();

        if (contrasena.length() < 6) {
            errores.add("La contraseña debe tener al menos 6 caracteres.");
        }

        if (!contrasena.matches(".*\\d.*")) {
            errores.add("La contraseña debe contener al menos un numero.");
        }

        if (!contrasena.matches(".*[A-Z].*")) {
            errores.add("La contraseña debe contener al menos una letra mayuscula.");
        }

        if (!errores.isEmpty()) {
            throw new RuntimeException(String.join(" ", errores));
        }
    }
}
