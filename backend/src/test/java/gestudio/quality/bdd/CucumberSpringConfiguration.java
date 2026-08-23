package gestudio.quality.bdd;

import io.cucumber.spring.CucumberContextConfiguration;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.postgresql.PostgreSQLContainer;

import java.nio.charset.StandardCharsets;
import java.util.Base64;

@CucumberContextConfiguration
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class CucumberSpringConfiguration {
    private static final PostgreSQLContainer POSTGRESQL =
            new PostgreSQLContainer("postgres:15.18-alpine3.24")
                    .withDatabaseName("gestudio_bdd")
                    .withUsername("gestudio_bdd")
                    .withPassword("synthetic-bdd-database-password");

    static {
        POSTGRESQL.start();
    }

    @DynamicPropertySource
    static void properties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRESQL::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRESQL::getUsername);
        registry.add("spring.datasource.password", POSTGRESQL::getPassword);
        registry.add("spring.flyway.enabled", () -> true);
        registry.add("spring.flyway.baseline-on-migrate", () -> false);
        registry.add("app.platform-datasource.url", POSTGRESQL::getJdbcUrl);
        registry.add("app.platform-datasource.username", POSTGRESQL::getUsername);
        registry.add("app.platform-datasource.password", POSTGRESQL::getPassword);
        registry.add("app.platform-security.mfa-encryption-key", () ->
                Base64.getEncoder().encodeToString(
                        "quality-fortress-synthetic-key32".getBytes(StandardCharsets.US_ASCII)));
        registry.add("app.platform-security.refresh-cookie.secure", () -> false);
    }
}
