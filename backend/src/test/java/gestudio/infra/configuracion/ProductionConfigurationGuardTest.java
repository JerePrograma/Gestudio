package gestudio.infra.configuracion;

import gestudio.Main;
import gestudio.infra.seguridad.SecurityProperties;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.support.BeanDefinitionRegistry;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.context.annotation.ClassPathBeanDefinitionScanner;

import java.nio.file.Path;
import java.time.ZoneId;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
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

    @Test
    void descubreLaGuardaPublicaDesdeElPaqueteDeMain() {
        for (String profile : List.of("prod", "remote-demo")) {
            scannedGuard(profile, "https://app.example.test").run(context -> {
                assertThat(context).hasNotFailed();
                assertThat(context).hasSingleBean(ProductionConfigurationGuard.class);
            });
        }
    }

    @Test
    void elEscaneoRespetaElPerfilYRechazaConfiguracionPublicaInsegura() {
        scannedGuard("dev", "http://localhost:5173").run(context -> {
            assertThat(context).hasNotFailed();
            assertThat(context).doesNotHaveBean(ProductionConfigurationGuard.class);
        });
        scannedGuard("prod", "http://app.example.test").run(context -> {
            assertThat(context).hasFailed();
            assertThat(context.getStartupFailure()).hasStackTraceContaining("CORS HTTPS");
        });
    }

    private ApplicationContextRunner scannedGuard(String profile, String origin) {
        return new ApplicationContextRunner()
                .withBean(AppProperties.class, () -> app(origin))
                .withBean(SecurityProperties.class, () -> security(true))
                .withPropertyValues("app.observability.metrics-token=" + METRICS_TOKEN)
                .withInitializer(context -> {
                    context.getEnvironment().setActiveProfiles(profile);
                    ClassPathBeanDefinitionScanner scanner = new ClassPathBeanDefinitionScanner(
                            (BeanDefinitionRegistry) context);
                    // Keep Spring's default component filters and real profile
                    // conditions; exclude unrelated infrastructure to avoid a DB.
                    scanner.addExcludeFilter((metadata, factory) -> !metadata.getClassMetadata()
                            .getClassName().equals(ProductionConfigurationGuard.class.getName()));
                    scanner.scan(Main.class.getPackageName());
                });
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
