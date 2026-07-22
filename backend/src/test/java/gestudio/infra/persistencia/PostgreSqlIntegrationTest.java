package gestudio.infra.persistencia;

import org.junit.jupiter.api.BeforeAll;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.PostgreSQLContainer;

import static org.assertj.core.api.Assertions.assertThat;

@ActiveProfiles("test")
public abstract class PostgreSqlIntegrationTest {

    protected static final PostgreSQLContainer<?> POSTGRESQL =
            new PostgreSQLContainer<>("postgres:15.18-alpine3.24")
                    .withDatabaseName("gestudio_phase4a")
                    .withUsername("phase4a")
                    .withPassword("phase4a");

    static {
        POSTGRESQL.start();
    }

    @DynamicPropertySource
    static void postgresqlProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRESQL::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRESQL::getUsername);
        registry.add("spring.datasource.password", POSTGRESQL::getPassword);
        registry.add("spring.flyway.enabled", () -> true);
        registry.add("spring.flyway.baseline-on-migrate", () -> false);
        registry.add("spring.flyway.default-schema", () -> "public");
        registry.add("spring.flyway.schemas", () -> "public");
    }

    @BeforeAll
    static void requireIsolatedRandomPort() {
        assertThat(POSTGRESQL.getMappedPort(PostgreSQLContainer.POSTGRESQL_PORT))
                .as("PostgreSQL de test no debe usar localhost:5432")
                .isNotEqualTo(PostgreSQLContainer.POSTGRESQL_PORT);
    }
}
