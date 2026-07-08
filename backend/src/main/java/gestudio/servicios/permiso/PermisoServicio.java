package gestudio.servicios.permiso;

import gestudio.dto.rol.RolMapper;
import gestudio.dto.rol.response.PermisoResponse;
import gestudio.repositorios.PermisoRepositorio;
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
                        .comparing((gestudio.entidades.Permiso permiso) -> permiso.getModulo().toUpperCase(Locale.ROOT))
                        .thenComparing(permiso -> permiso.getCodigo().toUpperCase(Locale.ROOT)))
                .map(mapper::toDTO)
                .toList();
    }
}