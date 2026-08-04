package gestudio.infra.persistencia;

import gestudio.tenancy.TenantContext;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.BeforeEach;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.PostgreSQLContainer;

import java.util.UUID;
import java.util.concurrent.Callable;

import static org.assertj.core.api.Assertions.assertThat;

@ActiveProfiles("test")
public abstract class PostgreSqlIntegrationTest {

    protected static final UUID DEFAULT_TENANT_ID =
            UUID.fromString("00000000-0000-0000-0000-000000000001");

    private TenantContext.Scope tenantScope;

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
