package ledance.servicios.permiso;

import ledance.dto.rol.RolMapper;
import ledance.dto.rol.response.PermisoResponse;
import ledance.repositorios.PermisoRepositorio;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Comparator;
import java.util.List;
import java.util.Locale;

@Service
public class PermisoServicio {

    private final PermisoRepositorio permisos;
    private final RolMapper mapper;

    public PermisoServicio(PermisoRepositorio permisos, RolMapper mapper) {
        this.permisos = permisos;
        this.mapper = mapper;
    }

    @Transactional(readOnly = true)
    public List<PermisoResponse> listarPermisos(String modulo) {
        String moduloNormalizado = modulo == null || modulo.isBlank()
                ? null
                : modulo.trim().toUpperCase(Locale.ROOT);

        return permisos.findAll().stream()
                .filter(permiso -> moduloNormalizado == null
                        || permiso.getModulo().equalsIgnoreCase(moduloNormalizado))
                .sorted(Comparator
                        .comparing((ledance.entidades.Permiso permiso) -> permiso.getModulo().toUpperCase(Locale.ROOT))
                        .thenComparing(permiso -> permiso.getCodigo().toUpperCase(Locale.ROOT)))
                .map(mapper::toDTO)
                .toList();
    }
}