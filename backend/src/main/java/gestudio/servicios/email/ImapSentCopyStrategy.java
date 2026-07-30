package gestudio.servicios.email;

import jakarta.mail.Folder;
import jakarta.mail.Message;
import jakarta.mail.MessagingException;
import jakarta.mail.Session;
import jakarta.mail.Store;
import jakarta.mail.internet.MimeMessage;
import org.springframework.stereotype.Component;

import java.util.Properties;

@Component
public class ImapSentCopyStrategy implements SentCopyStrategy {
    private final EmailDeliveryProperties properties;

    public ImapSentCopyStrategy(EmailDeliveryProperties properties) {
        this.properties = properties;
    }

    @Override
    public void append(MimeMessage message) throws MessagingException {
        EmailDeliveryProperties.SentCopy sentCopy = properties.sentCopy();
        Properties sessionProperties = new Properties();
        sessionProperties.setProperty("mail.store.protocol", "imaps");
        sessionProperties.setProperty("mail.imaps.ssl.enable", "true");
        sessionProperties.setProperty("mail.imaps.connectiontimeout", String.valueOf(sentCopy.connectionTimeoutMs()));
        sessionProperties.setProperty("mail.imaps.timeout", String.valueOf(sentCopy.readTimeoutMs()));

        Folder folder = null;
        try (Store store = Session.getInstance(sessionProperties).getStore("imaps")) {
            store.connect(sentCopy.host(), sentCopy.port(), sentCopy.username(), sentCopy.appPassword());
            folder = store.getFolder(sentCopy.folder());
            if (!folder.exists()) folder.create(Folder.HOLDS_MESSAGES);
            folder.open(Folder.READ_WRITE);
            folder.appendMessages(new Message[]{message});
        } finally {
            if (folder != null && folder.isOpen()) folder.close(false);
        }
    }
}
