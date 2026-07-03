package ledance.servicios.cargo;

import ledance.entidades.EstadoCargo;

import java.math.BigDecimal;

public record SaldoCargo(
        BigDecimal importeOriginal,
        BigDecimal aplicadoPagos,
        BigDecimal aplicadoCredito,
        BigDecimal saldo,
        EstadoCargo estadoEsperado
) {
    public BigDecimal aplicadoTotal() {
        return aplicadoPagos.add(aplicadoCredito);
    }
}
