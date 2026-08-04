package gestudio.tenancy;

import org.springframework.stereotype.Service;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.Objects;
import java.util.UUID;
import java.util.function.Consumer;

@Service
public class TenantExecutionService {
    private static final Logger log = LoggerFactory.getLogger(TenantExecutionService.class);
    private final TenantRepository tenants;
    private final TenantMetrics metrics;

    public TenantExecutionService(TenantRepository tenants, TenantMetrics metrics) {
        this.tenants = tenants;
        this.metrics = metrics;
    }

    public void forEachActiveTenant(String operation, Consumer<UUID> work) {
        Objects.requireNonNull(operation, "operation");
        Objects.requireNonNull(work, "work");
        for (UUID tenantId : tenants.findAllActiveIds()) {
            try (TenantContext.Scope ignored = TenantContext.open(tenantId, null)) {
                work.accept(tenantId);
                metrics.job(operation, "success");
            } catch (RuntimeException failure) {
                metrics.job(operation, "failure");
                log.error("tenant_job operation={} result=failure type={}",
                        operation, failure.getClass().getSimpleName());
            }
        }
    }
}
