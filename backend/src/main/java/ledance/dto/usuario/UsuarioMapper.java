package ledance.dto.usuario;

import ledance.dto.usuario.request.UsuarioRegistroRequest;
import ledance.dto.usuario.response.UsuarioResponse;
import ledance.entidades.Usuario;
import org.mapstruct.Mapper;
import org.mapstruct.Mapping;
import org.mapstruct.Named;

@Mapper(componentModel = "spring")
public interface UsuarioMapper {

    /**
     * Convierte UsuarioRegistroRequest en una entidad Usuario.
     * Se ignora el id (generado automaticamente), la contraseña (se encripta en el servicio)
     * y el rol (se asigna en el servicio). Ademas, se fija activo en true.
     */
    @Mapping(target = "id", ignore = true)
    @Mapping(target = "contrasena", ignore = true)
    @Mapping(target = "rol", ignore = true)
    @Mapping(target = "activo", constant = "true")
    @Mapping(target = "authorities", ignore = true)
    @Mapping(target = "authVersion", ignore = true)
    @Mapping(target = "passwordChangedAt", ignore = true)
    @Mapping(target = "version", ignore = true)
    Usuario toEntity(UsuarioRegistroRequest request);

    /**
     * Convierte Usuario en UsuarioResponse.
     * Se extrae el nombre del rol en lugar de enviar el objeto completo.
     * Se agrega @Named para que otros mappers (por ejemplo, PagoMapper) lo puedan usar.
     */
    @Named("toUsuarioResponse")
    @Mapping(target = "id", source = "id")
    @Mapping(target = "nombreUsuario", source = "nombreUsuario")
    @Mapping(target = "rol", expression = "java(usuario.getRol() != null ? usuario.getRol().getDescripcion() : null)")
    @Mapping(target = "activo", source = "activo")
    UsuarioResponse toDTO(Usuario usuario);
}
