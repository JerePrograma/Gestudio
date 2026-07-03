package ledance.infra.seguridad;

import org.junit.jupiter.api.Test;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.context.annotation.Configuration;

import static org.assertj.core.api.Assertions.assertThat;

class JwtPropertiesContextTest {

    private final ApplicationContextRunner runner = new ApplicationContextRunner()
            .withUserConfiguration(JwtConfiguration.class)
            .withPropertyValues(
                    "jwt.issuer=le-dance-test",
                    "jwt.audience=le-dance-web",
                    "jwt.access-token-ttl=PT2H",
                    "jwt.refresh-token-ttl=P7D"
            );

    @Test
    void secretoAusenteEnProdImpideIniciar() {
        runner
                .withInitializer(context -> context.getEnvironment().setActiveProfiles("prod"))
                .run(context -> assertThat(context).hasFailed());
    }

    @Test
    void configuracionJwtInvalidaImpideIniciar() {
        runner
                .withPropertyValues("jwt.secret=short")
                .run(context -> assertThat(context).hasFailed());
    }

    @Test
    void configuracionJwtValidaInicia() {
        runner
                .withPropertyValues("jwt.secret=test-only-secret-with-at-least-32-characters")
                .run(context -> assertThat(context).hasNotFailed());
    }

    @Configuration(proxyBeanMethods = false)
    @EnableConfigurationProperties(JwtProperties.class)
    static class JwtConfiguration {
    }
}
