package gestudio.infra.observabilidad;

import gestudio.infra.persistencia.PostgreSqlIntegrationTest;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.web.servlet.MockMvc;

import static org.hamcrest.Matchers.matchesPattern;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest(properties = {
        "app.observability.metrics-token=test-metrics-token",
        "management.endpoints.web.exposure.include=health,prometheus"
})
@AutoConfigureMockMvc
class ObservabilityPostgreSqlTest extends PostgreSqlIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    @Test
    void livenessYReadinessSonPublicosYNoExponenDetalles() throws Exception {
        mockMvc.perform(get("/actuator/health/liveness"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("UP"))
                .andExpect(jsonPath("$.components").doesNotExist());

        mockMvc.perform(get("/actuator/health/readiness"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("UP"))
                .andExpect(jsonPath("$.components").doesNotExist());
    }

    @Test
    void prometheusPermaneceCerradoSinElTokenExacto() throws Exception {
        mockMvc.perform(get("/actuator/prometheus"))
                .andExpect(status().isForbidden());

        mockMvc.perform(get("/actuator/prometheus")
                        .header(MetricsTokenAuthorizationManager.HEADER_NAME, "wrong-token"))
                .andExpect(status().isForbidden());

        mockMvc.perform(get("/actuator/prometheus")
                        .header(MetricsTokenAuthorizationManager.HEADER_NAME, "test-metrics-token"))
                .andExpect(status().isOk())
                .andExpect(content().string(org.hamcrest.Matchers.containsString("jvm_memory_used_bytes")))
                .andExpect(content().string(org.hamcrest.Matchers.containsString("http_server_requests_seconds_count")));
    }

    @Test
    void requestIdSePropagaOSeReemplazaAntesDeResponder401() throws Exception {
        mockMvc.perform(get("/api/alumnos")
                        .header(RequestCorrelationFilter.HEADER_NAME, "client-request-123"))
                .andExpect(status().isUnauthorized())
                .andExpect(header().string(RequestCorrelationFilter.HEADER_NAME, "client-request-123"));

        mockMvc.perform(get("/api/alumnos"))
                .andExpect(status().isUnauthorized())
                .andExpect(header().string(RequestCorrelationFilter.HEADER_NAME,
                        matchesPattern("[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}")));

        mockMvc.perform(get("/api/alumnos")
                        .header(RequestCorrelationFilter.HEADER_NAME, "unsafe request id"))
                .andExpect(status().isUnauthorized())
                .andExpect(header().string(RequestCorrelationFilter.HEADER_NAME,
                        matchesPattern("[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}")));
    }
}
