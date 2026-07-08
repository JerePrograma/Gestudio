package gestudio.tarifas.api;

import jakarta.validation.constraints.*;

import java.math.BigDecimal;
import java.time.LocalDate;

public record TarifaDisciplinaRequest(
        @NotNull LocalDate vigenteDesde,
        @NotNull @DecimalMin("0.00") @Digits(integer = 17, fraction = 2) BigDecimal valorCuota,
        @NotNull @DecimalMin("0.00") @Digits(integer = 17, fraction = 2) BigDecimal matricula,
        @NotNull @DecimalMin("0.00") @Digits(integer = 17, fraction = 2) BigDecimal claseSuelta,
        @NotNull @DecimalMin("0.00") @Digits(integer = 17, fraction = 2) BigDecimal clasePrueba,
        @NotBlank @Size(max = 500) String motivo) {
}
