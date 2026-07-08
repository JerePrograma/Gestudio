package gestudio.cuotas;

import gestudio.infra.persistencia.PostgreSqlIntegrationTest;
import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.MigrationVersion;
import org.junit.jupiter.api.Test;

import java.sql.*;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class CargoLiquidacionMigrationPostgreSqlTest extends PostgreSqlIntegrationTest {
    @Test
    void actualizaV3AV4SinInventarDescuentosYLaVistaUsaPagoMasCredito() throws Exception {
        String database = "gestudio_v4_" + UUID.randomUUID().toString().replace("-", "");
        String url = POSTGRESQL.getJdbcUrl().replace(POSTGRESQL.getDatabaseName(), database);
        createDatabase(database);
        try {
            flyway(url, "3").migrate();
            long cargoId;
            try (Connection connection = DriverManager.getConnection(url, POSTGRESQL.getUsername(), POSTGRESQL.getPassword())) {
                cargoId = fixtureV3(connection);
            }

            flyway(url, "4").migrate();
            try (Connection connection = DriverManager.getConnection(url, POSTGRESQL.getUsername(), POSTGRESQL.getPassword())) {
                assertThat(text(connection, "SELECT origen_precio FROM cargo_liquidaciones WHERE cargo_id = " + cargoId))
                        .isEqualTo("MIGRADO_CARGO_EXISTENTE");
                assertThat(text(connection, "SELECT importe_base || ':' || importe_final || ':' || formula_version FROM cargo_liquidaciones WHERE cargo_id = " + cargoId))
                        .isEqualTo("100.00:100.00:0");
                assertThat(text(connection, "SELECT periodo_desde::text FROM cargo_liquidaciones WHERE cargo_id = " + cargoId))
                        .isEqualTo("2026-01-01");
                assertThat(text(connection, "SELECT saldo_nuevo::text FROM cargo_eventos WHERE cargo_id = " + cargoId))
                        .isEqualTo("50.00");
                assertThat(text(connection, """
                        SELECT aplicado_pagos || ':' || aplicado_credito || ':' || saldo_cuota || ':' || saldo_total_periodo
                        FROM v_cuotas_seguimiento WHERE cargo_id = %d
                        """.formatted(cargoId))).isEqualTo("30.00:20.00:50.00:50.00");
                assertThatThrownBy(() -> execute(connection,
                        "UPDATE cargo_eventos SET tipo = 'ANULADO' WHERE cargo_id = " + cargoId))
                        .hasMessageContaining("append-only");
            }
        } finally {
            dropDatabase(database);
        }
    }

    private long fixtureV3(Connection connection) throws SQLException {
        try (Statement s = connection.createStatement()) {
            long role = id(s, "SELECT id FROM roles WHERE descripcion = 'ADMINISTRADOR'");
            long user = id(s, "INSERT INTO usuarios(nombre_usuario, contrasena, rol_id) VALUES ('v4-user', 'hash', " + role + ") RETURNING id");
            long professor = id(s, "INSERT INTO profesores(nombre, apellido) VALUES ('Profe', 'V4') RETURNING id");
            long discipline = id(s, "INSERT INTO disciplinas(nombre, profesor_id, valor_cuota) VALUES ('V4', " + professor + ", 999) RETURNING id");
            long student = id(s, "INSERT INTO alumnos(nombre, apellido, fecha_incorporacion) VALUES ('Alumno', 'V4', DATE '2025-01-01') RETURNING id");
            long enrollment = id(s, "INSERT INTO inscripciones(alumno_id, disciplina_id, fecha_inscripcion) VALUES (" + student + ", " + discipline + ", DATE '2025-01-01') RETURNING id");
            long monthly = id(s, "INSERT INTO mensualidades(inscripcion_id, anio, mes, fecha_generacion, fecha_vencimiento, descripcion) VALUES (" + enrollment + ", 2026, 1, DATE '2026-07-03', DATE '2026-01-10', 'Enero') RETURNING id");
            long cargo = id(s, "INSERT INTO cargos(alumno_id, tipo, descripcion, importe_original, fecha_emision, fecha_vencimiento, mensualidad_id) VALUES (" + student + ", 'MENSUALIDAD', 'Enero', 100, DATE '2026-07-03', DATE '2026-01-10', " + monthly + ") RETURNING id");
            long method = id(s, "INSERT INTO metodo_pagos(descripcion) VALUES ('Efectivo V4') RETURNING id");
            long payment = id(s, "INSERT INTO pagos(alumno_id, metodo_pago_id, usuario_id, fecha, monto_recibido, idempotency_key, request_hash) VALUES (" + student + ", " + method + ", " + user + ", DATE '2026-07-03', 30, 'v4-payment', repeat('a', 64)) RETURNING id");
            s.executeUpdate("INSERT INTO aplicaciones_pago(pago_id, cargo_id, usuario_id, importe_aplicado, fecha) VALUES (" + payment + ", " + cargo + ", " + user + ", 30, DATE '2026-07-03')");
            s.executeUpdate("INSERT INTO movimientos_credito(alumno_id, tipo, importe, cargo_id, usuario_id, idempotency_key, request_hash) VALUES (" + student + ", 'CONSUMO', 20, " + cargo + ", " + user + ", 'v4-credit', repeat('b', 64))");
            return cargo;
        }
    }

    private Flyway flyway(String url, String target) {
        return Flyway.configure().dataSource(url, POSTGRESQL.getUsername(), POSTGRESQL.getPassword())
                .schemas("public").defaultSchema("public").target(MigrationVersion.fromVersion(target)).load();
    }

    private long id(Statement statement, String sql) throws SQLException {
        try (ResultSet result = statement.executeQuery(sql)) { result.next(); return result.getLong(1); }
    }

    private String text(Connection connection, String sql) throws SQLException {
        try (Statement statement = connection.createStatement(); ResultSet result = statement.executeQuery(sql)) {
            result.next(); return result.getString(1);
        }
    }

    private void execute(Connection connection, String sql) throws SQLException {
        try (Statement statement = connection.createStatement()) { statement.executeUpdate(sql); }
    }

    private void createDatabase(String name) throws SQLException {
        try (Connection connection = POSTGRESQL.createConnection(""); Statement statement = connection.createStatement()) {
            connection.setAutoCommit(true); statement.execute("CREATE DATABASE " + name);
        }
    }

    private void dropDatabase(String name) throws SQLException {
        try (Connection connection = POSTGRESQL.createConnection(""); Statement statement = connection.createStatement()) {
            connection.setAutoCommit(true); statement.execute("DROP DATABASE " + name + " WITH (FORCE)");
        }
    }
}
