package gestudio.infra.persistencia;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class PostgreSqlTestDatabaseTest {
    @Test
    void externalPostgresRequiresExplicitDisposableAcknowledgementAndDedicatedPort() {
        assertThatThrownBy(() -> PostgreSqlTestDatabase.validateLocalPort("52915", null))
                .isInstanceOf(IllegalArgumentException.class);
        for (String port : new String[]{"5432", "0", "65536", "-1", "localhost:5433"}) {
            assertThatThrownBy(() -> PostgreSqlTestDatabase.validateLocalPort(port, "true"))
                    .isInstanceOf(IllegalArgumentException.class);
        }
        assertThat(PostgreSqlTestDatabase.validateLocalPort("52915", "true")).isEqualTo(52915);
    }
}
