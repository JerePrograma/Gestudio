package gestudio.infra.configuracion;

import gestudio.infra.seguridad.SecurityProperties;
import org.junit.jupiter.api.Test;

import java.nio.file.Path;
import java.time.ZoneId;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class ProductionConfigurationGuardTest {

    private static final String METRICS_TOKEN = "metrics-token-independent-with-32-bytes";

    @Test
    void aceptaConfiguracionProductivaCerrada() {
        assertThatCode(() -> new ProductionConfigurationGuard(
                app("https://app.example.test"), security(true), METRICS_TOKEN))
                .doesNotThrowAnyException();
    }

    @Test
    void rechazaCorsNoSeguroOWildcard() {
        assertThatThrownBy(() -> new ProductionConfigurationGuard(
                app("http://app.example.test"), security(true), METRICS_TOKEN))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("CORS HTTPS");
        assertThatThrownBy(() -> new ProductionConfigurationGuard(
                app("https://*.example.test"), security(true), METRICS_TOKEN))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("CORS HTTPS");
        assertThatThrownBy(() -> new ProductionConfigurationGuard(
                app("https://app.example.test/path"), security(true), METRICS_TOKEN))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("CORS HTTPS");
    }

    @Test
    void rechazaCookieInseguraYTokenDeMetricasDebil() {
        assertThatThrownBy(() -> new ProductionConfigurationGuard(
                app("https://app.example.test"), security(false), METRICS_TOKEN))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("cookie de refresh Secure");
        assertThatThrownBy(() -> new ProductionConfigurationGuard(
                app("https://app.example.test"), security(true), "short"))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("token de métricas");
    }

    private AppProperties app(String origin) {
        return new AppProperties(
                ZoneId.of("America/Argentina/Buenos_Aires"),
                Path.of("receipts"),
                List.of(origin));
    }

    private SecurityProperties security(boolean secure) {
        return new SecurityProperties(12,
                new SecurityProperties.RefreshCookie("gestudio_refresh", secure, "Strict", "", "/api/login"));
    }
}
