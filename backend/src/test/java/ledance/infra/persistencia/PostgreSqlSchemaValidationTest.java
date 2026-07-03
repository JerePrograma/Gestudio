package ledance.infra.persistencia;

import ledance.Main;
import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.MigrationVersion;
import org.flywaydb.core.api.output.ValidateResult;
import org.junit.jupiter.api.Test;
import org.springframework.boot.builder.SpringApplicationBuilder;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;

class PostgreSqlSchemaValidationTest extends PostgreSqlIntegrationTest {

    private static final Set<String> EXPECTED_TABLES = Set.of(
            "alumnos", "aplicaciones_pago", "asistencias_alumno_mensual", "asistencias_diarias",
            "asistencias_mensuales", "bonificaciones", "cargos", "conceptos", "disciplina_horarios",
            "disciplinas", "egresos", "flyway_schema_history", "inscripciones", "matriculas",
            "mensualidades", "metodo_pagos", "movimientos_caja", "movimientos_credito",
            "movimientos_stock", "notificaciones", "observaciones_profesores", "pagos", "profesores",
            "recargos", "recibos", "recibos_pendientes", "roles", "salones", "stocks",
            "sub_conceptos", "usuarios", "ventas_stock", "refresh_sessions",
            "bootstrap_ejecuciones", "auditoria_eventos", "disciplina_tarifas",
            "inscripcion_condiciones_economicas", "cargo_liquidaciones", "cargo_eventos");

    @Test
    void aplicaFlywayDesdeVacioValidaHibernateYCumpleElContratoDelCatalogo() throws Exception {
        String databaseName = "ledance_schema_" + UUID.randomUUID().toString().replace("-", "");
        String jdbcUrl = POSTGRESQL.getJdbcUrl().replace(POSTGRESQL.getDatabaseName(), databaseName);
        crearBase(databaseName);
        try {
            Flyway flyway = Flyway.configure()
                    .dataSource(jdbcUrl, POSTGRESQL.getUsername(), POSTGRESQL.getPassword())
                    .defaultSchema("public")
                    .schemas("public")
                    .baselineOnMigrate(false)
                    .load();

            assertThat(flyway.migrate().migrationsExecuted).isEqualTo(4);
            ValidateResult validation = flyway.validateWithResult();
            assertThat(flyway.info().current()).isNotNull();
            assertThat(flyway.info().current().getVersion()).isEqualTo(MigrationVersion.fromVersion("4"));
            assertThat(validation.validationSuccessful)
                    .withFailMessage(validation.getAllErrorMessages())
                    .isTrue();

            try (Connection connection = DriverManager.getConnection(
                    jdbcUrl, POSTGRESQL.getUsername(), POSTGRESQL.getPassword())) {
                assertThat(tablas(connection)).isEqualTo(EXPECTED_TABLES);
                assertThat(contar(connection, """
                        SELECT count(*)
                        FROM information_schema.columns
                        WHERE table_schema = 'public'
                          AND (column_name ~ '(importe|monto|precio|saldo|credito|valor_cuota|matricula|clase_suelta|clase_prueba|recargo|porcentaje)')
                          AND data_type <> 'numeric'
                          AND column_name !~ '(_id|^id)$'
                          AND column_name NOT IN ('importe_revertido', 'origen_precio')
                        """)).as("toda columna monetaria o porcentual es NUMERIC").isZero();
                assertThat(contar(connection, """
                        SELECT count(*)
                        FROM information_schema.table_constraints tc
                        JOIN information_schema.key_column_usage kcu
                          ON tc.constraint_name = kcu.constraint_name AND tc.constraint_schema = kcu.constraint_schema
                        JOIN information_schema.columns c
                          ON c.table_schema = kcu.table_schema AND c.table_name = kcu.table_name AND c.column_name = kcu.column_name
                        WHERE tc.table_schema = 'public' AND tc.constraint_type = 'PRIMARY KEY'
                          AND tc.table_name NOT IN ('flyway_schema_history', 'refresh_sessions', 'bootstrap_ejecuciones')
                          AND c.data_type <> 'bigint'
                        """)).as("toda PK es BIGINT").isZero();
                assertThat(contar(connection, """
                        SELECT count(*)
                        FROM information_schema.columns
                        WHERE table_schema = 'public' AND column_name IN ('es_clon', 'descripcion_origen')
                        """)).isZero();
                assertThat(contar(connection, """
                        SELECT count(*)
                        FROM information_schema.columns
                        WHERE table_schema = 'public' AND table_name = 'recibos'
                          AND column_name IN ('estado', 'intentos', 'ultimo_error', 'version')
                        """)).as("el recibo historico no duplica estado tecnico de la outbox").isZero();
                assertThat(contar(connection, """
                        SELECT count(*)
                        FROM pg_constraint c
                        JOIN pg_class t ON t.oid = c.conrelid
                        JOIN pg_namespace n ON n.oid = t.relnamespace
                        WHERE n.nspname = 'public' AND c.contype = 'f'
                          AND c.confdeltype = 'c' AND t.relname <> 'disciplina_horarios'
                        """)).as("sólo la composición de horarios permite cascade").isZero();
                assertThat(contar(connection, """
                        SELECT count(*)
                        FROM pg_constraint c
                        JOIN pg_class t ON t.oid = c.conrelid
                        JOIN pg_namespace n ON n.oid = t.relnamespace
                        WHERE n.nspname = 'public' AND c.contype = 'f'
                          AND NOT EXISTS (
                            SELECT 1 FROM pg_index i
                            WHERE i.indrelid = c.conrelid
                              AND (i.indkey::smallint[])[0:cardinality(c.conkey)-1] @> c.conkey
                          )
                        """)).as("cada FK tiene índice de prefijo").isZero();
            }

            assertThatCode(() -> new SpringApplicationBuilder(Main.class).run(
                    "--spring.profiles.active=test",
                    "--spring.main.web-application-type=none",
                    "--spring.datasource.url=" + jdbcUrl,
                    "--spring.datasource.username=" + POSTGRESQL.getUsername(),
                    "--spring.datasource.password=" + POSTGRESQL.getPassword(),
                    "--spring.flyway.enabled=false",
                    "--spring.jpa.hibernate.ddl-auto=validate").close())
                    .doesNotThrowAnyException();
        } finally {
            eliminarBase(databaseName);
        }
    }

    private void crearBase(String databaseName) throws Exception {
        try (Connection admin = POSTGRESQL.createConnection(""); Statement statement = admin.createStatement()) {
            admin.setAutoCommit(true);
            statement.execute("CREATE DATABASE " + databaseName);
        }
    }

    private void eliminarBase(String databaseName) throws Exception {
        try (Connection admin = POSTGRESQL.createConnection(""); Statement statement = admin.createStatement()) {
            admin.setAutoCommit(true);
            statement.execute("DROP DATABASE " + databaseName + " WITH (FORCE)");
        }
    }

    private Set<String> tablas(Connection connection) throws Exception {
        Set<String> tables = new java.util.TreeSet<>();
        try (Statement statement = connection.createStatement(); ResultSet result = statement.executeQuery("""
                SELECT table_name FROM information_schema.tables
                WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
                ORDER BY table_name
                """)) {
            while (result.next()) {
                tables.add(result.getString(1));
            }
        }
        return tables;
    }

    private long contar(Connection connection, String sql) throws Exception {
        try (Statement statement = connection.createStatement(); ResultSet result = statement.executeQuery(sql)) {
            result.next();
            return result.getLong(1);
        }
    }
}
