package gestudio.platform;

import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.Test;

import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;

class PlatformMetricsTest {

    @Test
    void publishesRequiredCountersWithOnlyBoundedNonIdentifyingLabels() {
        SimpleMeterRegistry registry = new SimpleMeterRegistry();
        PlatformMetrics metrics = new PlatformMetrics(registry);

        metrics.tenantEvent(PlatformMetrics.TenantEvent.CREATED);
        metrics.membershipEvent(PlatformMetrics.MembershipEvent.REVOKED);
        metrics.bootstrap(PlatformMetrics.BootstrapResult.SUCCESS);
        metrics.mfa(PlatformMetrics.MfaMethod.TOTP, PlatformMetrics.MfaResult.FAILURE);
        metrics.authFailure(PlatformMetrics.AuthOperation.LOGIN,
                PlatformMetrics.AuthFailureReason.INVALID_CREDENTIALS);
        metrics.authorizationDenied(PlatformMetrics.AuthorizationReason.CROSS_SCOPE,
                PlatformMetrics.Scope.TENANT, PlatformMetrics.Scope.PLATFORM);
        metrics.provisioningFailure(PlatformMetrics.ProvisioningResource.TENANT,
                PlatformMetrics.ProvisioningFailureReason.DATABASE);

        assertThat(registry.get(PlatformMetrics.TENANT_EVENTS)
                .tag("event", "created").counter().count()).isEqualTo(1);
        assertThat(registry.get(PlatformMetrics.MEMBERSHIP_EVENTS)
                .tag("event", "revoked").counter().count()).isEqualTo(1);
        assertThat(registry.get(PlatformMetrics.BOOTSTRAP_EVENTS)
                .tag("result", "success").counter().count()).isEqualTo(1);
        assertThat(registry.get(PlatformMetrics.MFA_EVENTS)
                .tags("method", "totp", "result", "failure").counter().count()).isEqualTo(1);
        assertThat(registry.get(PlatformMetrics.AUTH_FAILURES)
                .tags("operation", "login", "reason", "invalid_credentials")
                .counter().count()).isEqualTo(1);
        assertThat(registry.get(PlatformMetrics.AUTHORIZATION_DENIALS)
                .tags("reason", "cross_scope", "source_scope", "tenant",
                        "target_scope", "platform").counter().count()).isEqualTo(1);
        assertThat(registry.get(PlatformMetrics.PROVISIONING_FAILURES)
                .tags("resource", "tenant", "reason", "database")
                .counter().count()).isEqualTo(1);

        Set<String> allowed = Set.of("event", "result", "method", "operation", "reason",
                "source_scope", "target_scope", "resource");
        assertThat(registry.getMeters()).allSatisfy(meter ->
                assertThat(meter.getId().getTags()).allSatisfy(tag ->
                        assertThat(tag.getKey()).isIn(allowed)));
    }
}
