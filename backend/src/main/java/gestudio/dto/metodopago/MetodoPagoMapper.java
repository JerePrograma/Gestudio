// src/main/java/gestudio/dto/metodopago/MetodoPagoMapper.java
package gestudio.dto.metodopago;

import gestudio.dto.metodopago.request.MetodoPagoRegistroRequest;
import gestudio.dto.metodopago.request.MetodoPagoRegistroRequest;
import gestudio.dto.metodopago.response.MetodoPagoResponse;
import gestudio.entidades.MetodoPago;
import org.mapstruct.Mapper;
import org.mapstruct.Mapping;
import org.mapstruct.MappingTarget;

@Mapper(componentModel = "spring")
public interface MetodoPagoMapper {

    MetodoPago toEntity(MetodoPagoRegistroRequest request);

    MetodoPagoResponse toDTO(MetodoPago metodoPago);

    // MapStruct actualizara recargo automaticamente si el campo tiene el mismo nombre
    void updateEntityFromRequest(MetodoPagoRegistroRequest request, @MappingTarget MetodoPago metodoPago);
}
