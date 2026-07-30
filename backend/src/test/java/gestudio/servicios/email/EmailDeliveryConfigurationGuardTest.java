package gestudio.servicios.email;

import org.junit.jupiter.api.Test;
import org.springframework.boot.autoconfigure.mail.MailProperties;
import org.springframework.boot.env.YamlPropertySourceLoader;
import org.springframework.core.env.PropertySource;
import org.springframework.core.io.ClassPathResource;

import java.io.IOException;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class EmailDeliveryConfigurationGuardTest {

    @Test
    void noopYGmailBloqueadoInicianSinCredenciales() {
        EmailDeliveryProperties noop = EmailServicesTest.properties(
                EmailDeliveryProperties.Provider.NOOP, EmailDeliveryProperties.FakeOutcome.SUCCESS);
        EmailDeliveryProperties blocked = EmailDeliveryPolicyTest.properties(true, true, false, true);

        assertThatCode(() -> guard(noop, new MailProperties())).doesNotThrowAnyException();
        assertThatCode(() -> guard(blocked, new MailProperties())).doesNotThrowAnyException();
    }

    @Test
    void gmailRealSinSecretoFallaCerradoSinFiltrarValores() {
        EmailDeliveryProperties real = EmailDeliveryPolicyTest.properties(true, false, false, true);
        MailProperties mail = validMail();
        mail.setPassword("");

        assertThatThrownBy(() -> guard(real, mail))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("incompleta o es inválida")
                .hasMessageNotContaining("sender@example.test")
                .hasMessageNotContaining("synthetic-app-password");
    }

    @Test
    void gmailRealExigeSenderPropioTlsYTimeouts() {
        EmailDeliveryProperties real = EmailDeliveryPolicyTest.properties(true, false, false, true);
        assertThatCode(() -> guard(real, validMail())).doesNotThrowAnyException();

        MailProperties arbitrarySender = validMail();
        arbitrarySender.setUsername("other@example.test");
        assertThatThrownBy(() -> guard(real, arbitrarySender)).isInstanceOf(IllegalStateException.class);

        MailProperties noTimeout = validMail();
        noTimeout.getProperties().put("mail.smtp.timeout", "0");
        assertThatThrownBy(() -> guard(real, noTimeout))
                .isInstanceOf(IllegalStateException.class).hasMessageContaining("TLS");
    }

    @Test
    void sentCopyRequiredSeRechazaSinSimularAtomicidad() {
        EmailDeliveryProperties base = EmailDeliveryPolicyTest.properties(true, false, false, true);
        EmailDeliveryProperties required = new EmailDeliveryProperties(
                base.enabled(), base.provider(), base.dryRun(), base.realNetworkAllowed(), base.killSwitch(),
                base.fromAddress(), base.fromName(), EmailDeliveryProperties.SentCopyMode.REQUIRED,
                base.fakeOutcome(), base.sentCopy());

        assertThatThrownBy(() -> guard(required, validMail()))
                .isInstanceOf(IllegalStateException.class).hasMessageContaining("no son atómicos");
    }

    @Test
    void configuracionBaseFijaTlsYTimeoutsSinHostReal() throws IOException {
        List<PropertySource<?>> sources = new YamlPropertySourceLoader().load(
                "application", new ClassPathResource("application.yml"));
        PropertySource<?> source = sources.getFirst();

        assertThat(source.getProperty("spring.mail.host")).isEqualTo("${APP_EMAIL_GMAIL_HOST:}");
        assertThat(source.getProperty("spring.mail.properties.mail.smtp.auth")).isEqualTo(true);
        assertThat(source.getProperty("spring.mail.properties.mail.smtp.starttls.enable")).isEqualTo(true);
        assertThat(source.getProperty("spring.mail.properties.mail.smtp.starttls.required")).isEqualTo(true);
        assertThat(source.getProperty("spring.mail.properties.mail.smtp.connectiontimeout"))
                .isEqualTo("${APP_EMAIL_SMTP_CONNECTION_TIMEOUT_MS:5000}");
        assertThat(source.getProperty("spring.mail.properties.mail.smtp.timeout"))
                .isEqualTo("${APP_EMAIL_SMTP_READ_TIMEOUT_MS:5000}");
        assertThat(source.getProperty("spring.mail.properties.mail.smtp.writetimeout"))
                .isEqualTo("${APP_EMAIL_SMTP_WRITE_TIMEOUT_MS:5000}");
    }

    private static EmailDeliveryConfigurationGuard guard(EmailDeliveryProperties properties,
                                                         MailProperties mail) {
        return new EmailDeliveryConfigurationGuard(properties, mail,
                EmailDeliveryPolicyTest.policy(properties, "prod"));
    }

    static MailProperties validMail() {
        MailProperties mail = new MailProperties();
        mail.setHost("smtp.example.test");
        mail.setPort(587);
        mail.setUsername("sender@example.test");
        mail.setPassword("synthetic-app-password");
        mail.getProperties().put("mail.smtp.auth", "true");
        mail.getProperties().put("mail.smtp.starttls.enable", "true");
        mail.getProperties().put("mail.smtp.starttls.required", "true");
        mail.getProperties().put("mail.smtp.connectiontimeout", "5000");
        mail.getProperties().put("mail.smtp.timeout", "5000");
        mail.getProperties().put("mail.smtp.writetimeout", "5000");
        return mail;
    }
}
