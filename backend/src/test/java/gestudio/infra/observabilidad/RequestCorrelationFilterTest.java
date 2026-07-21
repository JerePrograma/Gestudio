package gestudio.infra.observabilidad;

import org.junit.jupiter.api.Test;
import org.slf4j.MDC;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

import static org.assertj.core.api.Assertions.assertThat;

class RequestCorrelationFilterTest {

    private final RequestCorrelationFilter filter = new RequestCorrelationFilter();

    @Test
    void propagaUnRequestIdSeguro() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/test");
        request.addHeader(RequestCorrelationFilter.HEADER_NAME, "client-request-123");
        MockHttpServletResponse response = new MockHttpServletResponse();

        filter.doFilter(request, response, new MockFilterChain());

        assertThat(response.getHeader(RequestCorrelationFilter.HEADER_NAME))
                .isEqualTo("client-request-123");
        assertThat(MDC.get(RequestCorrelationFilter.MDC_KEY)).isNull();
    }

    @Test
    void generaUuidCuandoFaltaElHeader() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/test");
        MockHttpServletResponse response = new MockHttpServletResponse();

        filter.doFilter(request, response, new MockFilterChain());

        assertThat(response.getHeader(RequestCorrelationFilter.HEADER_NAME))
                .matches("[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}");
        assertThat(MDC.get(RequestCorrelationFilter.MDC_KEY)).isNull();
    }

    @Test
    void reemplazaValoresConEspaciosOSaltosDeLinea() {
        assertThat(RequestCorrelationFilter.resolveRequestId("unsafe request id"))
                .matches("[0-9a-f-]{36}")
                .isNotEqualTo("unsafe request id");
        assertThat(RequestCorrelationFilter.resolveRequestId("unsafe\nrequest"))
                .matches("[0-9a-f-]{36}")
                .isNotEqualTo("unsafe\nrequest");
    }
}
