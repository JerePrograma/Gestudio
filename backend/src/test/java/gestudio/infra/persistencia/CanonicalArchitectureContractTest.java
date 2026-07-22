package gestudio.infra.persistencia;

import jakarta.persistence.Entity;
import org.junit.jupiter.api.Test;
import org.springframework.web.bind.annotation.RequestMapping;

import java.io.IOException;
import java.lang.reflect.ParameterizedType;
import java.lang.reflect.Type;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Set;
import java.util.TreeSet;
import java.util.regex.Pattern;
import java.util.stream.IntStream;
import java.util.stream.Stream;

import static org.assertj.core.api.Assertions.assertThat;

class CanonicalArchitectureContractTest {

    private static final List<String> REMOVED_MODEL = List.of(
            "DetallePago", "PaymentProcessor", "PaymentCalculationServicio", "ProcesoEjecutado",
            "esClon", "es_clon"
    );

    private static final Pattern JAVA_FLOATING_POINT =
            Pattern.compile("\\b(?:Double|double|Float|float)\\b");

    private static final Pattern UNCONTROLLED_TIME =
            Pattern.compile("\\b(?:LocalDate|LocalDateTime|YearMonth)\\.now\\(\\s*\\)");

    private static final Pattern TYPESCRIPT_MONEY_NUMBER = Pattern.compile(
            "(?i)\\b(?:monto|importe|precio|saldo|credito|valorCuota|matricula|claseSuelta|clasePrueba|recargo|porcentaje|valorFijo|costoParticular)\\??\\s*:\\s*number\\b"
    );

    private static final Pattern MIGRATION_FILE = Pattern.compile("^V[1-9][0-9]*__.+\\.sql$");

    private final Path root = repositoryRoot();

    @Test
    void conservaV1CongeladaYAvanzaConMigracionesForwardOnly() throws IOException {
        Path migrations = root.resolve("backend/src/main/resources/db/migration");

        try (Stream<Path> files = Files.list(migrations)) {
            List<String> migrationFiles = files
                    .filter(Files::isRegularFile)
                    .map(path -> path.getFileName().toString())
                    .toList();

            assertThat(migrationFiles)
                    .isNotEmpty()
                    .allMatch(MIGRATION_FILE.asMatchPredicate())
                    .contains("V1__canonical_schema.sql")
                    .noneMatch(name -> name.toLowerCase().contains("demo") && name.toLowerCase().contains("seed"));

            List<Integer> versions = migrationFiles.stream()
                    .map(name -> Integer.parseInt(name.substring(1, name.indexOf("__"))))
                    .sorted()
                    .toList();
            assertThat(versions)
                    .containsExactlyElementsOf(IntStream.rangeClosed(1, versions.size()).boxed().toList());
        }
    }

    @Test
    void statusDemoDerivaFlywayYValidaMetadataDeLasImagenes() throws IOException {
        String script = Files.readString(root.resolve("scripts/demo-local.ps1"));
        String status = functionBody(script, "Invoke-Status", "Invoke-Start");

        assertThat(status)
                .contains(
                        "$manifest = Get-LocalMigrationManifest",
                        "$history[0] -eq [string]$manifest.Count",
                        "$history[1] -eq [string]$manifest.LatestVersion",
                        "Get-ImageFreshness -Service \"backend\"",
                        "Get-ImageFreshness -Service \"frontend\"",
                        "-ExpectedFlyway ([string]$manifest.LatestVersion)",
                        "-ExpectedSourceSha $expectedBackendSourceSha",
                        "-ExpectedSourceSha $expectedFrontendSourceSha",
                        "-ExpectedHealthContract \"actuator-readiness-v1\"",
                        "$backendFresh.Ready",
                        "$frontendFresh.Ready",
                        "$seedReady = Test-DemoSeedContract"
                );

        assertThat(Pattern.compile(
                "(?i)\\$flyway\\s*-(?:eq|ne|lt|le|gt|ge)\\s*['\\\"]?\\d+"
        ).matcher(status).find())
                .as("Invoke-Status no debe comparar Flyway contra una versión numérica rígida")
                .isFalse();

        assertThat(script)
                .contains(
                        "function Get-LocalMigrationManifest",
                        "function Get-SourceFingerprint",
                        "function Get-ImageFreshness",
                        "{{.Image}}",
                        "{{json .Config.Labels}}",
                        "org.opencontainers.image.revision",
                        "org.gestudio.compose.sha256",
                        "org.gestudio.source.sha256",
                        "/app/build-metadata/flyway-latest",
                        "/app/build-metadata/health-contract"
                );
    }

    @Test
    void validadoresOperativosDerivanLaCadenaFlywaySinVersionRigida() throws IOException {
        List<String> scripts = List.of(
                "scripts/smoke-local.ps1",
                "scripts/ops/verify-backup-restore.ps1",
                "scripts/ops/verify-application-rollback.ps1"
        );
        Pattern expectedPair = Pattern.compile("(?i)-Expected\\s+['\"]?\\d+\\|\\d+");
        Pattern rigidRange = Pattern.compile("(?i)BETWEEN\\s+1\\s+AND\\s+\\d+");
        Pattern rigidMetadata = Pattern.compile("(?i)printf\\s+['\"]\\d+\\\\n['\"][^\\n]*flyway-latest");

        for (String relativePath : scripts) {
            String script = Files.readString(root.resolve(relativePath));
            assertThat(script)
                    .as(relativePath)
                    .contains("function Get-LocalMigrationManifest", ".LatestVersion", ".Count");
            assertThat(expectedPair.matcher(script).find())
                    .as("par count/latest rígido en %s", relativePath)
                    .isFalse();
            assertThat(rigidRange.matcher(script).find())
                    .as("rango Flyway rígido en %s", relativePath)
                    .isFalse();
            assertThat(rigidMetadata.matcher(script).find())
                    .as("metadata Flyway rígida en %s", relativePath)
                    .isFalse();
        }
    }

    @Test
    void statusDemoExigeDatasetCompletoCumpleanosYMatrizRbac() throws IOException {
        String script = Files.readString(root.resolve("scripts/demo-local.ps1"));
        String contract = functionBody(script, "Test-DemoSeedContract", "Invoke-DemoSeed");

        assertThat(contract)
                .contains(
                        "'usuarios',5",
                        "'alumnos',28",
                        "'pagos',48",
                        "'recibos_pendientes',48",
                        "= 914",
                        "expected_matrix(role_code, permission_code)",
                        "NOT EXISTS (SELECT 1 FROM matrix_diff)",
                        "NOT EXISTS (SELECT 1 FROM demo_user_diff)",
                        "America/Argentina/Buenos_Aires",
                        "documento='49287134'"
                );
    }

    @Test
    void configuracionActivaNoConservaAliasLegacyDelBootstrapAdmin() throws IOException {
        for (String relativePath : List.of(
                "backend/src/main/resources/application.yml",
                "docker-compose.yml",
                ".env.local.example",
                "scripts/demo-local.ps1",
                "scripts/validate-demo-seed.ps1",
                "scripts/smoke-local.ps1",
                "scripts/ops/verify-observability.ps1",
                "scripts/ops/verify-backup-restore.ps1",
                "scripts/ops/verify-application-rollback.ps1"
        )) {
            String source = Files.readString(root.resolve(relativePath));
            assertThat(source)
                    .as("configuración legacy en %s", relativePath)
                    .doesNotContain("APP_BOOTSTRAP_ADMIN", "app.bootstrap-admin");
        }

        assertThat(Files.readString(root.resolve("backend/src/main/resources/application.yml")))
                .contains(
                        "APP_LOCAL_ADMIN_PASSWORD_RESET_ENABLED",
                        "APP_LOCAL_ADMIN_PASSWORD_RESET_USERNAME",
                        "APP_LOCAL_ADMIN_PASSWORD_RESET_PASSWORD"
                );
    }

    @Test
    void scriptsPowerShellSonUtf8BomLfYEstrictos() throws IOException {
        Path scriptsRoot = root.resolve("scripts");
        try (Stream<Path> paths = Files.walk(scriptsRoot)) {
            for (Path path : paths.filter(Files::isRegularFile)
                    .filter(file -> file.toString().endsWith(".ps1"))
                    .toList()) {
                byte[] bytes = Files.readAllBytes(path);
                assertThat(bytes)
                        .as("UTF-8 BOM en %s", root.relativize(path))
                        .startsWith((byte) 0xEF, (byte) 0xBB, (byte) 0xBF);
                String script = Files.readString(path);
                assertThat(script)
                        .as("EOL LF en %s", root.relativize(path))
                        .doesNotContain("\r");

                if (!path.getFileName().toString().equals("use-local-java.ps1")) {
                    assertThat(script)
                            .as("modo estricto en %s", root.relativize(path))
                            .contains("Set-StrictMode -Version Latest", "$ErrorActionPreference = ")
                            .containsAnyOf("\"Stop\"", "'Stop'");
                }
                if (script.contains("[Net.Http.")) {
                    assertThat(script)
                            .as("carga explícita de System.Net.Http para PowerShell 5.1 en %s", root.relativize(path))
                            .contains("Add-Type -AssemblyName System.Net.Http");
                }
            }
        }
    }

    @Test
    void drillsComposeAislanVariablesDelHost() throws IOException {
        for (String relativePath : List.of(
                "scripts/ops/verify-backup-restore.ps1",
                "scripts/ops/verify-application-rollback.ps1",
                "scripts/ops/verify-observability.ps1"
        )) {
            String script = Files.readString(root.resolve(relativePath));
            assertThat(script)
                    .as("aislamiento de variables Compose en %s", relativePath)
                    .contains(
                            "$previousProcessEnvironment = @{}",
                            "[Environment]::GetEnvironmentVariable($entry.Key, 'Process')",
                            "[Environment]::SetEnvironmentVariable($entry.Key, [string]$entry.Value, 'Process')",
                            "[Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process')"
                    );
        }
    }

    @Test
    void drillsSqlNoDependenDelQuotingNativoDeWindowsPowerShell() throws IOException {
        for (String relativePath : List.of(
                "scripts/ops/backup-postgres.ps1",
                "scripts/ops/restore-postgres.ps1",
                "scripts/ops/rollback-backend.ps1",
                "scripts/ops/verify-backup-restore.ps1",
                "scripts/ops/verify-application-rollback.ps1"
        )) {
            String script = Files.readString(root.resolve(relativePath));
            assertThat(script)
                    .as("transporte SQL seguro en PowerShell 5.1 para %s", relativePath)
                    .contains(
                            "base64 -d",
                            "--file=-"
                    )
                    .containsAnyOf(
                            "[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Sql))",
                            "[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($sql))"
                    )
                    .doesNotContain("--command=\"$1\"", "--command=\"$2\"");
        }

        String verifier = Files.readString(root.resolve("scripts/ops/verify-backup-restore.ps1"));
        assertThat(verifier)
                .contains(
                        "[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($script))",
                        "/tmp/gestudio-adversarial.sh"
                )
                .doesNotContain("'backend', '-ec', $script");

        String restore = Files.readString(root.resolve("scripts/ops/restore-postgres.ps1"));
        assertThat(restore)
                .contains(
                        "[Text.Encoding]::UTF8.GetBytes($receiptsArchiveScript)",
                        "/tmp/gestudio-restore-receipts.sh",
                        "[Text.Encoding]::UTF8.GetBytes($restoreDatabaseScript)",
                        "/tmp/gestudio-restore-database.sh",
                        "'exec', $dbContainer, 'sha256sum', $remoteDump"
                )
                .doesNotContain(
                        "'-ec', $receiptsArchiveScript",
                        "value=\"$(sha256sum"
                );
    }

    @Test
    void seedDemoRecibeFechaDeNegocioYContratoFlywayDinamico() throws IOException {
        String demo = Files.readString(root.resolve("scripts/demo-local.ps1"));
        String validator = Files.readString(root.resolve("scripts/validate-demo-seed.ps1"));
        String seed = Files.readString(root.resolve("scripts/gestudio_demo_seed_full.sql"));

        assertThat(demo)
                .contains(
                        "\\set demo_business_date $($BusinessDate.ToString('yyyy-MM-dd'))",
                        "\\set demo_expected_flyway_count $($manifest.Count)",
                        "\\set demo_expected_flyway_latest $($manifest.LatestVersion)"
                );
        assertThat(validator)
                .contains(
                        "\"-v\", \"demo_business_date=$($script:businessDate.ToString('yyyy-MM-dd'))\"",
                        "\"-v\", \"demo_expected_flyway_count=$($script:migrationManifest.Count)\"",
                        "\"-v\", \"demo_expected_flyway_latest=$($script:migrationManifest.LatestVersion)\""
                );
        assertThat(seed)
                .contains(
                        ":'demo_business_date'::date AS business_date",
                        ":'demo_expected_flyway_count'::integer AS expected_flyway_count",
                        ":'demo_expected_flyway_latest'::integer AS expected_flyway_latest"
                );

        Pattern fixedMigrationName = Pattern.compile("V[0-9]+__");
        for (String source : List.of(demo, validator, seed)) {
            assertThat(fixedMigrationName.matcher(source).find())
                    .as("los validadores demo no deben fijar nombres de migración")
                    .isFalse();
        }
    }

    @Test
    void v5RbacEsEstructuralSinSeedOperativo() throws IOException {
        Path v5 = root.resolve("backend/src/main/resources/db/migration/V5__base_roles_permissions_seed.sql");
        String sql = Files.readString(v5);

        assertThat(sql)
                .contains(
                        "CREATE TABLE public.permisos",
                        "CREATE TABLE public.rol_permisos",
                        "CREATE TABLE public.usuario_roles",
                        "INSERT INTO public.usuario_roles"
                );

        assertThat(sql)
                .as("V5 no debe seedear permisos operativos")
                .doesNotContain("INSERT INTO public.permisos");

        assertThat(sql)
                .as("V5 no debe seedear roles operativos")
                .doesNotContain("INSERT INTO public.roles");

        assertThat(sql)
                .as("V5 no debe asignar permisos a roles")
                .doesNotContain("INSERT INTO public.rol_permisos");
    }

    @Test
    void noReintroduceModeloFinancieroEliminadoNiAntipatronesProductivos() throws IOException {
        String backend = source(root.resolve("backend/src/main"));
        String frontend = source(root.resolve("frontend/src"));

        for (String removed : REMOVED_MODEL) {
            assertThat(backend).as("modelo eliminado en backend: %s", removed).doesNotContain(removed);
            assertThat(frontend).as("modelo eliminado en frontend: %s", removed).doesNotContain(removed);
        }

        assertThat(filesContaining(root.resolve("backend/src/main"), JAVA_FLOATING_POINT))
                .as("float permitido solo para anchos de columnas PDF, nunca para dinero")
                .containsExactly("backend/src/main/java/gestudio/servicios/pdfs/PdfService.java");

        assertThat(UNCONTROLLED_TIME.matcher(backend).find())
                .as("reloj del sistema sin Clock")
                .isFalse();

        assertThat(backend)
                .doesNotContain("printStackTrace(", "@Data", "/api/deudas", "/api/email");

        assertThat(backend)
                .doesNotContain("/api/detalle-pago", "saldo_credito");

        assertThat(frontend)
                .doesNotContain("IntersectionObserver", "InfiniteScroll");

        assertThat(TYPESCRIPT_MONEY_NUMBER.matcher(frontend).find())
                .as("contrato monetario TypeScript declarado como number")
                .isFalse();
    }

    @Test
    void losControladoresNoExponenEntidadesJpa() throws Exception {
        Path controllers = root.resolve("backend/src/main/java/gestudio/controladores");

        try (Stream<Path> paths = Files.list(controllers)) {
            for (Path path : paths
                    .filter(file -> file.toString().endsWith("Controlador.java"))
                    .toList()) {

                Class<?> controller = Class.forName("gestudio.controladores."
                        + path.getFileName().toString().replace(".java", ""));

                for (var method : controller.getDeclaredMethods()) {
                    if (isEndpointMethod(method.getDeclaredAnnotations())) {
                        assertThat(containsEntity(method.getGenericReturnType()))
                                .as("retorno JPA en %s#%s", controller.getSimpleName(), method.getName())
                                .isFalse();
                    }
                }
            }
        }
    }

    private boolean isEndpointMethod(java.lang.annotation.Annotation[] annotations) {
        return Stream.of(annotations)
                .anyMatch(annotation -> annotation.annotationType().isAnnotationPresent(RequestMapping.class));
    }

    private boolean containsEntity(Type type) {
        if (type instanceof Class<?> clazz) {
            return clazz.isAnnotationPresent(Entity.class);
        }

        if (type instanceof ParameterizedType parameterized) {
            return containsEntity(parameterized.getRawType())
                    || Stream.of(parameterized.getActualTypeArguments()).anyMatch(this::containsEntity);
        }

        return false;
    }

    private String source(Path sourceRoot) throws IOException {
        StringBuilder content = new StringBuilder();

        try (Stream<Path> paths = Files.walk(sourceRoot)) {
            for (Path path : paths
                    .filter(Files::isRegularFile)
                    .filter(file -> file.toString().endsWith(".java")
                            || file.toString().endsWith(".sql")
                            || file.toString().endsWith(".ts")
                            || file.toString().endsWith(".tsx"))
                    .toList()) {
                content.append(Files.readString(path)).append('\n');
            }
        }

        return content.toString();
    }

    private Set<String> filesContaining(Path sourceRoot, Pattern pattern) throws IOException {
        Set<String> matches = new TreeSet<>();

        try (Stream<Path> paths = Files.walk(sourceRoot)) {
            for (Path path : paths
                    .filter(Files::isRegularFile)
                    .filter(file -> file.toString().endsWith(".java"))
                    .toList()) {
                if (pattern.matcher(Files.readString(path)).find()) {
                    matches.add(root.relativize(path).toString().replace('\\', '/'));
                }
            }
        }

        return matches;
    }

    private String functionBody(String script, String function, String nextFunction) {
        int start = script.indexOf("function " + function);
        int end = script.indexOf("function " + nextFunction, start);

        assertThat(start).as("función PowerShell %s", function).isGreaterThanOrEqualTo(0);
        assertThat(end).as("función PowerShell siguiente a %s", function).isGreaterThan(start);
        return script.substring(start, end);
    }

    private Path repositoryRoot() {
        Path current = Path.of(System.getProperty("user.dir")).toAbsolutePath().normalize();
        return current.getFileName().toString().equals("backend") ? current.getParent() : current;
    }
}
