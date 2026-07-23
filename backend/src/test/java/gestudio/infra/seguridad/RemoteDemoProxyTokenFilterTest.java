package gestudio.infra.seguridad;

import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

import java.util.concurrent.atomic.AtomicBoolean;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class RemoteDemoProxyTokenFilterTest {

    private static final String TOKEN = "pages-proxy-token-independent-32-bytes";

    @Test
    void rechazaConfiguracionDebil() {
        assertThatThrownBy(() -> new RemoteDemoProxyTokenFilter("short"))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("token de proxy");
    }

    @Test
    void ocultaApiCuandoFaltaOTieneTokenIncorrecto() throws Exception {
        RemoteDemoProxyTokenFilter filter = new RemoteDemoProxyTokenFilter(TOKEN);
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/alumnos");
        MockHttpServletResponse response = new MockHttpServletResponse();
        AtomicBoolean invoked = new AtomicBoolean(false);

        filter.doFilter(request, response, (ignoredRequest, ignoredResponse) -> invoked.set(true));

        assertThat(invoked).isFalse();
        assertThat(response.getStatus()).isEqualTo(404);
        assertThat(response.getHeader("Cache-Control")).isEqualTo("no-store");
    }

    @Test
    void permiteApiConTokenExacto() throws Exception {
        RemoteDemoProxyTokenFilter filter = new RemoteDemoProxyTokenFilter(TOKEN);
        MockHttpServletRequest request = new MockHttpServletRequest("POST", "/api/login");
        request.addHeader(RemoteDemoProxyTokenFilter.HEADER_NAME, TOKEN);
        MockHttpServletResponse response = new MockHttpServletResponse();
        AtomicBoolean invoked = new AtomicBoolean(false);

        filter.doFilter(request, response, (ignoredRequest, ignoredResponse) -> invoked.set(true));

        assertThat(invoked).isTrue();
        assertThat(response.getStatus()).isEqualTo(200);
    }

    @Test
    void noInterfiereConReadinessLocal() throws Exception {
        RemoteDemoProxyTokenFilter filter = new RemoteDemoProxyTokenFilter(TOKEN);
        MockHttpServletRequest request = new MockHttpServletRequest(
                "GET",
                "/actuator/health/readiness");
        MockHttpServletResponse response = new MockHttpServletResponse();
        AtomicBoolean invoked = new AtomicBoolean(false);

        filter.doFilter(request, response, (ignoredRequest, ignoredResponse) -> invoked.set(true));

        assertThat(invoked).isTrue();
    }

    @Test
    void ocultaReadinessYOtrosPathsCuandoLleganDesdeCloudflare() throws Exception {
        RemoteDemoProxyTokenFilter filter = new RemoteDemoProxyTokenFilter(TOKEN);

        for (String path : new String[]{"/actuator/health/readiness", "/actuator/prometheus", "/"}) {
            MockHttpServletRequest request = new MockHttpServletRequest("GET", path);
            request.addHeader("CF-Ray", "1234567890abcdef-EZE");
            request.addHeader("CF-Connecting-IP", "203.0.113.10");
            MockHttpServletResponse response = new MockHttpServletResponse();
            AtomicBoolean invoked = new AtomicBoolean(false);

            filter.doFilter(request, response, (ignoredRequest, ignoredResponse) -> invoked.set(true));

            assertThat(invoked).as(path).isFalse();
            assertThat(response.getStatus()).as(path).isEqualTo(404);
            assertThat(response.getHeader("Cache-Control")).as(path).isEqualTo("no-store");
        }
    }
}
