package gestudio.servicios.email;

import gestudio.servicios.email.EmailAsyncService.BirthdayEmail;
import org.junit.jupiter.api.Test;

import java.util.UUID;

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

        new EmailAsyncService(email).enviarMailCumple(command());

        verify(email).sendEmailWithInlineImage(
                eq("birthday@example.test"), eq("¡Feliz Cumpleaños, Ana!"), any(),
                any(), eq("signature"), eq("image/png"));
    }

    @Test
    void excepciónDelAdaptadorNoEscapaDelExecutor() {
        IEmailService email = mock(IEmailService.class);
        when(email.sendEmailWithInlineImage(any(), any(), any(), any(), any(), any()))
                .thenThrow(new IllegalStateException("synthetic"));

        assertThatCode(() -> new EmailAsyncService(email).enviarMailCumple(command()))
                .doesNotThrowAnyException();
    }

    private static BirthdayEmail command() {
        return new BirthdayEmail(
                UUID.fromString("10000000-0000-0000-0000-000000000001"),
                "birthday@example.test", "Ana");
    }
}
