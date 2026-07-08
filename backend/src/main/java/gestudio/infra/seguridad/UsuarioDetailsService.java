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
        return usuarios.findByNombreUsuarioIgnoreCaseConRolesYPermisos(username.trim())
                .filter(UsuarioDetailsService::usuarioHabilitado)
                .orElseThrow(() -> new UsernameNotFoundException("Usuario no encontrado"));
    }

    private static boolean usuarioHabilitado(Usuario usuario) {
        return usuario.isEnabled()
                && usuario.rolesEfectivos().stream()
                .anyMatch(rol -> Boolean.TRUE.equals(rol.getActivo()));
    }
}