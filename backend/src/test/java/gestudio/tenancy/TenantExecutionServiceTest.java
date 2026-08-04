package gestudio.tenancy;

import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class TenantExecutionServiceTest {

    @Test
    void reconstruyeYLimpiaContextoYUnFalloNoOmiteElTenantSiguiente() {
        TenantRepository repository = mock(TenantRepository.class);
        UUID first = UUID.randomUUID();
        UUID second = UUID.randomUUID();
        when(repository.findAllActiveIds()).thenReturn(List.of(first, second));
        SimpleMeterRegistry registry = new SimpleMeterRegistry();
        TenantExecutionService execution = new TenantExecutionService(
                repository, new TenantMetrics(registry));
        List<UUID> visited = new ArrayList<>();

        execution.forEachActiveTenant("receipts", tenantId -> {
            visited.add(TenantContext.requireTenantId());
            if (tenantId.equals(first)) throw new IllegalStateException("synthetic");
        });

        assertThat(visited).containsExactly(first, second);
        assertThat(TenantContext.currentTenantId()).isEmpty();
        assertThat(registry.get("gestudio_tenant_job_total")
                .tag("job_type", "receipts").tag("result", "failure").counter().count()).isOne();
        assertThat(registry.get("gestudio_tenant_job_total")
                .tag("job_type", "receipts").tag("result", "success").counter().count()).isOne();
    }
}
