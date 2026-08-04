package gestudio.tenancy;

import org.junit.jupiter.api.Test;

import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class TenantContextTest {
    @Test
    void scopesAnidadosRestauranElAnteriorYElBordeLimpiaElThread() {
        UUID first = UUID.randomUUID();
        UUID second = UUID.randomUUID();
        UUID membership = UUID.randomUUID();

        try (TenantContext.Scope ignored = TenantContext.open(first, membership)) {
            assertThat(TenantContext.requireTenantId()).isEqualTo(first);
            assertThat(TenantContext.currentMembershipId()).contains(membership);
            try (TenantContext.Scope nested = TenantContext.open(second, null)) {
                assertThat(TenantContext.requireTenantId()).isEqualTo(second);
                assertThat(TenantContext.currentMembershipId()).isEmpty();
            }
            assertThat(TenantContext.requireTenantId()).isEqualTo(first);
        }

        assertThat(TenantContext.currentTenantId()).isEmpty();
        assertThatThrownBy(TenantContext::requireTenantId).isInstanceOf(IllegalStateException.class);
    }
}
