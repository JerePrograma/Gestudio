package gestudio.infra.persistencia;

import org.testcontainers.postgresql.PostgreSQLContainer;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.UUID;

/**
 * Uses Testcontainers by default. An explicitly disposable loopback PostgreSQL
 * cluster can be selected on hosts without Docker; every fixture creates a new
 * database and never opens an existing application database.
 */
public final class PostgreSqlTestDatabase {
    public static final int POSTGRESQL_PORT = PostgreSQLContainer.POSTGRESQL_PORT;
    private final String image;
    private PostgreSQLContainer container;
    private String databaseName;
    private String username;
    private String password;
    private int localPort;

    public PostgreSqlTestDatabase(String image) {
        this.image = image;
    }

    public PostgreSqlTestDatabase withDatabaseName(String value) {
        databaseName = value;
        return this;
    }

    public PostgreSqlTestDatabase withUsername(String value) {
        username = value;
        return this;
    }

    public PostgreSqlTestDatabase withPassword(String value) {
        password = value;
        return this;
    }

    public void start() {
        String configuredPort = System.getenv("GESTUDIO_TEST_POSTGRES_PORT");
        if (configuredPort == null || configuredPort.isBlank()) {
            container = new PostgreSQLContainer(image).withDatabaseName(databaseName)
                    .withUsername(username).withPassword(password);
            container.start();
            return;
        }

        localPort = validateLocalPort(configuredPort,
                System.getenv("GESTUDIO_TEST_POSTGRES_DISPOSABLE"));
        username = System.getenv("GESTUDIO_TEST_POSTGRES_USER");
        if (username == null || username.isBlank()) {
            throw new IllegalArgumentException("GESTUDIO_TEST_POSTGRES_USER is required");
        }
        password = System.getenv().getOrDefault("GESTUDIO_TEST_POSTGRES_PASSWORD", "");
        databaseName = "gestudio_test_" + databaseName.replaceFirst("^gestudio_", "")
                + "_" + UUID.randomUUID().toString().replace("-", "").substring(0, 12);
        if (!databaseName.matches("[a-z0-9_]{1,63}")) {
            throw new IllegalArgumentException("Invalid isolated test database name");
        }
        try (Connection admin = DriverManager.getConnection(
                localJdbcUrl("postgres"), username, password);
             Statement statement = admin.createStatement()) {
            statement.execute("CREATE DATABASE " + databaseName);
        } catch (SQLException failure) {
            throw new IllegalStateException("Could not create isolated PostgreSQL test database", failure);
        }
    }

    static int validateLocalPort(String configuredPort, String disposableAcknowledgement) {
        if (!"true".equals(disposableAcknowledgement)) {
            throw new IllegalArgumentException(
                    "Local PostgreSQL tests require GESTUDIO_TEST_POSTGRES_DISPOSABLE=true");
        }
        int port = Integer.parseInt(configuredPort);
        if (port < 1 || port > 65535 || port == POSTGRESQL_PORT) {
            throw new IllegalArgumentException("Local PostgreSQL tests require a dedicated non-default port");
        }
        return port;
    }

    public String getJdbcUrl() {
        return container == null ? localJdbcUrl(databaseName) : container.getJdbcUrl();
    }

    private String localJdbcUrl(String database) {
        return "jdbc:postgresql://127.0.0.1:" + localPort + "/" + database;
    }

    public String getDatabaseName() {
        return container == null ? databaseName : container.getDatabaseName();
    }

    public String getUsername() {
        return container == null ? username : container.getUsername();
    }

    public String getPassword() {
        return container == null ? password : container.getPassword();
    }

    public Integer getMappedPort(int originalPort) {
        if (originalPort != POSTGRESQL_PORT) {
            throw new IllegalArgumentException("Only the PostgreSQL port is supported");
        }
        return container == null ? localPort : container.getMappedPort(originalPort);
    }

    public Connection createConnection(String query) throws SQLException {
        return container == null
                ? DriverManager.getConnection(getJdbcUrl() + query, getUsername(), getPassword())
                : container.createConnection(query);
    }
}
