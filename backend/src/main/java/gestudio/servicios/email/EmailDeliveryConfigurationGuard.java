package gestudio.servicios.email;

import org.springframework.boot.autoconfigure.mail.MailProperties;
import org.springframework.stereotype.Component;

import java.util.Map;

@Component
public class EmailDeliveryConfigurationGuard {
    private final EmailDeliveryProperties email;
    private final MailProperties mail;

    public EmailDeliveryConfigurationGuard(EmailDeliveryProperties email,
                                           MailProperties mail,
                                           EmailDeliveryPolicy policy) {
        this.email = email;
        this.mail = mail;
        if (email.provider() != EmailDeliveryProperties.Provider.GMAIL_SMTP) return;
        if (email.sentCopyMode() == EmailDeliveryProperties.SentCopyMode.REQUIRED) {
            throw new IllegalStateException("APP_EMAIL_SENT_COPY_MODE=REQUIRED no es seguro: SMTP e IMAP no son atómicos");
        }
        if (policy.gmailBlock().isPresent()) return;
        validateSmtp();
        if (email.sentCopyMode() == EmailDeliveryProperties.SentCopyMode.BEST_EFFORT) validateSentCopy();
    }

    private void validateSmtp() {
        if (blank(mail.getHost()) || mail.getPort() == null || mail.getPort() < 1 || mail.getPort() > 65535
                || !AbstractEmailService.validAddress(mail.getUsername()) || blank(mail.getPassword())
                || !AbstractEmailService.validAddress(email.fromAddress())
                || !email.fromAddress().equalsIgnoreCase(mail.getUsername())
                || invalidName(email.fromName())) {
            throw new IllegalStateException("La configuración Gmail SMTP habilitada está incompleta o es inválida");
        }
        Map<String, String> properties = mail.getProperties();
        if (!"true".equalsIgnoreCase(properties.get("mail.smtp.auth"))
                || !"true".equalsIgnoreCase(properties.get("mail.smtp.starttls.enable"))
                || !"true".equalsIgnoreCase(properties.get("mail.smtp.starttls.required"))
                || !positive(properties.get("mail.smtp.connectiontimeout"))
                || !positive(properties.get("mail.smtp.timeout"))
                || !positive(properties.get("mail.smtp.writetimeout"))) {
            throw new IllegalStateException("La configuración Gmail SMTP habilitada exige TLS, autenticación y timeouts explícitos");
        }
    }

    private void validateSentCopy() {
        EmailDeliveryProperties.SentCopy copy = email.sentCopy();
        if (blank(copy.host()) || copy.port() < 1 || copy.port() > 65535
                || !AbstractEmailService.validAddress(copy.username()) || blank(copy.appPassword())
                || blank(copy.folder()) || copy.connectionTimeoutMs() <= 0 || copy.readTimeoutMs() <= 0) {
            throw new IllegalStateException("La copia Sent BEST_EFFORT está incompleta o es inválida");
        }
    }

    private static boolean invalidName(String value) {
        return blank(value) || value.length() > 100 || value.indexOf('\r') >= 0 || value.indexOf('\n') >= 0;
    }

    private static boolean positive(String value) {
        try {
            return Integer.parseInt(value) > 0;
        } catch (NumberFormatException exception) {
            return false;
        }
    }

    private static boolean blank(String value) {
        return value == null || value.isBlank();
    }
}
