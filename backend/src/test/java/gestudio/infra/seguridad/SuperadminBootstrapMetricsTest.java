package gestudio.infra.seguridad;

import gestudio.platform.PlatformMetrics;
import gestudio.platform.control.PlatformAuditService;
import gestudio.platform.security.PlatformMfaService;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.transaction.PlatformTransactionManager;

import java.time.Clock;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;

class SuperadminBootstrapMetricsTest {

    @Test
    void rejectedBootstrapPublishesOnlyBoundedFailureSeries() {
        SimpleMeterRegistry registry = new SimpleMeterRegistry();
        SuperadminBootstrapService service = new SuperadminBootstrapService(
                mock(JdbcTemplate.class), mock(PasswordEncoder.class), mock(PasswordPolicy.class),
                mock(PlatformMfaService.class), mock(PlatformAuditService.class),
                new PlatformMetrics(registry), Clock.systemUTC(),
                mock(PlatformTransactionManager.class));

        assertThatThrownBy(() -> service.bootstrap("bad username", "unused", "unused", "unused",
                ignored -> { }))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("USERNAME");

        assertThat(registry.get(PlatformMetrics.BOOTSTRAP_EVENTS)
                .tag("result", "failed").counter().count()).isEqualTo(1);
        assertThat(registry.get(PlatformMetrics.BOOTSTRAP_EVENTS)
                .tag("result", "success").counter().count()).isZero();
        assertThat(registry.get(PlatformMetrics.PROVISIONING_FAILURES)
                .tags("resource", "bootstrap", "reason", "invalid_request")
                .counter().count()).isEqualTo(1);
    }
}
