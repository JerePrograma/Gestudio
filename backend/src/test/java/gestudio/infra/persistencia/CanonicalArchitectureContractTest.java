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

    private final Path root = repositoryRoot();

    @Test
    void conservaV1CongeladaYAvanzaConMigracionesForwardOnly() throws IOException {
        Path migrations = root.resolve("backend/src/main/resources/db/migration");

        try (Stream<Path> files = Files.list(migrations)) {
            assertThat(files
                    .filter(Files::isRegularFile)
                    .map(path -> path.getFileName().toString())
                    .sorted()
                    .toList())
                    .containsExactly(
                            "V1__canonical_schema.sql",
                            "V2__security_superadmin_sessions_audit.sql",
                            "V3__effective_dated_pricing.sql",
                            "V4__cargo_liquidations_and_events.sql",
                            "V5__base_roles_permissions_seed.sql"
                    );
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

    private Path repositoryRoot() {
        Path current = Path.of(System.getProperty("user.dir")).toAbsolutePath().normalize();
        return current.getFileName().toString().equals("backend") ? current.getParent() : current;
    }
}