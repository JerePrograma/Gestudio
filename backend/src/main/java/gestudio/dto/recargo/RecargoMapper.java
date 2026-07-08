package gestudio.dto.recargo;

import gestudio.dto.recargo.request.RecargoRegistroRequest;
import gestudio.dto.recargo.response.RecargoResponse;
import gestudio.entidades.Recargo;
import org.mapstruct.*;

@Mapper(componentModel = "spring")
public interface RecargoMapper {

    @Mapping(target = "id", ignore = true)
    Recargo toEntity(RecargoRegistroRequest dto);

    RecargoResponse toResponse(Recargo recargo);
}
