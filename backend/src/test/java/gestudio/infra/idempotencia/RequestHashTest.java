package gestudio.infra.idempotencia;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class RequestHashTest {

    @Test
    void usaUtf8OrdenExplicitoYEncuadreSinColisionesPorSeparadores() {
        String first = RequestHash.sha256("PAGO", "á", "1.00", null);

        assertThat(first).hasSize(64).isEqualTo(RequestHash.sha256("PAGO", "á", "1.00", null));
        assertThat(first).isNotEqualTo(RequestHash.sha256("PAGO", "á", "1.0", null));
        assertThat(RequestHash.sha256("a|b", "c")).isNotEqualTo(RequestHash.sha256("a", "b|c"));
        assertThat(RequestHash.sha256("1", "2")).isNotEqualTo(RequestHash.sha256("2", "1"));
    }
}
