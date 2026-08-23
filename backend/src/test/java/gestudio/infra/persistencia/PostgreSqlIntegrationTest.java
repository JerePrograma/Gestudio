package gestudio.infra.persistencia;

import gestudio.tenancy.TenantContext;
import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.MigrationVersion;
import org.flywaydb.core.api.configuration.FluentConfiguration;
import org.flywaydb.core.api.migration.baseline.BaselineMigrationConfigurationExtension;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.BeforeEach;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.annotation.DirtiesContext;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.context.transaction.BeforeTransaction;
import org.testcontainers.postgresql.PostgreSQLContainer;

import java.util.UUID;
import java.util.concurrent.Callable;

import static org.assertj.core.api.Assertions.assertThat;

@ActiveProfiles("test")
@DirtiesContext(classMode = DirtiesContext.ClassMode.AFTER_CLASS)
public abstract class PostgreSqlIntegrationTest {
    private static final String DISABLED_BASELINE_MIGRATION_PREFIX = "X_DISABLED_BASELINE";

    protected static final UUID DEFAULT_TENANT_ID =
            UUID.fromString("00000000-0000-0000-0000-000000000001");

    private TenantContext.Scope tenantScope;

    protected static final PostgreSQLContainer POSTGRESQL =
            new PostgreSQLContainer("postgres:15.18-alpine3.24")
                    .withDatabaseName("gestudio_phase4a")
                    .withUsername("phase4a")
                    .withPassword("phase4a");

    static {
        POSTGRESQL.start();
        versionedFlyway(POSTGRESQL.getJdbcUrl()).migrate();
    }

    @DynamicPropertySource
    static void postgresqlProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRESQL::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRESQL::getUsername);
        registry.add("spring.datasource.password", POSTGRESQL::getPassword);
        registry.add("spring.flyway.enabled", () -> false);
        registry.add("app.platform-datasource.url", POSTGRESQL::getJdbcUrl);
        registry.add("app.platform-datasource.username", POSTGRESQL::getUsername);
        registry.add("app.platform-datasource.password", POSTGRESQL::getPassword);
    }

    protected static Flyway versionedFlyway(String jdbcUrl) {
        return versionedFlyway(jdbcUrl, null);
    }

    protected static Flyway versionedFlyway(String jdbcUrl, MigrationVersion target) {
        FluentConfiguration configuration = Flyway.configure()
                .dataSource(jdbcUrl, POSTGRESQL.getUsername(), POSTGRESQL.getPassword())
                .schemas("public")
                .defaultSchema("public");
        if (target != null) {
            configuration.target(target);
        }
        Flyway flyway = configuration.load();
        flyway.getConfigurationExtension(BaselineMigrationConfigurationExtension.class)
                .setBaselineMigrationPrefix(DISABLED_BASELINE_MIGRATION_PREFIX);
        return flyway;
    }

    @BeforeTransaction
    protected void openTenantContextBeforeTransaction() {
        selectMembership(null);
    }

    @BeforeEach
    protected void openTenantContext() {
        selectMembership(null);
    }

    @AfterEach
    protected void closeTenantContext() {
        if (tenantScope != null) {
            tenantScope.close();
            tenantScope = null;
        }
    }

    protected final Long defaultRoleId(JdbcTemplate jdbc, String code) {
        if (jdbc == null || code == null || code.isBlank()) {
            throw new IllegalArgumentException("JdbcTemplate y código de rol son obligatorios");
        }

        Long roleId = jdbc.queryForObject("""
                SELECT id
                FROM roles
                WHERE tenant_id = ?
                  AND codigo = ?
                """, Long.class, DEFAULT_TENANT_ID, code);

        if (roleId == null) {
            throw new IllegalStateException("El rol de test no devolvió id: " + code);
        }
        return roleId;
    }

    protected final UUID createActiveMembership(
            JdbcTemplate jdbc,
            Long userId,
            Long roleId
    ) {
        if (jdbc == null || userId == null || roleId == null) {
            throw new IllegalArgumentException("JdbcTemplate, userId y roleId son obligatorios");
        }

        UUID candidateId = UUID.randomUUID();

        jdbc.update("""
                INSERT INTO tenant_memberships(
                    id, tenant_id, usuario_id, status, security_version)
                VALUES (?, ?, ?, 'ACTIVE', 0)
                ON CONFLICT (tenant_id, usuario_id) DO UPDATE
                SET status = 'ACTIVE',
                    valid_until = NULL,
                    updated_at = CURRENT_TIMESTAMP
                """, candidateId, DEFAULT_TENANT_ID, userId);

        UUID membershipId = jdbc.queryForObject("""
                SELECT id
                FROM tenant_memberships
                WHERE tenant_id = ?
                  AND usuario_id = ?
                """, UUID.class, DEFAULT_TENANT_ID, userId);

        if (membershipId == null) {
            throw new IllegalStateException("La membership de test no devolvió id");
        }

        jdbc.update("""
                INSERT INTO tenant_membership_roles(
                    membership_id, tenant_id, role_id)
                VALUES (?, ?, ?)
                ON CONFLICT (membership_id, role_id) DO NOTHING
                """, membershipId, DEFAULT_TENANT_ID, roleId);

        return membershipId;
    }

    protected final void selectMembership(UUID membershipId) {
        if (tenantScope != null) {
            tenantScope.close();
        }

        tenantScope = TenantContext.open(DEFAULT_TENANT_ID, membershipId);
    }

    protected static <T> T withTenant(Callable<T> operation) throws Exception {
        try (TenantContext.Scope ignored =
                     TenantContext.open(DEFAULT_TENANT_ID, null)) {
            return operation.call();
        }
    }

    protected static <T> T withTenant(
            UUID membershipId,
            Callable<T> operation
    ) throws Exception {
        if (membershipId == null) {
            throw new IllegalArgumentException("membershipId es obligatorio");
        }

        try (TenantContext.Scope ignored =
                     TenantContext.open(DEFAULT_TENANT_ID, membershipId)) {
            return operation.call();
        }
    }

    @BeforeAll
    static void requireIsolatedRandomPort() {
        assertThat(POSTGRESQL.getMappedPort(PostgreSQLContainer.POSTGRESQL_PORT))
                .as("PostgreSQL de test no debe usar localhost:5432")
                .isNotEqualTo(PostgreSQLContainer.POSTGRESQL_PORT);
    }
}
