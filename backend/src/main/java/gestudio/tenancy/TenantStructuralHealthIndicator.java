package gestudio.tenancy;

import gestudio.servicios.pdfs.ReceiptNamespaceMigrator;
import org.springframework.boot.actuate.health.Health;
import org.springframework.boot.actuate.health.HealthIndicator;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

@Component("multitenancy")
public class TenantStructuralHealthIndicator implements HealthIndicator {
    private final JdbcTemplate jdbc;
    private final TenantMetrics metrics;
    private final ReceiptNamespaceMigrator receiptFiles;

    public TenantStructuralHealthIndicator(JdbcTemplate jdbc, TenantMetrics metrics,
                                           ReceiptNamespaceMigrator receiptFiles) {
        this.jdbc = jdbc;
        this.metrics = metrics;
        this.receiptFiles = receiptFiles;
    }

    @Override
    public Health health() {
        try {
            String status = jdbc.queryForObject(
                    "SELECT public.gestudio_multitenancy_health()", String.class);
            boolean green = "GREEN".equals(status) && receiptFiles.isHealthy();
            metrics.migrationHealthy(green);
            return green ? Health.up().build() : Health.down().build();
        } catch (RuntimeException failure) {
            metrics.migrationHealthy(false);
            return Health.down().build();
        }
    }
}
