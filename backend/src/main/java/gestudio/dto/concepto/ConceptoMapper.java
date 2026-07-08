package gestudio.dto.concepto;

import gestudio.dto.concepto.request.ConceptoRegistroRequest;
import gestudio.dto.concepto.response.ConceptoResponse;
import gestudio.entidades.Concepto;
import org.mapstruct.Mapper;
import org.mapstruct.Mapping;

@Mapper(componentModel = "spring", uses = {SubConceptoMapper.class})
public interface ConceptoMapper {
    // Mapea de registro a entidad; se ignora la asociacion subConcepto, que se asignara en el servicio.
    @Mapping(target = "subConcepto", ignore = true)
    @Mapping(target = "id", ignore = true)
    Concepto toEntity(ConceptoRegistroRequest request);

    ConceptoResponse toResponse(Concepto concepto);

}
