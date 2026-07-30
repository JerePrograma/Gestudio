package gestudio.servicios.email;

import jakarta.mail.Address;
import jakarta.mail.MessagingException;
import jakarta.mail.Session;
import jakarta.mail.internet.InternetAddress;
import jakarta.mail.internet.MimeMessage;
import org.eclipse.angus.mail.smtp.SMTPAddressFailedException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.mockito.ArgumentCaptor;
import org.springframework.mail.MailAuthenticationException;
import org.springframework.mail.MailSendException;
import org.springframework.mail.javamail.JavaMailSender;

import java.util.Properties;
import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;

import io.micrometer.core.instrument.simple.SimpleMeterRegistry;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

class GmailSmtpEmailServiceTest {
    private JavaMailSender mailSender;
    private SentCopyStrategy sentCopy;

    @BeforeEach
    void setUp() {
        mailSender = mock(JavaMailSender.class);
        sentCopy = mock(SentCopyStrategy.class);
        when(mailSender.createMimeMessage()).thenAnswer(invocation ->
                new MimeMessage(Session.getInstance(new Properties())));
    }

    @Test
    void construyeMimeUtf8ConSenderConfiguradoHtmlInlineYAdjunto() throws Exception {
        GmailSmtpEmailService service = service(EmailDeliveryProperties.SentCopyMode.DISABLED);

        EmailDeliveryResult result = service.sendEmailWithAttachmentAndInlineImage(
                "recipient@example.test", "Recibo número á", "<p>Contenido á</p>",
                "pdf".getBytes(), "receipt.pdf", "application/pdf",
                "png".getBytes(), "signature", "image/png");

        assertThat(result.status()).isEqualTo(EmailDeliveryResult.Status.PROVIDER_ACCEPTED);
        ArgumentCaptor<MimeMessage> message = ArgumentCaptor.forClass(MimeMessage.class);
        verify(mailSender).send(message.capture());
        MimeMessage captured = message.getValue();
        assertThat(captured.getSubject()).isEqualTo("Recibo número á");
        assertThat(captured.getAllRecipients()).extracting(Address::toString)
                .containsExactly("recipient@example.test");
        assertThat(captured.getFrom()).extracting(Address::toString)
                .containsExactly("Gestudio <sender@example.test>");
        ByteArrayOutputStream wire = new ByteArrayOutputStream();
        captured.writeTo(wire);
        assertThat(wire.toString(StandardCharsets.ISO_8859_1))
                .contains("Content-Type: application/pdf", "filename=receipt.pdf",
                        "Content-ID: <signature>", "Content-Type: image/png");
        verifyNoInteractions(sentCopy);
    }

    @Test
    void gmailBloqueadoNoCreaMimeNiInvocaSender() {
        EmailDeliveryProperties blocked = EmailDeliveryPolicyTest.properties(true, false, true, true);
        GmailSmtpEmailService service = new GmailSmtpEmailService(blocked,
                new EmailDeliveryMetrics(new SimpleMeterRegistry()), mailSender,
                EmailDeliveryPolicyTest.policy(blocked, "prod"), sentCopy);

        assertThat(service.sendEmailWithInlineImage(
                "recipient@example.test", "Subject", "<p>Body</p>",
                new byte[]{1}, "signature", "image/png").status())
                .isEqualTo(EmailDeliveryResult.Status.BLOCKED_BY_DRY_RUN);
        verifyNoInteractions(mailSender, sentCopy);
    }

    @ParameterizedTest
    @ValueSource(ints = {421, 450})
    void clasificaErroresSmtpCuatroComoTransitorios(int code) throws Exception {
        doThrow(mailSend(code)).when(mailSender).send(any(MimeMessage.class));

        EmailDeliveryResult result = service(EmailDeliveryProperties.SentCopyMode.DISABLED)
                .sendEmailWithInlineImage("recipient@example.test", "Subject", "<p>Body</p>",
                        new byte[]{1}, "signature", "image/png");

        assertThat(result.status()).isEqualTo(EmailDeliveryResult.Status.PROVIDER_TEMPORARY_FAILURE);
        assertThat(result.reason()).isEqualTo("smtp_" + code);
    }

    @ParameterizedTest
    @ValueSource(ints = {535, 550})
    void clasificaErroresSmtpCincoComoRechazoPermanente(int code) throws Exception {
        doThrow(mailSend(code)).when(mailSender).send(any(MimeMessage.class));

        EmailDeliveryResult result = service(EmailDeliveryProperties.SentCopyMode.DISABLED)
                .sendEmailWithInlineImage("recipient@example.test", "Subject", "<p>Body</p>",
                        new byte[]{1}, "signature", "image/png");

        assertThat(result.status()).isEqualTo(EmailDeliveryResult.Status.PROVIDER_REJECTED);
    }

    @Test
    void autenticacionFallidaEsPermanenteYSanitizada() {
        doThrow(new MailAuthenticationException("synthetic secret must not be logged"))
                .when(mailSender).send(any(MimeMessage.class));

        EmailDeliveryResult result = service(EmailDeliveryProperties.SentCopyMode.DISABLED)
                .sendEmailWithInlineImage("recipient@example.test", "Subject", "<p>Body</p>",
                        new byte[]{1}, "signature", "image/png");

        assertThat(result.status()).isEqualTo(EmailDeliveryResult.Status.PROVIDER_PERMANENT_FAILURE);
        assertThat(result.reason()).isEqualTo("MailAuthenticationException");
    }

    @Test
    void falloDeTransporteSinCodigoSmtpEsTransitorio() {
        doThrow(new MailSendException("synthetic transport failure"))
                .when(mailSender).send(any(MimeMessage.class));

        EmailDeliveryResult result = service(EmailDeliveryProperties.SentCopyMode.DISABLED)
                .sendEmailWithInlineImage("recipient@example.test", "Subject", "<p>Body</p>",
                        new byte[]{1}, "signature", "image/png");

        assertThat(result.status()).isEqualTo(EmailDeliveryResult.Status.PROVIDER_TEMPORARY_FAILURE);
        assertThat(result.reason()).isEqualTo("MailSendException");
    }

    @Test
    void bestEffortExitosoAgregaCopiaSinReenviar() throws Exception {
        EmailDeliveryResult result = service(EmailDeliveryProperties.SentCopyMode.BEST_EFFORT)
                .sendEmailWithInlineImage("recipient@example.test", "Subject", "<p>Body</p>",
                        new byte[]{1}, "signature", "image/png");

        assertThat(result.status()).isEqualTo(EmailDeliveryResult.Status.PROVIDER_ACCEPTED);
        verify(mailSender, times(1)).send(any(MimeMessage.class));
        verify(sentCopy, times(1)).append(any(MimeMessage.class));
    }

    @Test
    void bestEffortFallidoMantieneSmtpAceptadoYNoReenvia() throws Exception {
        doThrow(new MessagingException("synthetic append failure"))
                .when(sentCopy).append(any(MimeMessage.class));

        EmailDeliveryResult result = service(EmailDeliveryProperties.SentCopyMode.BEST_EFFORT)
                .sendEmailWithInlineImage("recipient@example.test", "Subject", "<p>Body</p>",
                        new byte[]{1}, "signature", "image/png");

        assertThat(result.status()).isEqualTo(EmailDeliveryResult.Status.SENT_COPY_FAILED);
        assertThat(result.providerAccepted()).isTrue();
        assertThat(result.retryable()).isFalse();
        verify(mailSender, times(1)).send(any(MimeMessage.class));
        verify(sentCopy, times(1)).append(any(MimeMessage.class));
    }

    private GmailSmtpEmailService service(EmailDeliveryProperties.SentCopyMode sentCopyMode) {
        EmailDeliveryProperties base = EmailDeliveryPolicyTest.properties(true, false, false, true);
        EmailDeliveryProperties properties = new EmailDeliveryProperties(
                base.enabled(), base.provider(), base.dryRun(), base.realNetworkAllowed(), base.killSwitch(),
                base.fromAddress(), base.fromName(), sentCopyMode, base.fakeOutcome(), base.sentCopy());
        return new GmailSmtpEmailService(properties,
                new EmailDeliveryMetrics(new SimpleMeterRegistry()), mailSender,
                EmailDeliveryPolicyTest.policy(properties, "prod"), sentCopy);
    }

    private static MailSendException mailSend(int code) throws MessagingException {
        SMTPAddressFailedException failure = new SMTPAddressFailedException(
                new InternetAddress("recipient@example.test"), "RCPT TO", code, "synthetic");
        return new MailSendException("synthetic", failure);
    }
}
