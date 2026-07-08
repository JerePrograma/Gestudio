package gestudio.dto.concepto.response;

import com.fasterxml.jackson.annotation.JsonFormat;

import java.math.BigDecimal;

public record ConceptoResponse(
        Long id,
        String descripcion,
        @JsonFormat(shape = JsonFormat.Shape.STRING) BigDecimal precio,
        SubConceptoResponse subConcepto,
        Boolean activo
) {
}
