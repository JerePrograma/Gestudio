package gestudio.servicios.email;

import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.read.ListAppender;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.Test;
import org.slf4j.LoggerFactory;

import static org.assertj.core.api.Assertions.assertThat;

class EmailServicesTest {

    @Test
    void noopEsPredeterminadoControladoYValidaAntesDeOmitir() {
        SimpleMeterRegistry registry = new SimpleMeterRegistry();
        NoOpEmailService service = new NoOpEmailService(
                properties(EmailDeliveryProperties.Provider.NOOP, EmailDeliveryProperties.FakeOutcome.SUCCESS),
                new EmailDeliveryMetrics(registry));

        EmailDeliveryResult result = service.sendEmailWithInlineImage(
                "recipient@example.test", "Subject", "<p>Body</p>",
                new byte[]{1}, "signature", "image/png");
        EmailDeliveryResult invalid = service.sendEmailWithInlineImage(
                "recipient@example.test", "Subject\r\nBcc: injected@example.test", "<p>Body</p>",
                new byte[]{1}, "signature", "image/png");

        assertThat(result.status()).isEqualTo(EmailDeliveryResult.Status.NOOP);
        assertThat(invalid.status()).isEqualTo(EmailDeliveryResult.Status.INVALID_MESSAGE);
        assertThat(registry.get("gestudio.email.attempts").counters())
                .extracting(counter -> counter.count()).containsOnly(1.0d);
        assertThat(registry.get("gestudio.email.blocked").counter().count()).isEqualTo(1.0d);
    }

    @Test
    void fakeEsDeterministaParaExitoFalloTransitorioYPermanente() {
        assertFake(EmailDeliveryProperties.FakeOutcome.SUCCESS, EmailDeliveryResult.Status.SIMULATED);
        assertFake(EmailDeliveryProperties.FakeOutcome.TEMPORARY_FAILURE,
                EmailDeliveryResult.Status.PROVIDER_TEMPORARY_FAILURE);
        assertFake(EmailDeliveryProperties.FakeOutcome.PERMANENT_FAILURE,
                EmailDeliveryResult.Status.PROVIDER_PERMANENT_FAILURE);
    }

    @Test
    void rechazaDestinatarioAdjuntoMimeYContenidoFueraDeContrato() {
        NoOpEmailService service = new NoOpEmailService(
                properties(EmailDeliveryProperties.Provider.NOOP, EmailDeliveryProperties.FakeOutcome.SUCCESS),
                new EmailDeliveryMetrics(new SimpleMeterRegistry()));

        assertThat(service.sendEmailWithInlineImage(
                "Name <recipient@example.test>", "Subject", "<p>Body</p>",
                new byte[]{1}, "signature", "image/png").status())
                .isEqualTo(EmailDeliveryResult.Status.INVALID_MESSAGE);
        assertThat(service.sendEmailWithAttachmentAndInlineImage(
                "recipient@example.test", "Subject", "<p>Body</p>",
                new byte[]{1}, "../receipt.pdf", "application/pdf",
                new byte[]{1}, "signature", "image/png").status())
                .isEqualTo(EmailDeliveryResult.Status.INVALID_MESSAGE);
        assertThat(service.sendEmailWithAttachmentAndInlineImage(
                "recipient@example.test", "Subject", "<p>Body</p>",
                new byte[]{1}, "receipt.pdf", "invalid",
                new byte[]{1}, "signature", "image/png").status())
                .isEqualTo(EmailDeliveryResult.Status.INVALID_MESSAGE);
    }

    @Test
    void logsYMetricasNoIncluyenDestinatarioAsuntoNiCuerpo() {
        Logger logger = (Logger) LoggerFactory.getLogger(AbstractEmailService.class);
        ListAppender<ILoggingEvent> appender = new ListAppender<>();
        appender.start();
        logger.addAppender(appender);
        try {
            FakeEmailService service = new FakeEmailService(
                    properties(EmailDeliveryProperties.Provider.FAKE, EmailDeliveryProperties.FakeOutcome.SUCCESS),
                    new EmailDeliveryMetrics(new SimpleMeterRegistry()));
            service.sendEmailWithInlineImage(
                    "private-recipient@example.test", "Private subject", "<p>Private body</p>",
                    new byte[]{1}, "signature", "image/png");

            String logs = appender.list.stream().map(ILoggingEvent::getFormattedMessage)
                    .reduce("", (left, right) -> left + right);
            assertThat(logs).contains("provider=FAKE", "result=SIMULATED", "messageType=BIRTHDAY")
                    .doesNotContain("private-recipient", "Private subject", "Private body");
        } finally {
            logger.detachAppender(appender);
        }
    }

    private static void assertFake(EmailDeliveryProperties.FakeOutcome outcome,
                                   EmailDeliveryResult.Status expected) {
        SimpleMeterRegistry registry = new SimpleMeterRegistry();
        FakeEmailService service = new FakeEmailService(
                properties(EmailDeliveryProperties.Provider.FAKE, outcome),
                new EmailDeliveryMetrics(registry));
        EmailDeliveryResult result = service.sendEmailWithInlineImage(
                "recipient@example.test", "Subject", "<p>Body</p>",
                new byte[]{1}, "signature", "image/png");

        assertThat(result.status()).isEqualTo(expected);
        assertThat(service.lastSanitizedResult()).isEqualTo(result);
        assertThat(result.reason()).doesNotContain("recipient@example.test", "Subject", "Body");
    }

    static EmailDeliveryProperties properties(EmailDeliveryProperties.Provider provider,
                                              EmailDeliveryProperties.FakeOutcome fakeOutcome) {
        return new EmailDeliveryProperties(false, provider, true, false, true,
                "", "Gestudio", EmailDeliveryProperties.SentCopyMode.DISABLED, fakeOutcome,
                new EmailDeliveryProperties.SentCopy("", 993, "", "", "", 5000, 5000));
    }
}
