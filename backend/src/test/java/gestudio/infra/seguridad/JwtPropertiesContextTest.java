package gestudio.infra.seguridad;

import org.junit.jupiter.api.Test;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.context.annotation.Configuration;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class JwtPropertiesContextTest {

    private final ApplicationContextRunner runner = new ApplicationContextRunner()
            .withUserConfiguration(JwtConfiguration.class)
            .withPropertyValues(
                    "jwt.issuer=gestudio-test",
                    "jwt.audience=gestudio-web",
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
                .run(context -> {
                    assertThat(context).hasNotFailed();
                    JwtProperties properties = context.getBean(JwtProperties.class);
                    assertThat(properties.accessTokenTtl()).isEqualTo(Duration.ofHours(2));
                    assertThat(properties.refreshTokenTtl()).isEqualTo(Duration.ofDays(7));
                });
    }

    @Test
    void despliegueUsaTtlDurationYCookieSeguraEnProduccion() throws IOException {
        Path root = repositoryRoot();
        String compose = Files.readString(root.resolve("docker-compose.yml"));
        String prodCompose = Files.readString(root.resolve("docker-compose.prod.yml"));
        String prodConfig = Files.readString(root.resolve("backend/src/main/resources/application-prod.yml"));

        assertThat(compose).contains(
                "JWT_ACCESS_TOKEN_TTL: ${JWT_ACCESS_TOKEN_TTL:-PT15M}",
                "JWT_REFRESH_TOKEN_TTL: ${JWT_REFRESH_TOKEN_TTL:-P7D}"
        );
        assertThat(prodCompose).contains(
                "JWT_ACCESS_TOKEN_TTL: ${JWT_ACCESS_TOKEN_TTL:?JWT_ACCESS_TOKEN_TTL is required}",
                "JWT_REFRESH_TOKEN_TTL: ${JWT_REFRESH_TOKEN_TTL:?JWT_REFRESH_TOKEN_TTL is required}",
                "APP_SECURITY_REFRESH_COOKIE_SECURE: \"true\""
        );
        assertThat(prodConfig).contains(
                "access-token-ttl: ${JWT_ACCESS_TOKEN_TTL}",
                "refresh-token-ttl: ${JWT_REFRESH_TOKEN_TTL}"
        );

        for (String relative : List.of(
                "docker-compose.yml",
                "docker-compose.prod.yml",
                "backend/src/main/resources/application-prod.yml",
                ".env.example",
                ".env.local.example",
                "docs/development/environment-variables.md",
                ".github/workflows/ci.yml"
        )) {
            assertThat(Files.readString(root.resolve(relative)))
                    .as("contrato JWT en %s", relative)
                    .doesNotContain("JWT_ACCESS_TOKEN_HOURS", "JWT_REFRESH_TOKEN_HOURS");
        }
    }

    private Path repositoryRoot() {
        Path current = Path.of(System.getProperty("user.dir")).toAbsolutePath().normalize();
        return current.getFileName().toString().equals("backend") ? current.getParent() : current;
    }

    @Configuration(proxyBeanMethods = false)
    @EnableConfigurationProperties(JwtProperties.class)
    static class JwtConfiguration {
    }
}
