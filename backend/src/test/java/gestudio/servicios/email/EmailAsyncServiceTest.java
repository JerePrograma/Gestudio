package gestudio.servicios.email;

import gestudio.entidades.Alumno;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class EmailAsyncServiceTest {

    @Test
    void cumpleañosDelegaSinFromLibreYConResultadoControlado() {
        IEmailService email = mock(IEmailService.class);
        when(email.sendEmailWithInlineImage(any(), any(), any(), any(), any(), any()))
                .thenReturn(EmailDeliveryResult.of(EmailDeliveryResult.Status.NOOP));

        new EmailAsyncService(email).enviarMailCumple(alumno());

        verify(email).sendEmailWithInlineImage(
                eq("birthday@example.test"), eq("¡Feliz Cumpleaños, Ana!"), any(),
                any(), eq("signature"), eq("image/png"));
    }

    @Test
    void excepciónDelAdaptadorNoEscapaDelExecutor() {
        IEmailService email = mock(IEmailService.class);
        when(email.sendEmailWithInlineImage(any(), any(), any(), any(), any(), any()))
                .thenThrow(new IllegalStateException("synthetic"));

        assertThatCode(() -> new EmailAsyncService(email).enviarMailCumple(alumno()))
                .doesNotThrowAnyException();
    }

    private static Alumno alumno() {
        Alumno alumno = new Alumno();
        alumno.setNombre("Ana");
        alumno.setEmail("birthday@example.test");
        return alumno;
    }
}
