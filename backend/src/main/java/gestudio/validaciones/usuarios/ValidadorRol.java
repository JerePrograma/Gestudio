package gestudio.validaciones.usuarios;
import gestudio.dto.usuario.request.UsuarioRegistroRequest;
import gestudio.repositorios.RolRepositorio;
import gestudio.validaciones.Validador;
import org.springframework.stereotype.Component;

@Component
public class ValidadorRol implements Validador<UsuarioRegistroRequest> {

    private final RolRepositorio rolRepositorio;

    public ValidadorRol(RolRepositorio rolRepositorio) {
        this.rolRepositorio = rolRepositorio;
    }

    @Override
    public void validar(UsuarioRegistroRequest request) {
        for (String codigo : request.roles()) {
            if (rolRepositorio.findByCodigoIgnoreCase(codigo.trim()).isEmpty()) {
                throw new IllegalArgumentException("El rol proporcionado no es válido: " + codigo);
            }
        }
    }
}
