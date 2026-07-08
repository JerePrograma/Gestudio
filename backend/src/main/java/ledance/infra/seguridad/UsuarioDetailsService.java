package ledance.infra.seguridad;

import ledance.repositorios.UsuarioRepositorio;
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
        return usuarios.findByNombreUsuarioIgnoreCase(username.trim())
                .filter(usuario -> usuario.getRoles().stream()
                        .anyMatch(role -> Boolean.TRUE.equals(role.getActivo())))
                .orElseThrow(() -> new UsernameNotFoundException("Usuario no encontrado"));
    }
}
