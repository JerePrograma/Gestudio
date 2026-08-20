package gestudio.infra.observabilidad;

import gestudio.infra.persistencia.PostgreSqlIntegrationTest;
import gestudio.tenancy.TenantStructuralHealthIndicator;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.actuate.health.Health;
import org.springframework.boot.test.autoconfigure.actuate.observability.AutoConfigureObservability;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.core.env.Environment;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.nio.charset.StandardCharsets;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.matchesPattern;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;
import static org.mockito.Mockito.when;

@SpringBootTest(properties = {
        "app.observability.metrics-token=test-metrics-token",
        "management.endpoints.web.exposure.include=health,prometheus"
})
@AutoConfigureMockMvc
@AutoConfigureObservability(metrics = true, tracing = false)
class ObservabilityPostgreSqlTest extends PostgreSqlIntegrationTest {

    @MockitoBean
    private TenantStructuralHealthIndicator multitenancyHealthIndicator;

    @Autowired
    private MockMvc mockMvc;

    @BeforeEach
    void readinessEstructuralDeterminista() {
        when(multitenancyHealthIndicator.health()).thenReturn(Health.up().build());
    }

    @Autowired
    private Environment environment;

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
                .andExpect(status().isUnauthorized());

        mockMvc.perform(get("/actuator/prometheus")
                        .header(MetricsTokenAuthorizationManager.HEADER_NAME, "wrong-token"))
                .andExpect(status().isUnauthorized());

        mockMvc.perform(get("/actuator/prometheus")
                        .header(MetricsTokenAuthorizationManager.HEADER_NAME,
                                "test-metrics-token", "test-metrics-token"))
                .andExpect(status().isUnauthorized());

        mockMvc.perform(get("/actuator/prometheus")
                        .header(MetricsTokenAuthorizationManager.HEADER_NAME, "test-metrics-token"))
                .andExpect(status().isOk())
                .andExpect(content().string(org.hamcrest.Matchers.containsString("jvm_memory_used_bytes")))
                .andExpect(content().string(org.hamcrest.Matchers.containsString("process_uptime_seconds")));
    }

    @Test
    void jpaUsaDeteccionDeDialectoYSinOpenSessionInView() {
        assertThat(environment.getProperty("spring.jpa.database-platform")).isNull();
        assertThat(environment.getProperty("spring.jpa.open-in-view")).isEqualTo("false");
    }

    @Test
    void requestIdSePropagaOSeReemplazaAntesDeResponder401() throws Exception {
        String clientRequestId = "client-request-123";
        String canonicalClientRequestId = UUID.nameUUIDFromBytes(
                clientRequestId.getBytes(StandardCharsets.UTF_8)).toString();
        mockMvc.perform(get("/api/alumnos")
                        .header(RequestCorrelationFilter.HEADER_NAME, clientRequestId))
                .andExpect(status().isUnauthorized())
                .andExpect(header().string(
                        RequestCorrelationFilter.HEADER_NAME, canonicalClientRequestId));

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
