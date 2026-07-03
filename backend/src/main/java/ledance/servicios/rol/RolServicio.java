package ledance.servicios.rol;

import ledance.dto.rol.response.RolResponse;
import ledance.dto.rol.RolMapper;
import ledance.entidades.Rol;
import ledance.repositorios.RolRepositorio;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.stream.Collectors;

@Service
public class RolServicio {

    private final RolRepositorio rolRepositorio;
    private final RolMapper rolMapper;

    public RolServicio(RolRepositorio rolRepositorio, RolMapper rolMapper) {
        this.rolRepositorio = rolRepositorio;
        this.rolMapper = rolMapper;
    }

    public RolResponse obtenerRolPorId(Long id) {
        Rol rol = rolRepositorio.findById(id)
                .orElseThrow(() -> new IllegalArgumentException("Rol no encontrado."));
        return rolMapper.toDTO(rol);
    }

    public List<RolResponse> listarRoles() {
        return rolRepositorio.findAll().stream()
                .map(rolMapper::toDTO)
                .collect(Collectors.toList());
    }
}
