package gestudio.tenancy;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.stereotype.Component;

import java.util.concurrent.atomic.AtomicInteger;

@Component
public class TenantMetrics {
    private final MeterRegistry registry;
    private final AtomicInteger migrationHealth = new AtomicInteger();

    public TenantMetrics(MeterRegistry registry) {
        this.registry = registry;
        registry.gauge("gestudio_tenant_migration_health", migrationHealth);
    }

    public void resolution(String result, String reason) {
        counter("gestudio_tenant_resolution_total", "result", result, "reason", reason).increment();
    }

    public void accessDenied(String reason, String operation) {
        counter("gestudio_tenant_access_denied_total", "reason", reason, "operation", operation).increment();
    }

    public void contextMissing(String operation, String resourceType) {
        counter("gestudio_tenant_context_missing_total", "operation", operation,
                "resource_type", resourceType).increment();
    }

    public void crossScopeBlocked(String operation, String resourceType) {
        counter("gestudio_tenant_cross_scope_blocked_total", "operation", operation,
                "resource_type", resourceType).increment();
    }

    public void job(String jobType, String result) {
        counter("gestudio_tenant_job_total", "job_type", jobType, "result", result).increment();
    }

    public void migrationHealthy(boolean healthy) {
        migrationHealth.set(healthy ? 1 : 0);
    }

    private Counter counter(String name, String firstKey, String firstValue,
                            String secondKey, String secondValue) {
        return Counter.builder(name)
                .tag(firstKey, firstValue)
                .tag(secondKey, secondValue)
                .register(registry);
    }
}
