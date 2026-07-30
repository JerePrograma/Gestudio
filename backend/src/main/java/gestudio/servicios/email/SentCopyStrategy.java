package gestudio.servicios.email;

import jakarta.mail.MessagingException;
import jakarta.mail.internet.MimeMessage;

public interface SentCopyStrategy {
    void append(MimeMessage message) throws MessagingException;
}
