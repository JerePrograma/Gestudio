package gestudio.infra.observabilidad;

import jakarta.servlet.FilterChain;
import org.junit.jupiter.api.Test;
import org.slf4j.MDC;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

import java.nio.charset.StandardCharsets;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

class RequestCorrelationFilterTest {

    private final RequestCorrelationFilter filter = new RequestCorrelationFilter();

    @Test
    void generaUnUuidCanonicoUnaVezCuandoFaltaElHeader() throws Exception {
        assertCorrelation(null, null, 4);
    }

    @Test
    void conservaElUuidDelClienteEnHeaderMdcYAtributo() throws Exception {
        UUID supplied = UUID.fromString("AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA");

        assertCorrelation("AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA", supplied, 4);
    }

    @Test
    void convierteUnIdSeguroNoUuidUnaVezYPropagaElMismoValor() throws Exception {
        String supplied = "client-request-123";
        UUID expected = UUID.nameUUIDFromBytes(supplied.getBytes(StandardCharsets.UTF_8));

        assertCorrelation(supplied, expected, 3);
    }

    @Test
    void reemplazaUnIdInseguroPorUnUuidAleatorioCanonico() throws Exception {
        assertCorrelation("unsafe request id", null, 4);
        assertThat(RequestCorrelationFilter.resolveRequestId("unsafe\nrequest").version())
                .isEqualTo(4);
    }

    private void assertCorrelation(String supplied, UUID expected, int expectedVersion)
            throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/test");
        if (supplied != null) request.addHeader(RequestCorrelationFilter.HEADER_NAME, supplied);
        MockHttpServletResponse response = new MockHttpServletResponse();
        UUID[] observed = new UUID[1];
        FilterChain chain = (servletRequest, servletResponse) -> {
            observed[0] = (UUID) servletRequest.getAttribute(
                    RequestCorrelationFilter.ATTRIBUTE_NAME);
            assertThat(MDC.get(RequestCorrelationFilter.MDC_KEY))
                    .isEqualTo(observed[0].toString());
        };

        filter.doFilter(request, response, chain);

        UUID responseId = UUID.fromString(
                response.getHeader(RequestCorrelationFilter.HEADER_NAME));
        assertThat(responseId).isEqualTo(observed[0]);
        if (expected != null) assertThat(responseId).isEqualTo(expected);
        assertThat(responseId.version()).isEqualTo(expectedVersion);
        assertThat(MDC.get(RequestCorrelationFilter.MDC_KEY)).isNull();
    }
}
