package gestudio.tenancy;

import org.junit.jupiter.api.Test;

import javax.sql.DataSource;
import java.lang.reflect.Proxy;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;

import static org.assertj.core.api.Assertions.assertThat;

class TenantAwareDataSourceTest {

    @Test
    void estableceTenantYLoLimpiaAntesDeDevolverLaConexion() throws Exception {
        List<String> values = new ArrayList<>();
        Connection physical = connection(values);
        DataSource delegate = (DataSource) Proxy.newProxyInstance(
                DataSource.class.getClassLoader(), new Class<?>[]{DataSource.class},
                (proxy, method, args) -> method.getName().equals("getConnection") ? physical : null);
        TenantAwareDataSource dataSource = new TenantAwareDataSource(delegate);
        UUID tenantId = UUID.randomUUID();

        try (TenantContext.Scope ignored = TenantContext.open(tenantId, UUID.randomUUID());
             Connection connection = dataSource.getConnection()) {
            assertThat(connection.isClosed()).isFalse();
        }

        assertThat(values).containsExactly(tenantId.toString(), "");
    }

    @Test
    void ausenciaDeContextoSiempreBorraUnValorResidual() throws Exception {
        List<String> values = new ArrayList<>();
        TenantAwareDataSource dataSource = new TenantAwareDataSource(dataSource(connection(values)));

        try (Connection ignored = dataSource.getConnection()) {
            // Adquirir sin contexto es una operación válida para el control plane.
        }

        assertThat(values).containsExactly("", "");
    }

    @Test
    void cierreDelWrapperCierraElDataSourceDelegado() throws Exception {
        AtomicBoolean closed = new AtomicBoolean();
        DataSource delegate = (DataSource) Proxy.newProxyInstance(
                DataSource.class.getClassLoader(),
                new Class<?>[]{DataSource.class, AutoCloseable.class},
                (proxy, method, args) -> {
                    if (method.getName().equals("close")) {
                        closed.set(true);
                        return null;
                    }
                    return primitiveDefault(method.getReturnType());
                });
        TenantAwareDataSource dataSource = new TenantAwareDataSource(delegate);

        dataSource.close();

        assertThat(closed).isTrue();
    }

    private static DataSource dataSource(Connection connection) {
        return (DataSource) Proxy.newProxyInstance(
                DataSource.class.getClassLoader(), new Class<?>[]{DataSource.class},
                (proxy, method, args) -> method.getName().equals("getConnection") ? connection : null);
    }

    private static Connection connection(List<String> values) {
        final boolean[] closed = {false};
        return (Connection) Proxy.newProxyInstance(
                Connection.class.getClassLoader(), new Class<?>[]{Connection.class},
                (proxy, method, args) -> switch (method.getName()) {
                    case "prepareStatement" -> statement(values);
                    case "close", "abort" -> { closed[0] = true; yield null; }
                    case "isClosed" -> closed[0];
                    default -> primitiveDefault(method.getReturnType());
                });
    }

    private static PreparedStatement statement(List<String> values) {
        final String[] value = {null};
        return (PreparedStatement) Proxy.newProxyInstance(
                PreparedStatement.class.getClassLoader(), new Class<?>[]{PreparedStatement.class},
                (proxy, method, args) -> switch (method.getName()) {
                    case "setString" -> { value[0] = (String) args[1]; yield null; }
                    case "execute" -> { values.add(value[0]); yield true; }
                    case "close" -> null;
                    default -> primitiveDefault(method.getReturnType());
                });
    }

    private static Object primitiveDefault(Class<?> type) {
        if (!type.isPrimitive()) return null;
        if (type == boolean.class) return false;
        if (type == char.class) return '\0';
        return 0;
    }
}
