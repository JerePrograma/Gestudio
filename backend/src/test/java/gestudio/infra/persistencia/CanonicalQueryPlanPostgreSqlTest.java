package gestudio.infra.persistencia;

import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

class CanonicalQueryPlanPostgreSqlTest extends PostgreSqlIntegrationTest {

    @Test
    void listadoDeCargosPendientesUsaIndiceCompuestoEnDatasetDeterminista() throws Exception {
        String databaseName = "gestudio_plan_" + UUID.randomUUID().toString().replace("-", "");
        String jdbcUrl = POSTGRESQL.getJdbcUrl().replace(POSTGRESQL.getDatabaseName(), databaseName);
        try (Connection admin = POSTGRESQL.createConnection(""); Statement statement = admin.createStatement()) {
            admin.setAutoCommit(true);
            statement.execute("CREATE DATABASE " + databaseName);
        }
        try {
            Flyway.configure().dataSource(jdbcUrl, POSTGRESQL.getUsername(), POSTGRESQL.getPassword()).load().migrate();
            try (Connection connection = DriverManager.getConnection(jdbcUrl, POSTGRESQL.getUsername(), POSTGRESQL.getPassword());
                 Statement statement = connection.createStatement()) {
                statement.executeUpdate("""
                        INSERT INTO alumnos(nombre, apellido, fecha_incorporacion)
                        SELECT 'Alumno ' || n, 'Plan', DATE '2025-01-01'
                        FROM generate_series(1, 500) n
                        """);
                statement.executeUpdate("INSERT INTO sub_conceptos(descripcion) VALUES ('Plan')");
                statement.executeUpdate("INSERT INTO conceptos(descripcion, precio, sub_concepto_id) VALUES ('Plan', 100, 1)");
                statement.executeUpdate("""
                        INSERT INTO cargos(alumno_id, tipo, descripcion, importe_original, fecha_emision,
                                           fecha_vencimiento, estado, concepto_id, idempotency_key)
                        SELECT alumno_id, 'CONCEPTO', 'Cargo plan', 100, DATE '2025-01-01',
                               DATE '2025-01-01' + (cargo_n % 365),
                               CASE WHEN cargo_n % 5 = 0 THEN 'PAGADO' ELSE 'PENDIENTE' END,
                               1, 'plan-' || alumno_id || '-' || cargo_n
                        FROM generate_series(1, 500) alumno_id
                        CROSS JOIN generate_series(1, 40) cargo_n
                        """);
                statement.execute("VACUUM (ANALYZE) cargos");

                List<String> plan = new ArrayList<>();
                try (ResultSet result = statement.executeQuery("""
                        EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
                        SELECT id, fecha_vencimiento
                        FROM cargos
                        WHERE alumno_id = 250 AND estado IN ('PENDIENTE','PARCIAL')
                        ORDER BY fecha_vencimiento, id
                        """)) {
                    while (result.next()) plan.add(result.getString(1));
                }
                String text = String.join(System.lineSeparator(), plan);
                System.out.println("CARGO_PENDING_QUERY_PLAN" + System.lineSeparator() + text);
                assertThat(text).contains("Index Only Scan using ix_cargos_alumno_pendientes")
                        .doesNotContain("Seq Scan on cargos", "Sort  ");
                List<String> ordered = new ArrayList<>();
                try (ResultSet result = statement.executeQuery("""
                        SELECT id, fecha_vencimiento
                        FROM cargos
                        WHERE alumno_id = 250 AND estado IN ('PENDIENTE','PARCIAL')
                        ORDER BY fecha_vencimiento, id
                        """)) {
                    while (result.next()) ordered.add(result.getDate(2) + ":" + String.format("%020d", result.getLong(1)));
                }
                assertThat(ordered).hasSize(32).isSorted();
            }
        } finally {
            try (Connection admin = POSTGRESQL.createConnection(""); Statement statement = admin.createStatement()) {
                admin.setAutoCommit(true);
                statement.execute("DROP DATABASE " + databaseName + " WITH (FORCE)");
            }
        }
    }
}
