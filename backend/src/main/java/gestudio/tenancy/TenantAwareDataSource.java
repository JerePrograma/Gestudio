package gestudio.tenancy;

import org.springframework.jdbc.datasource.AbstractDataSource;

import javax.sql.DataSource;
import java.io.PrintWriter;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Proxy;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.SQLException;
import java.util.Optional;
import java.util.UUID;
import java.util.logging.Logger;

public final class TenantAwareDataSource extends AbstractDataSource implements AutoCloseable {
    private static final String SET_TENANT = "SELECT set_config('app.current_tenant_id', ?, false)";

    private final DataSource delegate;

    public TenantAwareDataSource(DataSource delegate) {
        this.delegate = delegate;
    }

    @Override
    public void close() throws Exception {
        if (delegate instanceof AutoCloseable closeable) {
            closeable.close();
        }
    }

    @Override
    public Connection getConnection() throws SQLException {
        return prepare(delegate.getConnection());
    }

    @Override
    public Connection getConnection(String username, String password) throws SQLException {
        return prepare(delegate.getConnection(username, password));
    }

    private Connection prepare(Connection connection) throws SQLException {
        try {
            setTenant(connection, TenantContext.currentTenantId());
            return guarded(connection);
        } catch (SQLException failure) {
            connection.close();
            throw failure;
        }
    }

    private static void setTenant(Connection connection, Optional<UUID> tenantId) throws SQLException {
        try (PreparedStatement statement = connection.prepareStatement(SET_TENANT)) {
            statement.setString(1, tenantId.map(UUID::toString).orElse(""));
            statement.execute();
        }
    }

    private static Connection guarded(Connection connection) {
        return (Connection) Proxy.newProxyInstance(
                Connection.class.getClassLoader(),
                new Class<?>[]{Connection.class},
                new java.lang.reflect.InvocationHandler() {
                    private boolean closed;

                    @Override
                    public Object invoke(Object proxy, java.lang.reflect.Method method, Object[] args) throws Throwable {
                        if (method.getName().equals("close") && method.getParameterCount() == 0) {
                            if (!closed) {
                                closed = true;
                                try {
                                    setTenant(connection, Optional.empty());
                                } catch (SQLException resetFailure) {
                                    try {
                                        connection.abort(Runnable::run);
                                    } catch (SQLException abortFailure) {
                                        resetFailure.addSuppressed(abortFailure);
                                    }
                                    throw resetFailure;
                                } finally {
                                    connection.close();
                                }
                            }
                            return null;
                        }
                        if (method.getName().equals("isClosed") && closed) {
                            return true;
                        }
                        try {
                            return method.invoke(connection, args);
                        } catch (InvocationTargetException failure) {
                            throw failure.getCause();
                        }
                    }
                });
    }

    @Override
    public PrintWriter getLogWriter() {
        try {
            return delegate.getLogWriter();
        } catch (SQLException exception) {
            throw new IllegalStateException("No se pudo leer el log writer del datasource", exception);
        }
    }

    @Override
    public void setLogWriter(PrintWriter out) throws SQLException {
        delegate.setLogWriter(out);
    }

    @Override
    public void setLoginTimeout(int seconds) throws SQLException {
        delegate.setLoginTimeout(seconds);
    }

    @Override
    public int getLoginTimeout() throws SQLException {
        return delegate.getLoginTimeout();
    }

    @Override
    public Logger getParentLogger() {
        try {
            return delegate.getParentLogger();
        } catch (java.sql.SQLFeatureNotSupportedException exception) {
            return Logger.getLogger(TenantAwareDataSource.class.getName());
        }
    }

    @Override
    public <T> T unwrap(Class<T> iface) throws SQLException {
        return iface.isInstance(this) ? iface.cast(this) : delegate.unwrap(iface);
    }

    @Override
    public boolean isWrapperFor(Class<?> iface) throws SQLException {
        return iface.isInstance(this) || delegate.isWrapperFor(iface);
    }
}
