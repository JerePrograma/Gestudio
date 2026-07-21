package gestudio.infra.observabilidad;

import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.security.web.access.intercept.RequestAuthorizationContext;

import static org.assertj.core.api.Assertions.assertThat;

class MetricsTokenAuthorizationManagerTest {

    @Test
    void aceptaSolamenteElTokenConfiguradoExacto() {
        MetricsTokenAuthorizationManager manager =
                new MetricsTokenAuthorizationManager("metrics-secret");

        assertThat(decision(manager, "metrics-secret")).isTrue();
        assertThat(decision(manager, "wrong-secret")).isFalse();
        assertThat(decision(manager, " metrics-secret")).isFalse();
        assertThat(decision(manager, "metrics-secret ")).isFalse();
        assertThat(decision(manager, null)).isFalse();
    }

    @Test
    void tokenVacioMantienePrometheusCerrado() {
        MetricsTokenAuthorizationManager manager =
                new MetricsTokenAuthorizationManager("   ");

        assertThat(decision(manager, "anything")).isFalse();
        assertThat(decision(manager, "")).isFalse();
    }

    @Test
    void rechazaTokensExcesivamenteLargos() {
        MetricsTokenAuthorizationManager manager =
                new MetricsTokenAuthorizationManager("metrics-secret");

        assertThat(decision(manager, "x".repeat(513))).isFalse();
    }

    private static boolean decision(MetricsTokenAuthorizationManager manager, String token) {
        MockHttpServletRequest request = new MockHttpServletRequest();
        if (token != null) {
            request.addHeader(MetricsTokenAuthorizationManager.HEADER_NAME, token);
        }
        return manager.check(() -> null, new RequestAuthorizationContext(request)).isGranted();
    }
}
