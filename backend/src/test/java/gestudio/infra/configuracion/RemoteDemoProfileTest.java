package gestudio.infra.configuracion;

import gestudio.infra.seguridad.RemoteDemoProxyTokenFilter;
import gestudio.infra.seguridad.SecurityProperties;
import gestudio.servicios.email.EmailService;
import gestudio.servicios.email.IEmailService;
import gestudio.servicios.email.NoOpEmailService;
import org.junit.jupiter.api.Test;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.boot.env.YamlPropertySourceLoader;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Import;
import org.springframework.context.annotation.Profile;
import org.springframework.core.env.PropertySource;
import org.springframework.core.io.ClassPathResource;

import java.io.IOException;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class RemoteDemoProfileTest {

    private static final String METRICS_TOKEN = "metrics-token-independent-with-32-bytes";
    private static final String PROXY_TOKEN = "pages-proxy-token-independent-32-bytes";

    private final ApplicationContextRunner contextRunner = new ApplicationContextRunner()
            .withInitializer(context -> context.getEnvironment().setActiveProfiles("remote-demo"))
            .withUserConfiguration(RemoteDemoTestConfiguration.class)
            .withPropertyValues(
                    "app.time-zone=America/Argentina/Buenos_Aires",
                    "app.receipts-path=receipts",
                    "app.cors-allowed-origins=https://app.example.test",
                    "app.remote-demo.proxy-token=" + PROXY_TOKEN,
                    "app.observability.metrics-token=" + METRICS_TOKEN,
                    "app.security.bcrypt-strength=12",
                    "app.security.refresh-cookie.name=gestudio_remote_demo_refresh",
                    "app.security.refresh-cookie.secure=true",
                    "app.security.refresh-cookie.same-site=Strict",
                    "app.security.refresh-cookie.domain=",
                    "app.security.refresh-cookie.path=/api/login");

    @Test
    void activaGuardasPublicasProxyAutenticadoYEmailNoOp() {
        contextRunner.run(context -> {
            assertThat(context).hasNotFailed();
            assertThat(context).hasSingleBean(ProductionConfigurationGuard.class);
            assertThat(context).hasSingleBean(RemoteDemoProxyTokenFilter.class);
            assertThat(context).hasSingleBean(IEmailService.class);
            assertThat(context).hasSingleBean(NoOpEmailService.class);
        });

        Profile guardProfile = ProductionConfigurationGuard.class.getAnnotation(Profile.class);
        assertThat(guardProfile).isNotNull();
        assertThat(guardProfile.value()).containsExactlyInAnyOrder("prod", "remote-demo");

        Profile proxyProfile = RemoteDemoProxyTokenFilter.class.getAnnotation(Profile.class);
        assertThat(proxyProfile).isNotNull();
        assertThat(proxyProfile.value()).containsExactly("remote-demo");

        Profile noOpProfile = NoOpEmailService.class.getAnnotation(Profile.class);
        assertThat(noOpProfile).isNotNull();
        assertThat(noOpProfile.value()).contains("!prod");

        Profile emailProfile = EmailService.class.getAnnotation(Profile.class);
        assertThat(emailProfile).isNotNull();
        assertThat(emailProfile.value()).containsExactly("prod");
    }

    @Test
    void fallaCerradoConCorsCookieMetricasOProxyInseguros() {
        assertStartupFailure(
                contextRunner.withPropertyValues("app.cors-allowed-origins=http://app.example.test"),
                "CORS HTTPS");
        assertStartupFailure(
                contextRunner.withPropertyValues("app.security.refresh-cookie.secure=false"),
                "cookie de refresh Secure");
        assertStartupFailure(
                contextRunner.withPropertyValues("app.observability.metrics-token=short"),
                "token de métricas");
        assertStartupFailure(
                contextRunner.withPropertyValues("app.remote-demo.proxy-token=short"),
                "token de proxy");
    }

    @Test
    void declaraConfiguracionRemotaSinCorreoProductivo() throws IOException {
        List<PropertySource<?>> sources = new YamlPropertySourceLoader().load(
                "remote-demo",
                new ClassPathResource("application-remote-demo.yml"));

        assertThat(sources).hasSize(1);
        PropertySource<?> source = sources.getFirst();
        assertThat(source.getProperty("spring.config.activate.on-profile")).isEqualTo("remote-demo");
        assertThat(source.getProperty("spring.datasource.url")).isEqualTo("${SPRING_DATASOURCE_URL}");
        assertThat(source.getProperty("spring.jpa.hibernate.ddl-auto")).isEqualTo("validate");
        assertThat(source.getProperty("spring.flyway.enabled")).isEqualTo(true);
        assertThat(source.getProperty("app.scheduling-enabled")).isEqualTo(false);
        assertThat(source.getProperty("app.remote-demo.proxy-token"))
                .isEqualTo("${APP_REMOTE_DEMO_PROXY_TOKEN}");
        assertThat(source.getProperty("app.security.refresh-cookie.secure"))
                .isEqualTo("${APP_SECURITY_REFRESH_COOKIE_SECURE:true}");
        assertThat(source.getProperty("app.observability.metrics-token"))
                .isEqualTo("${APP_OBSERVABILITY_METRICS_TOKEN}");
        assertThat(source.getProperty("spring.mail.host")).isNull();
        assertThat(source.getProperty("spring.mail.imap.host")).isNull();
    }

    private void assertStartupFailure(ApplicationContextRunner runner, String expectedMessage) {
        runner.run(context -> {
            assertThat(context).hasFailed();
            Throwable rootCause = rootCause(context.getStartupFailure());
            assertThat(rootCause)
                    .isInstanceOf(IllegalStateException.class)
                    .hasMessageContaining(expectedMessage);
        });
    }

    private Throwable rootCause(Throwable failure) {
        Throwable current = failure;
        while (current.getCause() != null) current = current.getCause();
        return current;
    }

    @Configuration(proxyBeanMethods = false)
    @EnableConfigurationProperties({AppProperties.class, SecurityProperties.class})
    @Import({
            ProductionConfigurationGuard.class,
            RemoteDemoProxyTokenFilter.class,
            NoOpEmailService.class
    })
    static class RemoteDemoTestConfiguration {
    }
}
