package ledance.dto.rol;

import ledance.dto.rol.response.RolResponse;
import ledance.entidades.Rol;
import org.mapstruct.*;

@Mapper(componentModel = "spring")
public interface RolMapper {

    /**
     * ✅ Convierte `Rol` en `RolResponse`.
     */
    default RolResponse toDTO(Rol rol) {
        return new RolResponse(rol.getId(), rol.getCodigo(), rol.getNombre(), rol.getDescripcionFuncional(),
                rol.getActivo(), rol.getSistema(), rol.getEditable(), rol.getPermisos().size());
    }
}
