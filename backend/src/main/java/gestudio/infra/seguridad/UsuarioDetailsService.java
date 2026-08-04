package gestudio.infra.seguridad;

import gestudio.entidades.Usuario;
import gestudio.repositorios.UsuarioRepositorio;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.core.userdetails.UsernameNotFoundException;
import org.springframework.stereotype.Service;

@Service
public class UsuarioDetailsService implements UserDetailsService {

    private final UsuarioRepositorio usuarios;

    public UsuarioDetailsService(UsuarioRepositorio usuarios) {
        this.usuarios = usuarios;
    }

    @Override
    public UserDetails loadUserByUsername(String username) {
        return usuarios.findCredencialesAutenticacion(username.trim())
                .map(UsuarioDetailsService::principalAutenticacion)
                .filter(Usuario::isEnabled)
                .orElseThrow(() -> new UsernameNotFoundException("Usuario no encontrado"));
    }

    private static Usuario principalAutenticacion(
            UsuarioRepositorio.CredencialesAutenticacion credenciales) {
        Usuario usuario = new Usuario();
        usuario.setId(credenciales.getId());
        usuario.setNombreUsuario(credenciales.getNombreUsuario());
        usuario.setContrasena(credenciales.getContrasena());
        usuario.setActivo(credenciales.getActivo());
        usuario.setAuthVersion(credenciales.getAuthVersion());
        return usuario;
    }
}
