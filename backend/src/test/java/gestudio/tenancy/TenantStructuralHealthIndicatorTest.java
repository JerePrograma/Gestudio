package gestudio.tenancy;

import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.Test;
import org.springframework.boot.actuate.health.Status;
import org.springframework.jdbc.core.JdbcTemplate;
import gestudio.servicios.pdfs.ReceiptNamespaceMigrator;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class TenantStructuralHealthIndicatorTest {

    @Test
    void readinessSoloSubeConHealthEstructuralGreen() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.queryForObject("SELECT public.gestudio_multitenancy_health()", String.class))
                .thenReturn("GREEN", "RED");
        ReceiptNamespaceMigrator files = mock(ReceiptNamespaceMigrator.class);
        when(files.isHealthy()).thenReturn(true);
        TenantStructuralHealthIndicator health = new TenantStructuralHealthIndicator(
                jdbc, new TenantMetrics(new SimpleMeterRegistry()), files);

        assertThat(health.health().getStatus()).isEqualTo(Status.UP);
        assertThat(health.health().getStatus()).isEqualTo(Status.DOWN);
    }
}
