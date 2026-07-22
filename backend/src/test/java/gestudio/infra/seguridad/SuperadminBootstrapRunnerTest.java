package gestudio.infra.seguridad;

import gestudio.entidades.Usuario;
import org.junit.jupiter.api.Test;
import org.springframework.boot.DefaultApplicationArguments;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class SuperadminBootstrapRunnerTest {

    private final SuperadminBootstrapService service = mock(SuperadminBootstrapService.class);

    @Test
    void deshabilitadoNoHaceNada() {
        runner(false).run(new DefaultApplicationArguments());

        verify(service, never()).bootstrap(org.mockito.ArgumentMatchers.any(), org.mockito.ArgumentMatchers.any());
    }

    @Test
    void usaVariablesNuevas() {
        Usuario usuario = new Usuario();
        usuario.setId(1L);
        when(service.bootstrap("root", "clave-superadmin-segura")).thenReturn(usuario);

        runner(true).run(new DefaultApplicationArguments());

        verify(service).bootstrap("root", "clave-superadmin-segura");
    }

    @Test
    void reinicioPropagaElRechazoDeEjecucionUnica() {
        when(service.bootstrap("root", "clave-superadmin-segura"))
                .thenThrow(new IllegalStateException("El bootstrap SUPERADMIN ya fue ejecutado"));

        assertThatThrownBy(() -> runner(true).run(new DefaultApplicationArguments()))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("ya fue ejecutado");

        verify(service).bootstrap("root", "clave-superadmin-segura");
    }

    private SuperadminBootstrapRunner runner(boolean enabled) {
        return new SuperadminBootstrapRunner(
                new SuperadminBootstrapProperties(enabled, "root", "clave-superadmin-segura"),
                service);
    }
}
