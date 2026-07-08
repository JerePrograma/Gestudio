package ledance.dto.rol;

import ledance.dto.rol.response.PermisoResponse;
import ledance.dto.rol.response.RolResponse;
import ledance.entidades.Permiso;
import ledance.entidades.Rol;
import org.mapstruct.Mapper;

import java.util.Comparator;
import java.util.List;

@Mapper(componentModel = "spring")
public interface RolMapper {

    default RolResponse toDTO(Rol rol) {
        return new RolResponse(
                rol.getId(),
                rol.getCodigo(),
                rol.getNombre(),
                rol.getDescripcion(),
                rol.getDescripcionFuncional(),
                rol.getActivo(),
                rol.getSistema(),
                rol.getEditable(),
                permisos(rol)
        );
    }

    default PermisoResponse toDTO(Permiso permiso) {
        return new PermisoResponse(
                permiso.getId(),
                permiso.getCodigo(),
                permiso.getDescripcion(),
                permiso.getModulo(),
                permiso.getActivo(),
                permiso.getSistema()
        );
    }

    private List<PermisoResponse> permisos(Rol rol) {
        return rol.getPermisos().stream()
                .sorted(Comparator.comparing(Permiso::getCodigo))
                .map(this::toDTO)
                .toList();
    }
}