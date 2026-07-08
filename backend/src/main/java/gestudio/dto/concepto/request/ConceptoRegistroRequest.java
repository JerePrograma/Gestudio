package gestudio.dto.concepto.request;

import com.fasterxml.jackson.annotation.JsonFormat;
import jakarta.validation.constraints.NotNull;

import java.math.BigDecimal;

public record ConceptoRegistroRequest(
        @NotNull String descripcion,
        @NotNull @JsonFormat(shape = JsonFormat.Shape.STRING) BigDecimal precio,
        @NotNull SubConceptoRegistroRequest subConcepto,
        Boolean activo
) {
}
