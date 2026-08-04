package gestudio.tenancy;

import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class TenantMetricsTest {

    @Test
    void publicaSoloDimensionesAcotadasSinTenantNiPii() {
        SimpleMeterRegistry registry = new SimpleMeterRegistry();
        TenantMetrics metrics = new TenantMetrics(registry);

        metrics.resolution("denied", "membership_suspended");
        metrics.crossScopeBlocked("read", "payment");
        metrics.job("monthly_fees", "success");
        metrics.migrationHealthy(true);

        assertThat(registry.getMeters()).allSatisfy(meter ->
                assertThat(meter.getId().getTags()).allSatisfy(tag ->
                        assertThat(tag.getKey()).isIn(
                                "result", "reason", "operation", "resource_type", "job_type")));
        assertThat(registry.get("gestudio_tenant_migration_health").gauge().value()).isEqualTo(1);
    }
}
