package gestudio.dto.usuario;

import gestudio.dto.usuario.request.UsuarioRegistroRequest;
import gestudio.dto.usuario.response.UsuarioResponse;
import gestudio.entidades.Usuario;
import org.mapstruct.Mapper;
import org.mapstruct.Mapping;
import org.mapstruct.Named;

@Mapper(componentModel = "spring")
public interface UsuarioMapper {

    @Mapping(target = "id", ignore = true)
    @Mapping(target = "contrasena", ignore = true)
    @Mapping(target = "rol", ignore = true)
    @Mapping(target = "roles", ignore = true)
    @Mapping(target = "activo", constant = "true")
    @Mapping(target = "authorities", ignore = true)
    @Mapping(target = "authVersion", ignore = true)
    @Mapping(target = "passwordChangedAt", ignore = true)
    @Mapping(target = "version", ignore = true)
    Usuario toEntity(UsuarioRegistroRequest request);

    @Named("toUsuarioResponse")
    default UsuarioResponse toDTO(Usuario usuario) {
        return new UsuarioResponse(
                usuario.getId(),
                usuario.getNombreUsuario(),
                usuario.codigosRolesActivos().stream().toList(),
                usuario.codigosPermisosActivos().stream().toList(),
                usuario.getActivo()
        );
    }
}