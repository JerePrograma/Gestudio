package gestudio.validaciones.usuarios;

import gestudio.dto.usuario.request.UsuarioRegistroRequest;
import gestudio.repositorios.UsuarioRepositorio;
import gestudio.validaciones.Validador;
import org.springframework.stereotype.Component;

@Component
public class ValidadorUsuarioDuplicado implements Validador<UsuarioRegistroRequest> {

    private final UsuarioRepositorio usuarioRepositorio;

    public ValidadorUsuarioDuplicado(UsuarioRepositorio usuarioRepositorio) {
        this.usuarioRepositorio = usuarioRepositorio;
    }

    @Override
    public void validar(UsuarioRegistroRequest datos) {
        if (usuarioRepositorio.findByNombreUsuario(datos.nombreUsuario()).isPresent()) {
            throw new RuntimeException("El nombre de usuario ya esta registrado: " + datos.nombreUsuario());
        }
    }
}