package ledance.tarifas.api;

import jakarta.validation.constraints.*;

import java.math.BigDecimal;
import java.time.LocalDate;

public record CondicionEconomicaRequest(
        @NotNull LocalDate vigenteDesde,
        @DecimalMin("0.00") @Digits(integer = 17, fraction = 2) BigDecimal costoParticular,
        Long bonificacionId,
        @NotBlank @Size(max = 500) String motivo) {
}
