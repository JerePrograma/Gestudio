package gestudio.infra.seguridad;

import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import gestudio.dto.request.LoginRequest;
import gestudio.tenancy.TenantAwareDataSource;
import gestudio.tenancy.TenantContext;
import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.configuration.FluentConfiguration;
import org.flywaydb.core.api.migration.baseline.BaselineMigrationConfigurationExtension;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.postgresql.PostgreSQLContainer;

import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicReference;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.catchThrowableOfType;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.NONE)
@ActiveProfiles("test")
class ApplicationRoleAuthenticationPostgreSqlTest {

    private static final String DISABLED_BASELINE_MIGRATION_PREFIX = "X_DISABLED_BASELINE";

    private static final UUID DEFAULT_TENANT_ID =
            UUID.fromString("00000000-0000-0000-0000-000000000001");
    private static final UUID OTHER_TENANT_ID =
            UUID.fromString("00000000-0000-0000-0000-000000000002");
    private static final UUID INVALID_TENANT_ID =
            UUID.fromString("00000000-0000-0000-0000-000000000099");

    private static final String APP_USERNAME = "gestudio_app_test";
    private static final String APP_PASSWORD = "app-role-test-password";
    private static final String LOGIN_USERNAME = "app-role-login";
    private static final String LOGIN_PASSWORD = "Correcta-1234";

    private static final PostgreSQLContainer POSTGRESQL =
            new PostgreSQLContainer("postgres:15.18-alpine3.24")
                    .withDatabaseName("gestudio_app_role_auth")
                    .withUsername("migration_owner")
                    .withPassword("migration-owner-password");

    static {
        POSTGRESQL.start();
        createApplicationRoles();
        versionedFlyway().migrate();
    }

    @DynamicPropertySource
    static void properties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRESQL::getJdbcUrl);
        registry.add("spring.datasource.username", () -> APP_USERNAME);
        registry.add("spring.datasource.password", () -> APP_PASSWORD);

        registry.add("app.platform-datasource.url", POSTGRESQL::getJdbcUrl);
        registry.add("app.platform-datasource.username", POSTGRESQL::getUsername);
        registry.add("app.platform-datasource.password", POSTGRESQL::getPassword);

        registry.add("spring.flyway.enabled", () -> false);
        registry.add("spring.jpa.hibernate.ddl-auto", () -> "validate");

        registry.add(
                "jwt.secret",
                () -> "application-role-auth-test-secret-with-at-least-32-characters"
        );
        registry.add("jwt.issuer", () -> "application-role-auth-test");
        registry.add("jwt.audience", () -> "gestudio-web");
        registry.add("jwt.access-token-ttl", () -> "PT15M");
        registry.add("jwt.refresh-token-ttl", () -> "P7D");

        registry.add("app.multitenancy.required", () -> true);
        registry.add("app.scheduling-enabled", () -> false);
        registry.add("app.email.enabled", () -> false);
        registry.add("app.email.provider", () -> "NOOP");
        registry.add("app.email.dry-run", () -> true);
        registry.add("app.email.real-network-allowed", () -> false);
        registry.add("app.email.kill-switch", () -> true);
        registry.add(
                "app.observability.metrics-token",
                () -> "application-role-metrics-token-with-at-least-32-characters"
        );
    }

    private final AutenticacionService autenticacion;
    private final SecurityFilter securityFilter;
    private final PasswordEncoder passwordEncoder;

    @Autowired
    ApplicationRoleAuthenticationPostgreSqlTest(
            AutenticacionService autenticacion,
            SecurityFilter securityFilter,
            PasswordEncoder passwordEncoder
    ) {
        this.autenticacion = autenticacion;
        this.securityFilter = securityFilter;
        this.passwordEncoder = passwordEncoder;
    }

    @BeforeEach
    void seedUserAndMembership() throws Exception {
        try (Connection connection = ownerConnection()) {
            connection.setAutoCommit(false);

            long roleId = requireRoleId(connection, "SUPERADMIN");
            long userId = insertUser(
                    connection,
                    roleId,
                    passwordEncoder.encode(LOGIN_PASSWORD)
            );

            insertMembership(connection, DEFAULT_TENANT_ID, userId, roleId);

            try (PreparedStatement statement = connection.prepareStatement("""
                    INSERT INTO tenants(id, code, name, status)
                    VALUES (?, 'academia-secundaria', 'Academia secundaria', 'ACTIVE')
                    """)) {
                statement.setObject(1, OTHER_TENANT_ID);
                statement.executeUpdate();
            }

            long secondaryRoleId;
            try (PreparedStatement statement = connection.prepareStatement("""
                    INSERT INTO roles(
                        tenant_id, descripcion, activo, codigo, nombre,
                        descripcion_funcional, sistema, editable
                    ) VALUES (?, 'CAJA', true, 'CAJA', 'Caja', 'Caja secundaria', false, true)
                    RETURNING id
                    """)) {
                statement.setObject(1, OTHER_TENANT_ID);
                try (ResultSet resultSet = statement.executeQuery()) {
                    resultSet.next();
                    secondaryRoleId = resultSet.getLong(1);
                }
            }
            insertMembership(connection, OTHER_TENANT_ID, userId, secondaryRoleId);

            try (PreparedStatement statement = connection.prepareStatement("""
                    INSERT INTO alumnos(
                        tenant_id, nombre, apellido, fecha_incorporacion, documento
                    ) VALUES
                        (?, 'Alumno', 'Tenant inicial', CURRENT_DATE, 'RLS-APP-DEFAULT'),
                        (?, 'Alumno', 'Tenant secundario', CURRENT_DATE, 'RLS-APP-OTHER')
                    """)) {
                statement.setObject(1, DEFAULT_TENANT_ID);
                statement.setObject(2, OTHER_TENANT_ID);
                statement.executeUpdate();
            }

            connection.commit();
        }
    }

    @Test
    void loginAndAccessTokenWorkWithTheRealApplicationDatabaseRole() throws Exception {
        assertThatThrownBy(() -> autenticacion.login(
                new LoginRequest(LOGIN_USERNAME, "Incorrecta-1234"),
                "integration-test",
                "127.0.0.1"
        )).isInstanceOf(BadCredentialsException.class);

        AutenticacionService.Resultado selection = autenticacion.login(
                new LoginRequest(LOGIN_USERNAME, LOGIN_PASSWORD),
                "integration-test",
                "127.0.0.1"
        );
        assertThat(selection.selectionRequired()).isTrue();
        assertThat(selection.accessToken()).isNull();
        assertThat(selection.refreshToken()).isNull();
        assertThat(selection.tenants()).extracting("id")
                .containsExactlyInAnyOrder(DEFAULT_TENANT_ID, OTHER_TENANT_ID);

        AutenticacionService.Resultado result = autenticacion.login(
                new LoginRequest(
                        LOGIN_USERNAME,
                        LOGIN_PASSWORD,
                        DEFAULT_TENANT_ID
                ),
                "integration-test",
                "127.0.0.1"
        );

        assertThat(result.selectionRequired()).isFalse();
        assertThat(result.accessToken()).isNotBlank();
        assertThat(result.refreshToken()).isNotBlank();
        assertThat(result.usuario()).isNotNull();
        assertThat(result.usuario().nombreUsuario()).isEqualTo(LOGIN_USERNAME);
        assertThat(result.usuario().tenantActivo().id()).isEqualTo(DEFAULT_TENANT_ID);
        assertThat(result.usuario().roles()).contains("SUPERADMIN");
        assertAccessTokenAccepted(result.accessToken(), DEFAULT_TENANT_ID, "ROLE_SUPERADMIN");

        AutenticacionService.Resultado refreshed = autenticacion.refresh(
                result.refreshToken(),
                "integration-test",
                "127.0.0.1"
        );
        assertThat(refreshed.refreshToken()).isNotEqualTo(result.refreshToken());
        assertThat(refreshed.usuario().tenantActivo().id()).isEqualTo(DEFAULT_TENANT_ID);
        assertAccessTokenAccepted(refreshed.accessToken(), DEFAULT_TENANT_ID, "ROLE_SUPERADMIN");

        AutenticacionService.Resultado secondary = autenticacion.login(
                new LoginRequest(LOGIN_USERNAME, LOGIN_PASSWORD, OTHER_TENANT_ID),
                "integration-test",
                "127.0.0.1"
        );
        assertThat(secondary.selectionRequired()).isFalse();
        assertThat(secondary.usuario().tenantActivo().id()).isEqualTo(OTHER_TENANT_ID);
        assertThat(secondary.usuario().roles()).containsExactly("CAJA");
        assertAccessTokenAccepted(secondary.accessToken(), OTHER_TENANT_ID, "ROLE_CAJA");

        assertApplicationRolesAreRestrictedAndDoNotOwnSchema();
        assertConnectionReuseDoesNotLeakTenant();
        assertThatThrownBy(() -> autenticacion.login(
                new LoginRequest(LOGIN_USERNAME, LOGIN_PASSWORD, INVALID_TENANT_ID),
                "integration-test",
                "127.0.0.1"
        )).isInstanceOf(BadCredentialsException.class);

        executeAsOwner("""
                UPDATE tenant_memberships
                SET status = 'SUSPENDED', security_version = security_version + 1
                WHERE usuario_id = (
                    SELECT id FROM usuarios WHERE nombre_usuario = 'app-role-login'
                )
                """);
        assertAccessTokenRejected(result.accessToken());
        assertThatThrownBy(() -> autenticacion.login(
                new LoginRequest(LOGIN_USERNAME, LOGIN_PASSWORD, DEFAULT_TENANT_ID),
                "integration-test",
                "127.0.0.1"
        )).isInstanceOf(BadCredentialsException.class);

        executeAsOwner("""
                UPDATE tenant_memberships
                SET status = 'ACTIVE'
                WHERE usuario_id = (
                    SELECT id FROM usuarios WHERE nombre_usuario = 'app-role-login'
                );
                UPDATE roles
                SET activo = false
                WHERE tenant_id = '00000000-0000-0000-0000-000000000001'
                  AND codigo = 'SUPERADMIN'
                """);
        assertThatThrownBy(() -> autenticacion.login(
                new LoginRequest(LOGIN_USERNAME, LOGIN_PASSWORD, DEFAULT_TENANT_ID),
                "integration-test",
                "127.0.0.1"
        )).isInstanceOf(BadCredentialsException.class);
    }

    private void assertAccessTokenAccepted(String token, UUID expectedTenantId,
                                           String expectedAuthority) throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/usuarios/perfil");
        request.setServletPath("/api/usuarios/perfil");
        request.addHeader("Authorization", "Bearer " + token);
        MockHttpServletResponse response = new MockHttpServletResponse();
        AtomicReference<Authentication> authenticated = new AtomicReference<>();
        AtomicReference<UUID> tenantId = new AtomicReference<>();

        securityFilter.doFilter(request, response, (servletRequest, servletResponse) -> {
            authenticated.set(SecurityContextHolder.getContext().getAuthentication());
            tenantId.set(TenantContext.requireTenantId());
        });

        assertThat(response.getStatus()).isEqualTo(200);
        assertThat(authenticated.get()).isNotNull();
        assertThat(authenticated.get().getName()).isEqualTo(LOGIN_USERNAME);
        assertThat(authenticated.get().getAuthorities())
                .extracting("authority")
                .contains(expectedAuthority);
        assertThat(tenantId.get()).isEqualTo(expectedTenantId);
    }

    private void assertAccessTokenRejected(String token) throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/usuarios/perfil");
        request.setServletPath("/api/usuarios/perfil");
        request.addHeader("Authorization", "Bearer " + token);
        MockHttpServletResponse response = new MockHttpServletResponse();
        boolean[] invoked = {false};

        securityFilter.doFilter(request, response, (servletRequest, servletResponse) -> invoked[0] = true);

        assertThat(response.getStatus()).isEqualTo(401);
        assertThat(invoked[0]).isFalse();
    }

    private static void executeAsOwner(String sql) throws Exception {
        try (Connection connection = ownerConnection();
             Statement statement = connection.createStatement()) {
            statement.execute(sql);
        }
    }

    private static void assertApplicationRolesAreRestrictedAndDoNotOwnSchema() throws Exception {
        try (Connection connection = ownerConnection();
             Statement statement = connection.createStatement()) {
            try (ResultSet resultSet = statement.executeQuery("""
                    SELECT count(*)
                    FROM pg_catalog.pg_roles
                    WHERE (rolname = 'gestudio_app' AND (
                               rolcanlogin OR rolsuper OR rolcreatedb OR rolcreaterole
                               OR rolreplication OR rolbypassrls
                           ))
                       OR (rolname = 'gestudio_app_test' AND (
                               NOT rolcanlogin OR rolsuper OR rolcreatedb OR rolcreaterole
                               OR rolreplication OR rolbypassrls
                           ))
                    """)) {
                resultSet.next();
                assertThat(resultSet.getLong(1)).isZero();
            }

            try (ResultSet resultSet = statement.executeQuery("""
                    SELECT count(*)
                    FROM pg_catalog.pg_class c
                    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
                    JOIN pg_catalog.pg_roles r ON r.oid = c.relowner
                    WHERE n.nspname = 'public'
                      AND r.rolname IN ('gestudio_app', 'gestudio_app_test')
                    """)) {
                resultSet.next();
                assertThat(resultSet.getLong(1)).isZero();
            }

            try (ResultSet resultSet = statement.executeQuery("""
                    SELECT count(*)
                    FROM pg_catalog.pg_proc p
                    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
                    JOIN pg_catalog.pg_roles r ON r.oid = p.proowner
                    WHERE n.nspname = 'public'
                      AND p.proname = 'gestudio_multitenancy_health'
                      AND p.prosecdef
                      AND r.rolname = 'gestudio_health'
                      AND p.proconfig = ARRAY['search_path=pg_catalog']::text[]
                    """)) {
                resultSet.next();
                assertThat(resultSet.getLong(1)).isOne();
            }
        }
    }

    private static void assertConnectionReuseDoesNotLeakTenant() throws Exception {
        HikariConfig config = new HikariConfig();
        config.setJdbcUrl(POSTGRESQL.getJdbcUrl());
        config.setUsername(APP_USERNAME);
        config.setPassword(APP_PASSWORD);
        config.setMaximumPoolSize(1);
        config.setMinimumIdle(1);

        try (HikariDataSource pool = new HikariDataSource(config)) {
            DataSource dataSource = new TenantAwareDataSource(pool);
            long defaultPid;

            try (TenantContext.Scope ignored = TenantContext.open(DEFAULT_TENANT_ID, null);
                 Connection connection = dataSource.getConnection()) {
                defaultPid = scalar(connection, "SELECT pg_backend_pid()");
                assertThat(scalar(connection, "SELECT count(*) FROM refresh_sessions"))
                        .isPositive();
                assertThat(scalar(connection, """
                        SELECT count(*) FROM refresh_sessions
                        WHERE tenant_id <> '00000000-0000-0000-0000-000000000001'
                        """)).isZero();
                assertThat(scalar(connection, "SELECT count(*) FROM alumnos")).isOne();
                assertThat(scalar(connection, """
                        SELECT count(*) FROM alumnos
                        WHERE tenant_id <> '00000000-0000-0000-0000-000000000001'
                        """)).isZero();
            }

            try (Connection connection = dataSource.getConnection()) {
                assertThat(scalar(connection, "SELECT pg_backend_pid()"))
                        .isEqualTo(defaultPid);
                SQLException failure = catchThrowableOfType(
                        () -> scalar(connection, "SELECT count(*) FROM refresh_sessions"),
                        SQLException.class
                );
                org.assertj.core.api.Assertions.assertThatObject(failure).isNotNull();
                assertThat(failure.getSQLState()).isEqualTo("42501");
            }

            try (TenantContext.Scope ignored = TenantContext.open(OTHER_TENANT_ID, null);
                 Connection connection = dataSource.getConnection()) {
                assertThat(scalar(connection, "SELECT pg_backend_pid()"))
                        .isEqualTo(defaultPid);
                assertThat(scalar(connection, "SELECT count(*) FROM refresh_sessions"))
                        .isPositive();
                assertThat(scalar(connection, """
                        SELECT count(*) FROM refresh_sessions
                        WHERE tenant_id <> '00000000-0000-0000-0000-000000000002'
                        """)).isZero();
                assertThat(scalar(connection, "SELECT count(*) FROM alumnos")).isOne();
                assertThat(scalar(connection, """
                        SELECT count(*) FROM alumnos
                        WHERE tenant_id <> '00000000-0000-0000-0000-000000000002'
                        """)).isZero();
            }
        }
    }

    private static void insertMembership(Connection connection, UUID tenantId,
                                         long userId, long roleId) throws Exception {
        UUID membershipId = UUID.randomUUID();
        try (PreparedStatement statement = connection.prepareStatement("""
                INSERT INTO tenant_memberships(
                    id, tenant_id, usuario_id, status, security_version,
                    valid_from, created_at, updated_at
                ) VALUES (
                    ?, ?, ?, 'ACTIVE', 0,
                    CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
                )
                """)) {
            statement.setObject(1, membershipId);
            statement.setObject(2, tenantId);
            statement.setLong(3, userId);
            statement.executeUpdate();
        }
        try (PreparedStatement statement = connection.prepareStatement("""
                INSERT INTO tenant_membership_roles(membership_id, tenant_id, role_id)
                VALUES (?, ?, ?)
                """)) {
            statement.setObject(1, membershipId);
            statement.setObject(2, tenantId);
            statement.setLong(3, roleId);
            statement.executeUpdate();
        }
    }

    private static long scalar(Connection connection, String sql) throws SQLException {
        try (Statement statement = connection.createStatement();
             ResultSet resultSet = statement.executeQuery(sql)) {
            resultSet.next();
            return resultSet.getLong(1);
        }
    }

    private static void createApplicationRoles() {
        try (Connection connection = ownerConnection();
             Statement statement = connection.createStatement()) {

            statement.execute("""
                    CREATE ROLE gestudio_app
                    NOLOGIN
                    NOSUPERUSER
                    NOCREATEDB
                    NOCREATEROLE
                    NOINHERIT
                    NOREPLICATION
                    NOBYPASSRLS
                    """);

            statement.execute("""
                    CREATE ROLE gestudio_app_test
                    LOGIN
                    PASSWORD 'app-role-test-password'
                    NOSUPERUSER
                    NOCREATEDB
                    NOCREATEROLE
                    INHERIT
                    NOREPLICATION
                    NOBYPASSRLS
                    """);

            statement.execute("GRANT gestudio_app TO gestudio_app_test");
        } catch (Exception exception) {
            throw new ExceptionInInitializerError(exception);
        }
    }

    private static Flyway versionedFlyway() {
        FluentConfiguration configuration = Flyway.configure()
                .dataSource(POSTGRESQL.getJdbcUrl(), POSTGRESQL.getUsername(), POSTGRESQL.getPassword())
                .schemas("public")
                .defaultSchema("public");
        Flyway flyway = configuration.load();
        flyway.getConfigurationExtension(BaselineMigrationConfigurationExtension.class)
                .setBaselineMigrationPrefix(DISABLED_BASELINE_MIGRATION_PREFIX);
        return flyway;
    }

    private static Connection ownerConnection() throws Exception {
        return DriverManager.getConnection(
                POSTGRESQL.getJdbcUrl(),
                POSTGRESQL.getUsername(),
                POSTGRESQL.getPassword()
        );
    }

    private static long requireRoleId(
            Connection connection,
            String code
    ) throws Exception {
        try (PreparedStatement statement = connection.prepareStatement("""
                SELECT id
                FROM roles
                WHERE tenant_id = ?
                  AND upper(codigo) = upper(?)
                  AND activo = true
                """)) {
            statement.setObject(1, DEFAULT_TENANT_ID);
            statement.setString(2, code);

            try (ResultSet resultSet = statement.executeQuery()) {
                if (!resultSet.next()) {
                    throw new IllegalStateException(
                            "No se encontró el rol activo " + code
                    );
                }

                return resultSet.getLong(1);
            }
        }
    }

    private static long insertUser(
            Connection connection,
            long roleId,
            String encodedPassword
    ) throws Exception {
        try (PreparedStatement statement = connection.prepareStatement("""
                INSERT INTO usuarios(
                    nombre_usuario,
                    contrasena,
                    rol_id,
                    activo,
                    auth_version,
                    version
                )
                VALUES (?, ?, ?, true, 0, 0)
                RETURNING id
                """)) {
            statement.setString(1, LOGIN_USERNAME);
            statement.setString(2, encodedPassword);
            statement.setLong(3, roleId);

            try (ResultSet resultSet = statement.executeQuery()) {
                if (!resultSet.next()) {
                    throw new IllegalStateException(
                            "El INSERT de usuario no devolvió id"
                    );
                }

                return resultSet.getLong(1);
            }
        }
    }
}
