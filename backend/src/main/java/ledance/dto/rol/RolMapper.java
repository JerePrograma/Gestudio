package ledance.dto.rol;

import ledance.dto.rol.response.RolResponse;
import ledance.entidades.Rol;
import org.mapstruct.*;

@Mapper(componentModel = "spring")
public interface RolMapper {

    /**
     * ✅ Convierte `Rol` en `RolResponse`.
     */
    @Mapping(target = "id", source = "id")
    @Mapping(target = "descripcion", source = "descripcion")
    @Mapping(target = "activo", source = "activo")
    RolResponse toDTO(Rol rol);
}
