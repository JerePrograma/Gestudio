package gestudio.infra.persistencia;

import gestudio.Main;
import gestudio.infra.seguridad.PermissionCodes;
import org.flywaydb.core.Flyway;
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
import java.util.Set;
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
            "jere_platform_student_export_snapshots", "jere_platform_student_export_pages"
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

            assertThat(flyway.migrate().migrationsExecuted).isEqualTo(7);

            ValidateResult validation = flyway.validateWithResult();

            assertThat(flyway.info().current()).isNotNull();
            assertThat(flyway.info().current().getVersion()).isEqualTo(MigrationVersion.fromVersion("7"));
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
                assertThat(codigos(connection, "SELECT codigo FROM roles WHERE sistema"))
                        .isEqualTo(BASE_ROLES);
                assertThat(contar(connection, """
                        SELECT count(*) FROM roles
                        WHERE codigo = 'SUPERADMIN' AND activo AND sistema AND NOT editable
                        """))
                        .isOne();
                assertThat(contar(connection, """
                        SELECT count(*) FROM roles
                        WHERE codigo IN ('DIRECCION', 'ADMINISTRADOR', 'SECRETARIA', 'CAJA')
                          AND activo AND sistema AND editable
                        """))
                        .isEqualTo(4);
                assertThat(contar(connection, """
                        SELECT count(*) FROM roles
                        WHERE codigo = 'PROFESOR' AND NOT activo AND sistema AND NOT editable
                        """))
                        .isOne();
                assertThat(permisosRol(connection, "SUPERADMIN")).isEqualTo(PermissionCodes.ALL);
                assertThat(permisosRol(connection, "DIRECCION")).isEqualTo(DIRECCION);
                assertThat(permisosRol(connection, "ADMINISTRADOR")).isEqualTo(DIRECCION);
                assertThat(permisosRol(connection, "SECRETARIA")).isEqualTo(SECRETARIA);
                assertThat(permisosRol(connection, "CAJA")).isEqualTo(CAJA);
                assertThat(permisosRol(connection, "PROFESOR")).isEmpty();
                assertThat(contar(connection, "SELECT count(*) FROM roles WHERE codigo ~ '^ROLE_'"))
                        .isZero();

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
                              'jere_platform_student_export_pages'
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
                              ('rol_permisos', 'fk_rol_permisos_rol'),
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
                              AND (i.indkey::smallint[])[0:cardinality(c.conkey)-1] @> c.conkey
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
                    "--spring.flyway.enabled=false",
                    "--spring.jpa.hibernate.ddl-auto=validate"
            ).close())
                    .doesNotThrowAnyException();

        } finally {
            eliminarBase(databaseName);
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
    void migracionesPosterioresActualizanDesdeV5SinPerderIdentidadesAsignacionesNiDatosPersonalizados() throws Exception {
        String databaseName = "gestudio_rbac_v6_upgrade_" + UUID.randomUUID().toString().replace("-", "");
        String jdbcUrl = POSTGRESQL.getJdbcUrl().replace(POSTGRESQL.getDatabaseName(), databaseName);

        crearBase(databaseName);

        try {
            Flyway v5 = Flyway.configure()
                    .dataSource(jdbcUrl, POSTGRESQL.getUsername(), POSTGRESQL.getPassword())
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
                        FROM roles WHERE codigo = 'ADMINISTRADOR'
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

            Flyway latest = Flyway.configure()
                    .dataSource(jdbcUrl, POSTGRESQL.getUsername(), POSTGRESQL.getPassword())
                    .load();
            assertThat(latest.migrate().migrationsExecuted).isEqualTo(2);
            assertThat(latest.info().current().getVersion()).isEqualTo(MigrationVersion.fromVersion("7"));

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
        assertThat(Pattern.compile("(?is)insert\\s+into\\s+public\\.roles").matcher(seed).find())
                .isFalse();
        assertThat(Pattern.compile("(?is)insert\\s+into\\s+public\\.permisos").matcher(seed).find())
                .isFalse();
        assertThat(Pattern.compile("(?is)insert\\s+into\\s+public\\.rol_permisos").matcher(seed).find())
                .isFalse();
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
