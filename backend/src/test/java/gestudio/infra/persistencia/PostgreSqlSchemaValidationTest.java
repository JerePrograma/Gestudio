package gestudio.infra.persistencia;

import gestudio.Main;
import gestudio.infra.seguridad.PermissionCodes;
import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.MigrationInfo;
import org.flywaydb.core.api.MigrationVersion;
import org.flywaydb.core.api.output.ValidateResult;
import org.junit.jupiter.api.Test;
import org.springframework.boot.builder.SpringApplicationBuilder;

import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;
import java.util.UUID;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class PostgreSqlSchemaValidationTest extends PostgreSqlIntegrationTest {

    private static final Set<String> BASE_ROLES = Set.of(
            "SUPERADMIN", "DIRECCION", "ADMINISTRADOR", "SECRETARIA", "CAJA", "PROFESOR");
    private static final Set<String> DIRECCION = PermissionCodes.ALL.stream()
            .filter(codigo -> !PermissionCodes.PERM_ROLES_ADMIN.equals(codigo))
            .collect(Collectors.toUnmodifiableSet());
    private static final Set<String> SECRETARIA = Set.of(
            PermissionCodes.PERM_APP_ACCESO,
            PermissionCodes.PERM_PAGOS_REGISTRAR,
            PermissionCodes.PERM_CREDITOS_CONSUMIR,
            PermissionCodes.PERM_CONDICIONES_ECONOMICAS_ADMIN,
            PermissionCodes.PERM_ALUMNOS_LEER,
            PermissionCodes.PERM_ALUMNOS_ADMIN,
            PermissionCodes.PERM_INSCRIPCIONES_LEER,
            PermissionCodes.PERM_INSCRIPCIONES_ADMIN,
            PermissionCodes.PERM_DISCIPLINAS_LEER,
            PermissionCodes.PERM_PROFESORES_LEER,
            PermissionCodes.PERM_ASISTENCIAS_LEER,
            PermissionCodes.PERM_ASISTENCIAS_REGISTRAR,
            PermissionCodes.PERM_PAGOS_LEER,
            PermissionCodes.PERM_CAJA_LEER,
            PermissionCodes.PERM_STOCK_LEER,
            PermissionCodes.PERM_REPORTES_LEER,
            PermissionCodes.PERM_CONFIG_LEER
    );
    private static final Set<String> CAJA = Set.of(
            PermissionCodes.PERM_APP_ACCESO,
            PermissionCodes.PERM_ALUMNOS_LEER,
            PermissionCodes.PERM_PAGOS_LEER,
            PermissionCodes.PERM_PAGOS_REGISTRAR,
            PermissionCodes.PERM_CAJA_LEER,
            PermissionCodes.PERM_STOCK_LEER,
            PermissionCodes.PERM_CONFIG_LEER,
            PermissionCodes.PERM_CREDITOS_CONSUMIR
    );

    private static final Set<String> EXPECTED_TABLES = Set.of(
            "alumnos", "aplicaciones_pago", "asistencias_alumno_mensual", "asistencias_diarias",
            "asistencias_mensuales", "bonificaciones", "cargos", "conceptos", "disciplina_horarios",
            "disciplinas", "egresos", "flyway_schema_history", "inscripciones", "matriculas",
            "mensualidades", "metodo_pagos", "movimientos_caja", "movimientos_credito",
            "movimientos_stock", "notificaciones", "observaciones_profesores", "pagos", "profesores",
            "recargos", "recibos", "recibos_pendientes", "roles", "salones", "stocks",
            "sub_conceptos", "usuarios", "ventas_stock", "refresh_sessions",
            "bootstrap_ejecuciones", "auditoria_eventos", "disciplina_tarifas",
            "inscripcion_condiciones_economicas", "cargo_liquidaciones", "cargo_eventos",
            "permisos", "usuario_roles", "rol_permisos",
            "jere_platform_student_export_snapshots", "jere_platform_student_export_pages",
            "tenants", "tenant_memberships", "tenant_membership_roles",
            "platform_admins", "jere_platform_tenant_mappings",
            "platform_refresh_sessions", "platform_mfa_credentials",
            "platform_recovery_codes", "platform_identity_activations",
            "platform_step_up_challenges", "platform_idempotency_keys",
            "platform_audit_events"
    );

    @Test
    void aplicaFlywayDesdeVacioValidaHibernateYCumpleElContratoDelCatalogo() throws Exception {
        String databaseName = "gestudio_schema_" + UUID.randomUUID().toString().replace("-", "");
        String jdbcUrl = POSTGRESQL.getJdbcUrl().replace(POSTGRESQL.getDatabaseName(), databaseName);

        crearBase(databaseName);

        try {
            Flyway flyway = Flyway.configure()
                    .dataSource(jdbcUrl, POSTGRESQL.getUsername(), POSTGRESQL.getPassword())
                    .defaultSchema("public")
                    .schemas("public")
                    .baselineOnMigrate(false)
                    .load();

            MigrationInfo[] pendingMigrations = flyway.info().pending();
            assertThat(pendingMigrations).isNotEmpty();
            MigrationVersion expectedLatestVersion = pendingMigrations[pendingMigrations.length - 1].getVersion();

            assertThat(flyway.migrate().migrationsExecuted).isEqualTo(pendingMigrations.length);

            ValidateResult validation = flyway.validateWithResult();

            assertThat(flyway.info().current()).isNotNull();
            assertThat(flyway.info().current().getVersion()).isEqualTo(expectedLatestVersion);
            assertThat(validation.validationSuccessful)
                    .withFailMessage(validation.getAllErrorMessages())
                    .isTrue();

            try (Connection connection = DriverManager.getConnection(
                    jdbcUrl,
                    POSTGRESQL.getUsername(),
                    POSTGRESQL.getPassword()
            )) {
                assertThat(tablas(connection)).isEqualTo(EXPECTED_TABLES);

                assertThat(codigos(connection, "SELECT codigo FROM permisos"))
                        .isEqualTo(PermissionCodes.ALL);
                assertThat(contar(connection, "SELECT count(*) FROM permisos WHERE activo AND sistema"))
                        .isEqualTo(32);
                assertThat(codigos(connection, """
                        SELECT version || ':' || type || ':' || script
                        FROM flyway_schema_history
                        WHERE success
                        ORDER BY installed_rank
                        """))
                        .containsExactly("12:SQL_BASELINE:B12__gestudio_production_baseline.sql");
                assertThat(tablasConDatosFuncionales(connection)).isEmpty();
                assertThat(codigos(connection, "SELECT public.gestudio_multitenancy_health()"))
                        .containsExactly("GREEN");

                assertThat(contar(connection, """
                        SELECT count(*)
                        FROM information_schema.columns
                        WHERE table_schema = 'public'
                          AND (column_name ~ '(importe|monto|precio|saldo|credito|valor_cuota|matricula|clase_suelta|clase_prueba|recargo|porcentaje)')
                          AND data_type <> 'numeric'
                          AND column_name !~ '(_id|^id)$'
                          AND column_name NOT IN ('importe_revertido', 'origen_precio')
                        """))
                        .as("toda columna monetaria o porcentual es NUMERIC")
                        .isZero();

                assertThat(contar(connection, """
                        SELECT count(*)
                        FROM information_schema.table_constraints tc
                        JOIN information_schema.key_column_usage kcu
                          ON tc.constraint_name = kcu.constraint_name
                         AND tc.constraint_schema = kcu.constraint_schema
                        JOIN information_schema.columns c
                          ON c.table_schema = kcu.table_schema
                         AND c.table_name = kcu.table_name
                         AND c.column_name = kcu.column_name
                        WHERE tc.table_schema = 'public'
                          AND tc.constraint_type = 'PRIMARY KEY'
                          AND tc.table_name NOT IN (
                              'flyway_schema_history',
                              'refresh_sessions',
                              'bootstrap_ejecuciones',
                              'jere_platform_student_export_snapshots',
                              'jere_platform_student_export_pages',
                              'tenants',
                              'tenant_memberships',
                              'tenant_membership_roles',
                              'jere_platform_tenant_mappings',
                              'platform_refresh_sessions',
                              'platform_mfa_credentials',
                              'platform_recovery_codes',
                              'platform_identity_activations',
                              'platform_step_up_challenges'
                          )
                          AND c.data_type <> 'bigint'
                        """))
                        .as("toda PK es BIGINT")
                        .isZero();

                assertThat(contar(connection, """
                        SELECT count(*)
                        FROM information_schema.columns
                        WHERE table_schema = 'public'
                          AND column_name IN ('es_clon', 'descripcion_origen')
                        """))
                        .isZero();

                assertThat(contar(connection, """
                        SELECT count(*)
                        FROM information_schema.columns
                        WHERE table_schema = 'public'
                          AND table_name = 'recibos'
                          AND column_name IN ('estado', 'intentos', 'ultimo_error', 'version')
                        """))
                        .as("el recibo historico no duplica estado tecnico de la outbox")
                        .isZero();

                assertThat(contar(connection, """
                        SELECT count(*)
                        FROM pg_constraint c
                        JOIN pg_class t ON t.oid = c.conrelid
                        JOIN pg_namespace n ON n.oid = t.relnamespace
                        WHERE n.nspname = 'public'
                          AND c.contype = 'f'
                          AND c.confdeltype = 'c'
                          AND (t.relname, c.conname) NOT IN (
                              ('disciplina_horarios', 'fk_horarios_disciplina'),
                              ('disciplina_horarios', 'fk_horarios_tenant_disciplina'),
                              ('rol_permisos', 'fk_rol_permisos_rol'),
                              ('rol_permisos', 'fk_rol_permisos_tenant_role'),
                              ('tenant_membership_roles', 'fk_tenant_membership_roles_membership'),
                              ('usuario_roles', 'fk_usuario_roles_usuario')
                          )
                        """))
                        .as("sólo composiciones estrictas y tablas join RBAC permiten cascade")
                        .isZero();

                assertThat(contar(connection, """
                        SELECT count(*)
                        FROM pg_constraint c
                        JOIN pg_class t ON t.oid = c.conrelid
                        JOIN pg_namespace n ON n.oid = t.relnamespace
                        WHERE n.nspname = 'public'
                          AND c.contype = 'f'
                          AND NOT EXISTS (
                            SELECT 1
                            FROM pg_index i
                            WHERE i.indrelid = c.conrelid
                              AND i.indisvalid
                              AND i.indisready
                              AND i.indpred IS NULL
                              AND i.indnkeyatts >= cardinality(c.conkey)
                              AND NOT EXISTS (
                                SELECT 1
                                FROM unnest(c.conkey)
                                     WITH ORDINALITY fk_column(attnum, ordinal_position)
                                LEFT JOIN unnest(i.indkey::smallint[])
                                     WITH ORDINALITY index_column(attnum, ordinal_position)
                                  ON index_column.ordinal_position = fk_column.ordinal_position
                                WHERE index_column.attnum IS DISTINCT FROM fk_column.attnum
                              )
                          )
                        """))
                        .as("cada FK tiene índice de prefijo")
                        .isZero();
            }

            assertThatCode(() -> new SpringApplicationBuilder(Main.class).run(
                    "--spring.profiles.active=test",
                    "--spring.main.web-application-type=none",
                    "--spring.datasource.url=" + jdbcUrl,
                    "--spring.datasource.username=" + POSTGRESQL.getUsername(),
                    "--spring.datasource.password=" + POSTGRESQL.getPassword(),
                    "--app.platform-datasource.url=" + jdbcUrl,
                    "--app.platform-datasource.username=" + POSTGRESQL.getUsername(),
                    "--app.platform-datasource.password=" + POSTGRESQL.getPassword(),
                    "--spring.flyway.enabled=false",
                    "--spring.jpa.hibernate.ddl-auto=validate"
            ).close())
                    .doesNotThrowAnyException();

        } finally {
            eliminarBase(databaseName);
        }
    }

    @Test
    void baselineB12YUpgradeV1AV12SonEstructuralmenteEquivalentes() throws Exception {
        String suffix = UUID.randomUUID().toString().replace("-", "");
        String historicalDatabase = "gestudio_v12_historical_" + suffix;
        String baselineDatabase = "gestudio_b12_equivalent_" + suffix;
        String historicalUrl = POSTGRESQL.getJdbcUrl()
                .replace(POSTGRESQL.getDatabaseName(), historicalDatabase);
        String baselineUrl = POSTGRESQL.getJdbcUrl()
                .replace(POSTGRESQL.getDatabaseName(), baselineDatabase);

        crearBase(historicalDatabase);
        crearBase(baselineDatabase);

        try {
            Flyway historicalV11 = Flyway.configure()
                    .dataSource(historicalUrl, POSTGRESQL.getUsername(), POSTGRESQL.getPassword())
                    .configuration(Map.of("flyway.baselineMigrationPrefix", "X_DISABLED_BASELINE"))
                    .target("11")
                    .baselineOnMigrate(false)
                    .load();
            assertThat(historicalV11.migrate().migrationsExecuted).isEqualTo(11);

            Flyway historicalV12 = Flyway.configure()
                    .dataSource(historicalUrl, POSTGRESQL.getUsername(), POSTGRESQL.getPassword())
                    .configuration(Map.of("flyway.baselineMigrationPrefix", "X_DISABLED_BASELINE"))
                    .baselineOnMigrate(false)
                    .load();
            assertThat(historicalV12.migrate().migrationsExecuted).isOne();
            assertThat(historicalV12.validateWithResult().validationSuccessful).isTrue();

            Flyway baselineV12 = Flyway.configure()
                    .dataSource(baselineUrl, POSTGRESQL.getUsername(), POSTGRESQL.getPassword())
                    .baselineOnMigrate(false)
                    .load();
            assertThat(baselineV12.migrate().migrationsExecuted).isOne();
            assertThat(baselineV12.validateWithResult().validationSuccessful).isTrue();

            try (Connection historical = DriverManager.getConnection(
                    historicalUrl, POSTGRESQL.getUsername(), POSTGRESQL.getPassword());
                 Connection baseline = DriverManager.getConnection(
                         baselineUrl, POSTGRESQL.getUsername(), POSTGRESQL.getPassword())) {
                assertThat(filas(historical, """
                        SELECT version || ':' || type || ':' || script
                        FROM flyway_schema_history
                        WHERE success
                        ORDER BY installed_rank
                        """))
                        .hasSize(12)
                        .allMatch(row -> row.matches("[1-9][0-9]*:SQL:V[1-9][0-9]*__.+\\.sql"))
                        .last()
                        .isEqualTo("12:SQL:V12__platform_identity_and_seedless_health.sql");
                assertThat(filas(baseline, """
                        SELECT version || ':' || type || ':' || script
                        FROM flyway_schema_history
                        WHERE success
                        ORDER BY installed_rank
                        """))
                        .containsExactly("12:SQL_BASELINE:B12__gestudio_production_baseline.sql");

                Set<String> baselineSchema = esquemaNormalizado(baseline);
                Set<String> historicalSchema = esquemaNormalizado(historical);
                Set<String> missingFromBaseline = new TreeSet<>(historicalSchema);
                missingFromBaseline.removeAll(baselineSchema);
                Set<String> extraInBaseline = new TreeSet<>(baselineSchema);
                extraInBaseline.removeAll(historicalSchema);
                assertThat(missingFromBaseline)
                        .as("objetos de V1..V12 ausentes en B12")
                        .isEmpty();
                assertThat(extraInBaseline)
                        .as("objetos extra de B12 ausentes en V1..V12")
                        .isEmpty();
                assertThat(codigos(baseline, """
                        SELECT codigo || '|' || descripcion || '|' || modulo || '|' || activo || '|' || sistema
                        FROM permisos
                        """))
                        .as("los datos de referencia deben coincidir")
                        .isEqualTo(codigos(historical, """
                                SELECT codigo || '|' || descripcion || '|' || modulo || '|' || activo || '|' || sistema
                                FROM permisos
                                """));
                assertThat(tablasConDatosFuncionales(baseline)).isEmpty();
                assertThat(contar(historical, "SELECT count(*) FROM tenants")).isOne();
                assertThat(contar(historical, "SELECT count(*) FROM roles")).isEqualTo(6);
                assertThat(contar(baseline, "SELECT count(*) FROM tenants")).isZero();
                assertThat(contar(baseline, "SELECT count(*) FROM usuarios")).isZero();
                assertThat(contar(baseline, "SELECT count(*) FROM tenant_memberships")).isZero();
                assertThat(contar(baseline, "SELECT count(*) FROM roles")).isZero();
                assertThat(contar(baseline, "SELECT count(*) FROM rol_permisos")).isZero();
                assertThat(codigos(historical, "SELECT public.gestudio_multitenancy_health()"))
                        .containsExactly("GREEN");
                assertThat(codigos(baseline, "SELECT public.gestudio_multitenancy_health()"))
                        .containsExactly("GREEN");
                assertThat(contar(baseline, """
                        SELECT count(*)
                        FROM pg_catalog.pg_roles
                        WHERE rolname IN ('gestudio_app', 'gestudio_health', 'gestudio_platform')
                          AND NOT rolsuper
                          AND NOT rolcreaterole
                          AND NOT rolcreatedb
                          AND NOT rolcanlogin
                          AND NOT rolinherit
                          AND NOT rolreplication
                          AND NOT rolbypassrls
                        """))
                        .isEqualTo(3);
            }
        } finally {
            eliminarBase(historicalDatabase);
            eliminarBase(baselineDatabase);
        }
    }

    @Test
    void v5ActualizaDesdeV4YBackfilleaElRolLegado() throws Exception {
        String databaseName = "gestudio_rbac_upgrade_" + UUID.randomUUID().toString().replace("-", "");
        String jdbcUrl = POSTGRESQL.getJdbcUrl().replace(POSTGRESQL.getDatabaseName(), databaseName);

        crearBase(databaseName);

        try {
            Flyway v4 = Flyway.configure()
                    .dataSource(jdbcUrl, POSTGRESQL.getUsername(), POSTGRESQL.getPassword())
                    .configuration(Map.of("flyway.baselineMigrationPrefix", "X_DISABLED_BASELINE"))
                    .target("4")
                    .load();

            v4.migrate();

            try (Connection connection = DriverManager.getConnection(
                    jdbcUrl,
                    POSTGRESQL.getUsername(),
                    POSTGRESQL.getPassword()
            );
                 Statement statement = connection.createStatement()) {
                statement.executeUpdate("""
                        INSERT INTO usuarios(nombre_usuario, contrasena, rol_id)
                        SELECT 'usuario-v4', 'hash-no-real', id
                        FROM roles
                        WHERE descripcion = 'ADMINISTRADOR'
                        """);
            }

            Flyway v5 = Flyway.configure()
                    .dataSource(jdbcUrl, POSTGRESQL.getUsername(), POSTGRESQL.getPassword())
                    .configuration(Map.of("flyway.baselineMigrationPrefix", "X_DISABLED_BASELINE"))
                    .target("5")
                    .load();

            assertThat(v5.migrate().migrationsExecuted).isOne();

            try (Connection connection = DriverManager.getConnection(
                    jdbcUrl,
                    POSTGRESQL.getUsername(),
                    POSTGRESQL.getPassword()
            )) {
                assertThat(contar(connection, """
                        SELECT count(*)
                        FROM usuario_roles ur
                        JOIN usuarios u ON u.id = ur.usuario_id
                        JOIN roles r ON r.id = ur.rol_id
                        WHERE u.nombre_usuario = 'usuario-v4'
                          AND r.codigo = 'ADMINISTRADOR'
                        """))
                        .isOne();

                assertThat(contar(connection, "SELECT count(*) FROM usuarios WHERE rol_id IS NULL"))
                        .isZero();
            }

        } finally {
            eliminarBase(databaseName);
        }
    }

    @Test
    void v7ActualizaHastaLaVersionActualSinPerderIdentidadesAsignacionesNiDatosPersonalizados() throws Exception {
        String databaseName = "gestudio_v7_upgrade_" + UUID.randomUUID().toString().replace("-", "");
        String jdbcUrl = POSTGRESQL.getJdbcUrl().replace(POSTGRESQL.getDatabaseName(), databaseName);

        crearBase(databaseName);

        try {
            Flyway v5 = Flyway.configure()
                    .dataSource(jdbcUrl, POSTGRESQL.getUsername(), POSTGRESQL.getPassword())
                    .configuration(Map.of("flyway.baselineMigrationPrefix", "X_DISABLED_BASELINE"))
                    .target("5")
                    .load();
            assertThat(v5.migrate().migrationsExecuted).isEqualTo(5);

            long administradorId;
            long rolAfectadoId;
            long rolNoAfectadoId;
            long usuarioAdministradorId;
            long usuarioAfectadoId;
            long usuarioNoAfectadoId;
            long permisoAppId;
            long permisoCustomAuditarId;
            long permisoCustomLeerId;

            try (Connection connection = DriverManager.getConnection(
                    jdbcUrl,
                    POSTGRESQL.getUsername(),
                    POSTGRESQL.getPassword()
            ); Statement statement = connection.createStatement()) {
                statement.executeUpdate("""
                        INSERT INTO roles
                            (descripcion, activo, codigo, nombre, descripcion_funcional, sistema, editable)
                        VALUES
                            ('CUSTOM_AFECTADO', TRUE, 'CUSTOM_AFECTADO', 'Custom afectado',
                             'Rol personalizado con permiso canónico previo', FALSE, TRUE),
                            ('CUSTOM_NO_AFECTADO', TRUE, 'CUSTOM_NO_AFECTADO', 'Custom no afectado',
                             'Rol personalizado sin permisos canónicos', FALSE, TRUE)
                        """);
                statement.executeUpdate("""
                        INSERT INTO permisos (codigo, descripcion, modulo, activo, sistema)
                        VALUES
                            ('PERM_APP_ACCESO', 'Metadato previo incompleto', 'APP', FALSE, FALSE),
                            ('PERM_CUSTOM_AUDITAR', 'Permiso personalizado preservado', 'CUSTOM', TRUE, FALSE),
                            ('PERM_CUSTOM_LEER', 'Segundo permiso personalizado preservado', 'CUSTOM', TRUE, FALSE)
                        """);
                statement.executeUpdate("""
                        INSERT INTO rol_permisos (rol_id, permiso_id)
                        SELECT r.id, p.id
                        FROM roles r
                        CROSS JOIN permisos p
                        WHERE (r.codigo = 'CUSTOM_AFECTADO'
                               AND p.codigo IN ('PERM_APP_ACCESO', 'PERM_CUSTOM_AUDITAR'))
                           OR (r.codigo = 'CUSTOM_NO_AFECTADO' AND p.codigo = 'PERM_CUSTOM_LEER')
                        """);
                statement.executeUpdate("""
                        INSERT INTO usuarios
                            (nombre_usuario, contrasena, rol_id, activo, auth_version, version)
                        SELECT 'usuario-admin-v5', 'hash-no-real', id, TRUE, 7, 0
                        FROM roles WHERE codigo = 'SUPERADMIN'
                        UNION ALL
                        SELECT 'usuario-custom-afectado', 'hash-no-real', id, TRUE, 11, 0
                        FROM roles WHERE codigo = 'CUSTOM_AFECTADO'
                        UNION ALL
                        SELECT 'usuario-custom-no-afectado', 'hash-no-real', id, TRUE, 20, 0
                        FROM roles WHERE codigo = 'CUSTOM_NO_AFECTADO'
                        """);
                statement.executeUpdate("""
                        INSERT INTO usuario_roles (usuario_id, rol_id)
                        SELECT u.id, r.id
                        FROM usuarios u
                        JOIN roles r ON r.codigo = CASE u.nombre_usuario
                            WHEN 'usuario-admin-v5' THEN 'ADMINISTRADOR'
                            WHEN 'usuario-custom-afectado' THEN 'CUSTOM_AFECTADO'
                            WHEN 'usuario-custom-no-afectado' THEN 'CUSTOM_NO_AFECTADO'
                        END
                        """);
                statement.executeUpdate("""
                        INSERT INTO refresh_sessions
                            (id, family_id, usuario_id, token_hash, auth_version, issued_at, expires_at)
                        SELECT '11111111-1111-4111-8111-111111111111',
                               '22222222-2222-4222-8222-222222222222',
                               id, repeat('a', 64), 7, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP + INTERVAL '1 day'
                        FROM usuarios WHERE nombre_usuario = 'usuario-admin-v5'
                        """);
                statement.executeUpdate("""
                        INSERT INTO alumnos(nombre, apellido, fecha_incorporacion, documento)
                        VALUES ('Alumno', 'Legacy V7', DATE '2026-01-10', 'LEGACY-V7-001')
                        """);

                administradorId = valor(connection, "SELECT id FROM roles WHERE codigo = 'ADMINISTRADOR'");
                rolAfectadoId = valor(connection, "SELECT id FROM roles WHERE codigo = 'CUSTOM_AFECTADO'");
                rolNoAfectadoId = valor(connection, "SELECT id FROM roles WHERE codigo = 'CUSTOM_NO_AFECTADO'");
                usuarioAdministradorId = valor(connection,
                        "SELECT id FROM usuarios WHERE nombre_usuario = 'usuario-admin-v5'");
                usuarioAfectadoId = valor(connection,
                        "SELECT id FROM usuarios WHERE nombre_usuario = 'usuario-custom-afectado'");
                usuarioNoAfectadoId = valor(connection,
                        "SELECT id FROM usuarios WHERE nombre_usuario = 'usuario-custom-no-afectado'");
                permisoAppId = valor(connection,
                        "SELECT id FROM permisos WHERE codigo = 'PERM_APP_ACCESO'");
                permisoCustomAuditarId = valor(connection,
                        "SELECT id FROM permisos WHERE codigo = 'PERM_CUSTOM_AUDITAR'");
                permisoCustomLeerId = valor(connection,
                        "SELECT id FROM permisos WHERE codigo = 'PERM_CUSTOM_LEER'");
            }

            Flyway v7 = Flyway.configure()
                    .dataSource(jdbcUrl, POSTGRESQL.getUsername(), POSTGRESQL.getPassword())
                    .configuration(Map.of("flyway.baselineMigrationPrefix", "X_DISABLED_BASELINE"))
                    .target("7")
                    .load();
            assertThat(v7.migrate().migrationsExecuted).isEqualTo(2);
            assertThat(v7.info().current().getVersion()).isEqualTo(MigrationVersion.fromVersion("7"));

            try (Connection connection = DriverManager.getConnection(
                    jdbcUrl,
                    POSTGRESQL.getUsername(),
                    POSTGRESQL.getPassword()
            ); Statement statement = connection.createStatement()) {
                statement.executeUpdate("""
                        INSERT INTO jere_platform_student_export_snapshots(
                            checkpoint, organization_id, tenant_id, status, page_size,
                            page_count, total_records, created_by, created_at
                        )
                        SELECT '33333333-3333-4333-8333-333333333333',
                               'org-legacy-v7',
                               '44444444-4444-4444-8444-444444444444',
                               'READY', 100, 1, 1, id, CURRENT_TIMESTAMP
                        FROM usuarios
                        WHERE nombre_usuario = 'usuario-admin-v5'
                        """);
                statement.executeUpdate("""
                        INSERT INTO jere_platform_student_export_pages(
                            snapshot_checkpoint, page_number, cursor_token, next_cursor_token,
                            full_snapshot, record_count, payload, payload_sha256, signature, created_at
                        ) VALUES (
                            '33333333-3333-4333-8333-333333333333', 1, NULL, NULL,
                            TRUE, 1, decode('7b7d', 'hex'), repeat('a', 64),
                            'sha256=' || repeat('b', 64), CURRENT_TIMESTAMP
                        )
                        """);
            }

            Flyway latest = Flyway.configure()
                    .dataSource(jdbcUrl, POSTGRESQL.getUsername(), POSTGRESQL.getPassword())
                    .configuration(Map.of("flyway.baselineMigrationPrefix", "X_DISABLED_BASELINE"))
                    .load();
            MigrationInfo[] pendingMigrations = latest.info().pending();
            assertThat(pendingMigrations).isNotEmpty();
            MigrationVersion expectedLatestVersion = pendingMigrations[pendingMigrations.length - 1].getVersion();
            assertThat(latest.migrate().migrationsExecuted).isEqualTo(pendingMigrations.length);
            assertThat(latest.info().current().getVersion()).isEqualTo(expectedLatestVersion);
            ValidateResult validation = latest.validateWithResult();
            assertThat(validation.validationSuccessful)
                    .withFailMessage(validation.getAllErrorMessages())
                    .isTrue();

            try (Connection connection = DriverManager.getConnection(
                    jdbcUrl,
                    POSTGRESQL.getUsername(),
                    POSTGRESQL.getPassword()
            )) {
                assertThat(valor(connection, "SELECT id FROM roles WHERE codigo = 'ADMINISTRADOR'"))
                        .isEqualTo(administradorId);
                assertThat(valor(connection, "SELECT id FROM roles WHERE codigo = 'CUSTOM_AFECTADO'"))
                        .isEqualTo(rolAfectadoId);
                assertThat(valor(connection, "SELECT id FROM roles WHERE codigo = 'CUSTOM_NO_AFECTADO'"))
                        .isEqualTo(rolNoAfectadoId);
                assertThat(valor(connection,
                        "SELECT id FROM usuarios WHERE nombre_usuario = 'usuario-admin-v5'"))
                        .isEqualTo(usuarioAdministradorId);
                assertThat(valor(connection,
                        "SELECT id FROM usuarios WHERE nombre_usuario = 'usuario-custom-afectado'"))
                        .isEqualTo(usuarioAfectadoId);
                assertThat(valor(connection,
                        "SELECT id FROM usuarios WHERE nombre_usuario = 'usuario-custom-no-afectado'"))
                        .isEqualTo(usuarioNoAfectadoId);
                assertThat(valor(connection, "SELECT id FROM permisos WHERE codigo = 'PERM_APP_ACCESO'"))
                        .isEqualTo(permisoAppId);
                assertThat(valor(connection, "SELECT id FROM permisos WHERE codigo = 'PERM_CUSTOM_AUDITAR'"))
                        .isEqualTo(permisoCustomAuditarId);
                assertThat(valor(connection, "SELECT id FROM permisos WHERE codigo = 'PERM_CUSTOM_LEER'"))
                        .isEqualTo(permisoCustomLeerId);

                assertThat(contar(connection, "SELECT count(*) FROM usuarios")).isEqualTo(3);
                assertThat(contar(connection, "SELECT count(*) FROM usuario_roles")).isEqualTo(3);
                assertThat(contar(connection, "SELECT count(*) FROM tenant_memberships")).isEqualTo(3);
                assertThat(contar(connection, "SELECT count(*) FROM tenant_memberships WHERE status = 'ACTIVE'"))
                        .isEqualTo(3);
                assertThat(contar(connection, "SELECT count(*) FROM tenant_membership_roles"))
                        .isEqualTo(4);
                assertThat(codigos(connection, """
                        SELECT u.nombre_usuario || ':' || r.codigo
                        FROM usuario_roles ur
                        JOIN usuarios u ON u.id = ur.usuario_id
                        JOIN roles r ON r.id = ur.rol_id
                        """))
                        .containsExactlyInAnyOrder(
                                "usuario-admin-v5:ADMINISTRADOR",
                                "usuario-custom-afectado:CUSTOM_AFECTADO",
                                "usuario-custom-no-afectado:CUSTOM_NO_AFECTADO");
                assertThat(contar(connection, """
                        SELECT count(*)
                        FROM platform_admins pa
                        JOIN usuarios u ON u.id = pa.usuario_id
                        WHERE u.nombre_usuario = 'usuario-admin-v5'
                          AND pa.active
                        """))
                        .isOne();
                assertThat(codigos(connection, """
                        SELECT r.codigo
                        FROM tenant_membership_roles tmr
                        JOIN tenant_memberships tm ON tm.id = tmr.membership_id
                        JOIN usuarios u ON u.id = tm.usuario_id
                        JOIN roles r ON r.id = tmr.role_id
                        WHERE u.nombre_usuario = 'usuario-admin-v5'
                        """))
                        .containsExactlyInAnyOrder("SUPERADMIN", "ADMINISTRADOR");
                assertThat(contar(connection,
                        "SELECT count(*) FROM usuarios WHERE contrasena = 'hash-no-real'"))
                        .isEqualTo(3);
                assertThat(contar(connection, """
                        SELECT count(*)
                        FROM rol_permisos rp
                        JOIN roles r ON r.id = rp.rol_id
                        WHERE r.codigo IN ('CUSTOM_AFECTADO', 'CUSTOM_NO_AFECTADO')
                        """))
                        .isEqualTo(3);
                assertThat(codigos(connection, """
                        SELECT p.codigo
                        FROM permisos p
                        WHERE p.codigo IN ('PERM_CUSTOM_AUDITAR', 'PERM_CUSTOM_LEER')
                        """))
                        .containsExactlyInAnyOrder("PERM_CUSTOM_AUDITAR", "PERM_CUSTOM_LEER");

                assertThat(valor(connection,
                        "SELECT auth_version FROM usuarios WHERE nombre_usuario = 'usuario-admin-v5'"))
                        .isEqualTo(8);
                assertThat(valor(connection,
                        "SELECT auth_version FROM usuarios WHERE nombre_usuario = 'usuario-custom-afectado'"))
                        .isEqualTo(12);
                assertThat(valor(connection,
                        "SELECT auth_version FROM usuarios WHERE nombre_usuario = 'usuario-custom-no-afectado'"))
                        .isEqualTo(20);
                assertThat(contar(connection, """
                        SELECT count(*)
                        FROM refresh_sessions s
                        JOIN usuarios u ON u.id = s.usuario_id
                        WHERE s.auth_version <> u.auth_version
                        """))
                        .isOne();
                assertThat(contar(connection, """
                        SELECT count(*)
                        FROM refresh_sessions s
                        JOIN tenant_memberships m
                          ON m.tenant_id = s.tenant_id AND m.id = s.membership_id
                        WHERE s.tenant_id = '00000000-0000-0000-0000-000000000001'
                          AND s.tenant_security_version = 0
                          AND s.membership_security_version = m.security_version
                        """))
                        .isOne();

                assertThat(contar(connection, """
                        SELECT count(*) FROM roles
                        WHERE tenant_id <> '00000000-0000-0000-0000-000000000001'
                        """))
                        .isZero();
                assertThat(contar(connection, """
                        SELECT count(*) FROM alumnos
                        WHERE documento = 'LEGACY-V7-001'
                          AND tenant_id = '00000000-0000-0000-0000-000000000001'
                        """))
                        .isOne();
                assertThat(contar(connection, """
                        SELECT count(*)
                        FROM jere_platform_student_export_snapshots s
                        JOIN jere_platform_tenant_mappings m
                          ON m.internal_tenant_id = s.internal_tenant_id
                         AND m.id = s.mapping_id
                        WHERE s.checkpoint = '33333333-3333-4333-8333-333333333333'
                          AND s.internal_tenant_id = '00000000-0000-0000-0000-000000000001'
                          AND s.external_organization_id = 'org-legacy-v7'
                          AND s.external_tenant_id = '44444444-4444-4444-8444-444444444444'
                        """))
                        .isOne();
                assertThat(contar(connection, """
                        SELECT count(*) FROM jere_platform_student_export_pages
                        WHERE snapshot_checkpoint = '33333333-3333-4333-8333-333333333333'
                          AND internal_tenant_id = '00000000-0000-0000-0000-000000000001'
                        """))
                        .isOne();
                assertThat(codigos(connection, "SELECT public.gestudio_multitenancy_health()"))
                        .containsExactly("GREEN");
                assertThat(contar(connection, """
                        SELECT count(*)
                        FROM pg_catalog.pg_constraint
                        WHERE NOT convalidated
                        """))
                        .isZero();
                assertThat(contar(connection, """
                        SELECT count(*)
                        FROM pg_catalog.pg_class c
                        JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
                        WHERE n.nspname = 'public'
                          AND c.relname = 'refresh_sessions'
                          AND c.relrowsecurity
                          AND c.relforcerowsecurity
                        """))
                        .isOne();

                assertThat(permisosRol(connection, "SUPERADMIN")).isEqualTo(PermissionCodes.ALL);
                assertThat(permisosRol(connection, "DIRECCION")).isEqualTo(DIRECCION);
                assertThat(permisosRol(connection, "ADMINISTRADOR")).isEqualTo(DIRECCION);
                assertThat(permisosRol(connection, "SECRETARIA")).isEqualTo(SECRETARIA);
                assertThat(permisosRol(connection, "CAJA")).isEqualTo(CAJA);
                assertThat(permisosRol(connection, "PROFESOR")).isEmpty();
            }
        } finally {
            eliminarBase(databaseName);
        }
    }

    @Test
    void v6FallaConDiagnosticoSiFaltaElAdministradorLegacy() throws Exception {
        String databaseName = "gestudio_rbac_v6_precondition_" + UUID.randomUUID().toString().replace("-", "");
        String jdbcUrl = POSTGRESQL.getJdbcUrl().replace(POSTGRESQL.getDatabaseName(), databaseName);

        crearBase(databaseName);

        try {
            Flyway v5 = Flyway.configure()
                    .dataSource(jdbcUrl, POSTGRESQL.getUsername(), POSTGRESQL.getPassword())
                    .configuration(Map.of("flyway.baselineMigrationPrefix", "X_DISABLED_BASELINE"))
                    .target("5")
                    .load();
            v5.migrate();

            try (Connection connection = DriverManager.getConnection(
                    jdbcUrl,
                    POSTGRESQL.getUsername(),
                    POSTGRESQL.getPassword()
            ); Statement statement = connection.createStatement()) {
                statement.executeUpdate("DELETE FROM roles WHERE codigo = 'ADMINISTRADOR'");
            }

            Flyway v6 = Flyway.configure()
                    .dataSource(jdbcUrl, POSTGRESQL.getUsername(), POSTGRESQL.getPassword())
                    .configuration(Map.of("flyway.baselineMigrationPrefix", "X_DISABLED_BASELINE"))
                    .load();

            assertThatThrownBy(v6::migrate)
                    .hasStackTraceContaining("falta el rol legacy ADMINISTRADOR");
            assertThat(v6.info().current().getVersion()).isEqualTo(MigrationVersion.fromVersion("5"));
        } finally {
            eliminarBase(databaseName);
        }
    }

    @Test
    void v6FallaConDiagnosticoAnteUnCodigoRoleReservado() throws Exception {
        String databaseName = "gestudio_rbac_v6_role_prefix_" + UUID.randomUUID().toString().replace("-", "");
        String jdbcUrl = POSTGRESQL.getJdbcUrl().replace(POSTGRESQL.getDatabaseName(), databaseName);

        crearBase(databaseName);

        try {
            Flyway v5 = Flyway.configure()
                    .dataSource(jdbcUrl, POSTGRESQL.getUsername(), POSTGRESQL.getPassword())
                    .configuration(Map.of("flyway.baselineMigrationPrefix", "X_DISABLED_BASELINE"))
                    .target("5")
                    .load();
            v5.migrate();

            try (Connection connection = DriverManager.getConnection(
                    jdbcUrl,
                    POSTGRESQL.getUsername(),
                    POSTGRESQL.getPassword()
            ); Statement statement = connection.createStatement()) {
                statement.executeUpdate("""
                        INSERT INTO roles
                            (descripcion, activo, codigo, nombre, descripcion_funcional, sistema, editable)
                        VALUES
                            ('CUSTOM_ROLE_PREFIX', TRUE, 'ROLE_CUSTOM', 'Custom incompatible',
                             'Código reservado incompatible', FALSE, TRUE)
                        """);
            }

            Flyway v6 = Flyway.configure()
                    .dataSource(jdbcUrl, POSTGRESQL.getUsername(), POSTGRESQL.getPassword())
                    .configuration(Map.of("flyway.baselineMigrationPrefix", "X_DISABLED_BASELINE"))
                    .load();

            assertThatThrownBy(v6::migrate)
                    .hasStackTraceContaining("prefijo reservado ROLE_");
            assertThat(v6.info().current().getVersion()).isEqualTo(MigrationVersion.fromVersion("5"));
        } finally {
            eliminarBase(databaseName);
        }
    }

    @Test
    void catalogoBackendFrontendYSeedDemoMantienenUnSoloContrato() throws Exception {
        String frontend = Files.readString(repoFile("frontend/src/config/permissions.ts"));
        var matcher = Pattern.compile("\\bPERM_[A-Z0-9_]+\\b").matcher(frontend);
        Set<String> codigosFrontend = new java.util.TreeSet<>();
        while (matcher.find()) codigosFrontend.add(matcher.group());

        assertThat(codigosFrontend).isEqualTo(PermissionCodes.ALL);

        String seed = Files.readString(repoFile("scripts/gestudio_demo_seed_full.sql"));
        assertThat(seed).doesNotContain("PERM_", "SUPERADMIN");
        assertThat(seed).contains("r.codigo = 'ADMINISTRADOR'");
        assertThat(seed)
                .contains(
                        "Fixture tenant/RBAC explícita",
                        "ON CONFLICT (tenant_id, codigo) DO NOTHING",
                        "CREATE TEMP TABLE _demo_role_matrix",
                        "INSERT INTO public.rol_permisos (tenant_id, rol_id, permiso_id)"
                );
        assertThat(Pattern.compile("(?is)insert\\s+into\\s+public\\.permisos").matcher(seed).find())
                .isFalse();
    }

    private Set<String> esquemaNormalizado(Connection connection) throws Exception {
        Set<String> snapshot = new TreeSet<>();
        List<String> queries = List.of(
                """
                SELECT concat_ws('|', 'REL', c.relkind, c.relname, c.relpersistence,
                                  c.relrowsecurity, c.relforcerowsecurity)
                FROM pg_catalog.pg_class c
                JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
                WHERE n.nspname = 'public'
                  AND c.relkind IN ('r', 'p', 'v', 'm', 'S')
                  AND c.relname NOT LIKE 'flyway_schema_history%'
                """,
                """
                SELECT concat_ws('|', 'COL', c.relname, a.attnum, a.attname,
                                  pg_catalog.format_type(a.atttypid, a.atttypmod),
                                  a.attnotnull, a.attidentity, a.attgenerated,
                                  COALESCE(pg_catalog.pg_get_expr(d.adbin, d.adrelid), '<NULL>'),
                                  COALESCE(coll.collname, '<DEFAULT>'))
                FROM pg_catalog.pg_attribute a
                JOIN pg_catalog.pg_class c ON c.oid = a.attrelid
                JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
                LEFT JOIN pg_catalog.pg_attrdef d
                  ON d.adrelid = a.attrelid AND d.adnum = a.attnum
                LEFT JOIN pg_catalog.pg_collation coll ON coll.oid = a.attcollation
                WHERE n.nspname = 'public'
                  AND c.relkind IN ('r', 'p', 'v', 'm')
                  AND c.relname <> 'flyway_schema_history'
                  AND a.attnum > 0
                  AND NOT a.attisdropped
                """,
                """
                SELECT concat_ws('|', 'CON', c.relname, con.conname, con.contype,
                                  con.condeferrable, con.condeferred, con.convalidated,
                                  CASE WHEN con.contype = 'c' THEN '<CHECK>'
                                       ELSE pg_catalog.pg_get_constraintdef(con.oid, true) END)
                FROM pg_catalog.pg_constraint con
                JOIN pg_catalog.pg_class c ON c.oid = con.conrelid
                JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
                WHERE n.nspname = 'public'
                  AND c.relname <> 'flyway_schema_history'
                """,
                """
                SELECT concat_ws('|', 'IDX', table_class.relname, index_class.relname,
                                  index.indisunique, index.indisprimary, index.indisexclusion,
                                  index.indisvalid, index.indisready,
                                  index.indkey::text, index.indclass::text, index.indoption::text,
                                  index.indpred IS NOT NULL, index.indexprs IS NOT NULL)
                FROM pg_catalog.pg_index index
                JOIN pg_catalog.pg_class table_class ON table_class.oid = index.indrelid
                JOIN pg_catalog.pg_class index_class ON index_class.oid = index.indexrelid
                JOIN pg_catalog.pg_namespace n ON n.oid = table_class.relnamespace
                WHERE n.nspname = 'public'
                  AND table_class.relname <> 'flyway_schema_history'
                """,
                """
                SELECT concat_ws('|', 'TRG', c.relname, trigger.tgname,
                                  pg_catalog.pg_get_triggerdef(trigger.oid, true))
                FROM pg_catalog.pg_trigger trigger
                JOIN pg_catalog.pg_class c ON c.oid = trigger.tgrelid
                JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
                WHERE n.nspname = 'public'
                  AND NOT trigger.tgisinternal
                """,
                """
                SELECT concat_ws('|', 'POL', c.relname, policy.polname, policy.polpermissive,
                                  policy.polcmd,
                                  COALESCE((
                                      SELECT string_agg(COALESCE(role.rolname, 'PUBLIC'), ',' ORDER BY role.rolname)
                                      FROM unnest(policy.polroles) role_oid(oid)
                                      LEFT JOIN pg_catalog.pg_roles role ON role.oid = role_oid.oid
                                  ), 'PUBLIC'),
                                  COALESCE(pg_catalog.pg_get_expr(policy.polqual, policy.polrelid), '<NULL>'),
                                  COALESCE(pg_catalog.pg_get_expr(policy.polwithcheck, policy.polrelid), '<NULL>'))
                FROM pg_catalog.pg_policy policy
                JOIN pg_catalog.pg_class c ON c.oid = policy.polrelid
                JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
                WHERE n.nspname = 'public'
                """,
                """
                SELECT concat_ws('|', 'FUN', procedure.proname,
                                  pg_catalog.pg_get_function_identity_arguments(procedure.oid),
                                  pg_catalog.pg_get_function_result(procedure.oid),
                                  procedure.prokind, procedure.provolatile, procedure.prosecdef,
                                  procedure.proleakproof, procedure.proparallel,
                                  CASE WHEN procedure.proname = 'gestudio_multitenancy_health'
                                       THEN pg_catalog.pg_get_userbyid(procedure.proowner)
                                       ELSE '<MIGRATOR>' END,
                                  COALESCE(array_to_string(procedure.proconfig, ','), '<NULL>'),
                                  pg_catalog.pg_get_functiondef(procedure.oid))
                FROM pg_catalog.pg_proc procedure
                JOIN pg_catalog.pg_namespace n ON n.oid = procedure.pronamespace
                WHERE n.nspname = 'public'
                """,
                """
                SELECT concat_ws('|', 'VIEW', c.relname, pg_catalog.pg_get_viewdef(c.oid, true))
                FROM pg_catalog.pg_class c
                JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
                WHERE n.nspname = 'public' AND c.relkind IN ('v', 'm')
                """,
                """
                SELECT concat_ws('|', 'SEQ', c.relname, sequence.seqtypid::regtype,
                                  sequence.seqstart, sequence.seqincrement, sequence.seqmax,
                                  sequence.seqmin, sequence.seqcache, sequence.seqcycle)
                FROM pg_catalog.pg_sequence sequence
                JOIN pg_catalog.pg_class c ON c.oid = sequence.seqrelid
                JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
                WHERE n.nspname = 'public'
                """,
                """
                SELECT concat_ws('|', 'ACL_REL', c.relkind, c.relname,
                                  COALESCE(grantee.rolname, 'PUBLIC'), acl.privilege_type,
                                  acl.is_grantable)
                FROM pg_catalog.pg_class c
                JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
                CROSS JOIN LATERAL pg_catalog.aclexplode(c.relacl) acl
                LEFT JOIN pg_catalog.pg_roles grantee ON grantee.oid = acl.grantee
                WHERE n.nspname = 'public'
                  AND COALESCE(grantee.rolname, 'PUBLIC') <> current_user
                  AND c.relname NOT LIKE 'flyway_schema_history%'
                """,
                """
                SELECT concat_ws('|', 'ACL_FUN', procedure.proname,
                                  pg_catalog.pg_get_function_identity_arguments(procedure.oid),
                                  COALESCE(grantee.rolname, 'PUBLIC'), acl.privilege_type,
                                  acl.is_grantable)
                FROM pg_catalog.pg_proc procedure
                JOIN pg_catalog.pg_namespace n ON n.oid = procedure.pronamespace
                CROSS JOIN LATERAL pg_catalog.aclexplode(procedure.proacl) acl
                LEFT JOIN pg_catalog.pg_roles grantee ON grantee.oid = acl.grantee
                WHERE n.nspname = 'public'
                  AND COALESCE(grantee.rolname, 'PUBLIC') <> current_user
                """,
                """
                SELECT concat_ws('|', 'ACL_SCHEMA', n.nspname,
                                  COALESCE(grantee.rolname, 'PUBLIC'), acl.privilege_type,
                                  acl.is_grantable)
                FROM pg_catalog.pg_namespace n
                CROSS JOIN LATERAL pg_catalog.aclexplode(n.nspacl) acl
                LEFT JOIN pg_catalog.pg_roles grantee ON grantee.oid = acl.grantee
                WHERE n.nspname = 'public'
                  AND COALESCE(grantee.rolname, 'PUBLIC') <> current_user
                """
        );

        for (String query : queries) {
            snapshot.addAll(filas(connection, query));
        }
        return snapshot;
    }

    private Set<String> tablasConDatosFuncionales(Connection connection) throws Exception {
        Set<String> nonEmptyTables = new TreeSet<>();
        List<String> tables = filas(connection, """
                SELECT table_name
                FROM information_schema.tables
                WHERE table_schema = 'public'
                  AND table_type = 'BASE TABLE'
                  AND table_name NOT IN ('permisos', 'flyway_schema_history')
                ORDER BY table_name
                """);

        try (Statement statement = connection.createStatement()) {
            for (String table : tables) {
                if (!table.matches("[a-z0-9_]+")) {
                    throw new IllegalStateException("Nombre de tabla no canónico: " + table);
                }
                try (ResultSet rows = statement.executeQuery(
                        "SELECT EXISTS (SELECT 1 FROM public." + table + ")")) {
                    rows.next();
                    if (rows.getBoolean(1)) nonEmptyTables.add(table);
                }
            }
        }
        return nonEmptyTables;
    }

    private List<String> filas(Connection connection, String sql) throws Exception {
        List<String> rows = new ArrayList<>();
        try (Statement statement = connection.createStatement();
             ResultSet result = statement.executeQuery(sql)) {
            while (result.next()) {
                rows.add(result.getString(1).replace("\r\n", "\n").replace('\r', '\n'));
            }
        }
        return rows;
    }

    private void crearBase(String databaseName) throws Exception {
        try (Connection admin = POSTGRESQL.createConnection("");
             Statement statement = admin.createStatement()) {
            admin.setAutoCommit(true);
            statement.execute("CREATE DATABASE " + databaseName);
        }
    }

    private void eliminarBase(String databaseName) throws Exception {
        try (Connection admin = POSTGRESQL.createConnection("");
             Statement statement = admin.createStatement()) {
            admin.setAutoCommit(true);
            statement.execute("DROP DATABASE " + databaseName + " WITH (FORCE)");
        }
    }

    private Set<String> tablas(Connection connection) throws Exception {
        Set<String> tables = new java.util.TreeSet<>();

        try (Statement statement = connection.createStatement();
             ResultSet result = statement.executeQuery("""
                     SELECT table_name
                     FROM information_schema.tables
                     WHERE table_schema = 'public'
                       AND table_type = 'BASE TABLE'
                     ORDER BY table_name
                     """)) {
            while (result.next()) {
                tables.add(result.getString(1));
            }
        }

        return tables;
    }

    private Set<String> permisosRol(Connection connection, String rolCodigo) throws Exception {
        return codigos(connection, """
                SELECT p.codigo
                FROM rol_permisos rp
                JOIN roles r ON r.id = rp.rol_id
                JOIN permisos p ON p.id = rp.permiso_id
                WHERE r.codigo = '%s'
                """.formatted(rolCodigo));
    }

    private Set<String> codigos(Connection connection, String sql) throws Exception {
        Set<String> result = new java.util.TreeSet<>();
        try (Statement statement = connection.createStatement();
             ResultSet rows = statement.executeQuery(sql)) {
            while (rows.next()) result.add(rows.getString(1));
        }
        return result;
    }

    private long valor(Connection connection, String sql) throws Exception {
        try (Statement statement = connection.createStatement();
             ResultSet result = statement.executeQuery(sql)) {
            result.next();
            return result.getLong(1);
        }
    }

    private Path repoFile(String relativePath) {
        Path cwd = Path.of("").toAbsolutePath();
        Path root = Files.isDirectory(cwd.resolve("frontend")) ? cwd : cwd.getParent();
        return root.resolve(relativePath);
    }

    private long contar(Connection connection, String sql) throws Exception {
        try (Statement statement = connection.createStatement();
             ResultSet result = statement.executeQuery(sql)) {
            result.next();
            return result.getLong(1);
        }
    }
}
