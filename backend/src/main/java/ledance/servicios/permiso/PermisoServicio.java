package ledance.servicios.rol;

import ledance.dto.rol.RolMapper;
import ledance.dto.rol.response.PermisoResponse;
import ledance.repositorios.PermisoRepositorio;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Comparator;
import java.util.List;

@Service
public class PermisoServicio {

    private final PermisoRepositorio permisos;
    private final RolMapper mapper;

    public PermisoServicio(PermisoRepositorio permisos, RolMapper mapper) {
        this.permisos = permisos;
        this.mapper = mapper;
    }

    @Transactional(readOnly = true)
    public List<PermisoResponse> listarPermisos() {
        return permisos.findAll().stream()
                .sorted(Comparator.comparing(permiso -> permiso.getCodigo().toUpperCase()))
                .map(mapper::toDTO)
                .toList();
    }
}