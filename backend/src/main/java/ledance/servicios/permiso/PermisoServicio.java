package ledance.servicios.permiso;

import ledance.dto.permiso.response.PermisoResponse;
import ledance.repositorios.PermisoRepositorio;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
public class PermisoServicio {
    private final PermisoRepositorio permisos;

    public PermisoServicio(PermisoRepositorio permisos) {
        this.permisos = permisos;
    }

    @Transactional(readOnly = true)
    public List<PermisoResponse> listar(String modulo) {
        return (modulo == null || modulo.isBlank()
                ? permisos.findAllByOrderByModuloAscCodigoAsc()
                : permisos.findByModuloIgnoreCaseOrderByCodigoAsc(modulo.trim())).stream()
                .map(PermisoResponse::from).toList();
    }
}
