package gestudio.infra.seguridad;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.boot.DefaultApplicationArguments;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class SuperadminBootstrapRunnerTest {
    private static final String SECRET = "JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP";
    private final SuperadminBootstrapService service = mock(SuperadminBootstrapService.class);

    @TempDir Path temp;

    @Test
    void soloExisteConBanderaExplicita() {
        ConditionalOnProperty condition = SuperadminBootstrapRunner.class
                .getAnnotation(ConditionalOnProperty.class);

        assertThat(condition.name()).containsExactly("app.bootstrap-superadmin.enabled");
        assertThat(condition.havingValue()).isEqualTo("true");
        assertThat(condition.matchIfMissing()).isFalse();
        verify(service, never()).bootstrap(any(), any(), any(), any(), any());
    }

    @Test
    void entregaRecoveryCodesSoloPorArchivoOneTime() throws Exception {
        Path output = temp.resolve("codes.txt");
        doAnswer(invocation -> {
            @SuppressWarnings("unchecked")
            java.util.function.Consumer<List<String>> sink = invocation.getArgument(4);
            sink.accept(List.of("A", "B", "C", "D", "E", "F", "G", "H", "I", "J"));
            return new SuperadminBootstrapService.BootstrapResult(1L, "root");
        }).when(service).bootstrap(eq("root"), eq("clave-superadmin-segura"),
                eq(SECRET), eq("123456"), any());

        runner(output).run(new DefaultApplicationArguments());

        assertThat(Files.readAllLines(output)).hasSize(10).containsExactly(
                "A", "B", "C", "D", "E", "F", "G", "H", "I", "J");
    }

    @Test
    void noSobrescribeRecoveryCodesExistentes() throws Exception {
        Path output = temp.resolve("codes.txt");
        Files.writeString(output, "preservar");
        doAnswer(invocation -> {
            @SuppressWarnings("unchecked")
            java.util.function.Consumer<List<String>> sink = invocation.getArgument(4);
            sink.accept(List.of("nuevo"));
            return new SuperadminBootstrapService.BootstrapResult(1L, "root");
        }).when(service).bootstrap(any(), any(), any(), any(), any());

        assertThatThrownBy(() -> runner(output).run(new DefaultApplicationArguments()))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("recovery codes");
        assertThat(Files.readString(output)).isEqualTo("preservar");
    }

    @Test
    void reinicioPropagaElRechazoDeEjecucionUnica() {
        when(service.bootstrap(any(), any(), any(), any(), any()))
                .thenThrow(new IllegalStateException("El bootstrap SUPERADMIN ya fue ejecutado"));

        assertThatThrownBy(() -> runner(temp.resolve("codes.txt"))
                .run(new DefaultApplicationArguments()))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("ya fue ejecutado");
    }

    private SuperadminBootstrapRunner runner(Path output) {
        return new SuperadminBootstrapRunner(new SuperadminBootstrapProperties(
                true, "root", "clave-superadmin-segura", SECRET, "123456",
                output.toString()), service);
    }
}
