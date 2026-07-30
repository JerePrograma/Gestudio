package gestudio.servicios.email;

import jakarta.mail.MessagingException;
import jakarta.mail.internet.InternetAddress;
import jakarta.mail.internet.MimeMessage;
import org.eclipse.angus.mail.smtp.SMTPAddressFailedException;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.core.io.ByteArrayResource;
import org.springframework.mail.MailAuthenticationException;
import org.springframework.mail.MailException;
import org.springframework.mail.MailSendException;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.mail.javamail.MimeMessageHelper;
import org.springframework.stereotype.Service;

import java.io.UnsupportedEncodingException;
import java.nio.charset.StandardCharsets;

@Service
@ConditionalOnProperty(prefix = "app.email", name = "provider", havingValue = "GMAIL_SMTP")
public class GmailSmtpEmailService extends AbstractEmailService {
    private final JavaMailSender mailSender;
    private final EmailDeliveryPolicy policy;
    private final SentCopyStrategy sentCopy;

    public GmailSmtpEmailService(EmailDeliveryProperties properties,
                                 EmailDeliveryMetrics metrics,
                                 JavaMailSender mailSender,
                                 EmailDeliveryPolicy policy,
                                 SentCopyStrategy sentCopy) {
        super(properties, metrics);
        this.mailSender = mailSender;
        this.policy = policy;
        this.sentCopy = sentCopy;
    }

    @Override
    protected EmailDeliveryResult deliverValidated(EmailMessage email) {
        EmailDeliveryResult blocked = policy.gmailBlock().orElse(null);
        if (blocked != null) return blocked;

        MimeMessage message;
        try {
            message = createMessage(email);
            mailSender.send(message);
        } catch (MailAuthenticationException exception) {
            return EmailDeliveryResult.of(EmailDeliveryResult.Status.PROVIDER_PERMANENT_FAILURE,
                    exception.getClass().getSimpleName());
        } catch (MailSendException exception) {
            int code = smtpCode(exception);
            return EmailDeliveryResult.of(code < 0 || code >= 400 && code < 500
                            ? EmailDeliveryResult.Status.PROVIDER_TEMPORARY_FAILURE
                            : EmailDeliveryResult.Status.PROVIDER_REJECTED,
                    code > 0 ? "smtp_" + code : exception.getClass().getSimpleName());
        } catch (MailException exception) {
            return EmailDeliveryResult.of(EmailDeliveryResult.Status.PROVIDER_TEMPORARY_FAILURE,
                    exception.getClass().getSimpleName());
        } catch (MessagingException | UnsupportedEncodingException exception) {
            return EmailDeliveryResult.of(EmailDeliveryResult.Status.INVALID_MESSAGE,
                    exception.getClass().getSimpleName());
        }

        if (properties().sentCopyMode() == EmailDeliveryProperties.SentCopyMode.BEST_EFFORT) {
            try {
                sentCopy.append(message);
            } catch (MessagingException exception) {
                return EmailDeliveryResult.of(EmailDeliveryResult.Status.SENT_COPY_FAILED,
                        exception.getClass().getSimpleName());
            }
        }
        return EmailDeliveryResult.of(EmailDeliveryResult.Status.PROVIDER_ACCEPTED);
    }

    private MimeMessage createMessage(EmailMessage email)
            throws MessagingException, UnsupportedEncodingException {
        MimeMessage message = mailSender.createMimeMessage();
        MimeMessageHelper helper = new MimeMessageHelper(message, true, StandardCharsets.UTF_8.name());
        helper.setFrom(new InternetAddress(properties().fromAddress(), properties().fromName(),
                StandardCharsets.UTF_8.name()));
        helper.setTo(email.to());
        helper.setSubject(email.subject());
        helper.setText(email.htmlText(), true);
        if (email.attachmentData() != null) {
            helper.addAttachment(email.attachmentFilename(), new ByteArrayResource(email.attachmentData()),
                    email.attachmentMimeType());
        }
        helper.addInline(email.contentId(), new ByteArrayResource(email.inlineData()), email.inlineMimeType());
        return message;
    }

    private static int smtpCode(Throwable failure) {
        Throwable current = failure;
        for (int depth = 0; current != null && depth < 12; depth++) {
            if (current instanceof SMTPAddressFailedException smtp) return smtp.getReturnCode();
            if (current instanceof MessagingException messaging && messaging.getNextException() != null) {
                current = messaging.getNextException();
            } else {
                current = current.getCause();
            }
        }
        return -1;
    }
}
