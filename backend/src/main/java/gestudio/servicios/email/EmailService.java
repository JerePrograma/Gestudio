package gestudio.servicios.email;

import jakarta.mail.Folder;
import jakarta.mail.Message;
import jakarta.mail.MessagingException;
import jakarta.mail.Session;
import jakarta.mail.Store;
import jakarta.mail.internet.MimeMessage;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.core.io.ByteArrayResource;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.mail.javamail.MimeMessageHelper;
import org.springframework.stereotype.Service;

import java.util.Properties;

/**
 * Servicio de envío de emails que guarda cada mensaje en la carpeta "Sent" vía IMAPS.
 */
@Service
@Profile("prod")
public class EmailService implements IEmailService {

    private static final Logger log = LoggerFactory.getLogger(EmailService.class);

    private final JavaMailSender mailSender;

    @Value("${spring.mail.imap.host}")
    private String imapHost;

    @Value("${spring.mail.imap.port}")
    private int imapPort;

    @Value("${spring.mail.imap.username}")
    private String imapUsername;

    @Value("${spring.mail.imap.password}")
    private String imapPassword;

    @Value("${spring.mail.imap.properties.mail.imap.ssl.enable}")
    private boolean imapSslEnable;

    public EmailService(JavaMailSender mailSender) {
        this.mailSender = mailSender;
    }

    @Override
    public void sendEmailWithInlineImage(String from,
                                         String to,
                                         String subject,
                                         String htmlText,
                                         byte[] inlineData,
                                         String contentId,
                                         String inlineMimeType) throws MessagingException {
        MimeMessage message = mailSender.createMimeMessage();
        MimeMessageHelper helper = new MimeMessageHelper(message, true, "UTF-8");

        helper.setFrom(from);
        helper.setTo(to);
        helper.setSubject(subject);
        helper.setText(htmlText, true);
        helper.addInline(contentId, new ByteArrayResource(inlineData), inlineMimeType);

        // 1) Envío SMTP normal
        mailSender.send(message);
        // 2) Guardado en carpeta Sent vía IMAPS
        saveToSent(message);
    }

    @Override
    public void sendEmailWithAttachmentAndInlineImage(String from,
                                                      String to,
                                                      String subject,
                                                      String htmlText,
                                                      byte[] attachmentData,
                                                      String attachmentFilename,
                                                      byte[] inlineData,
                                                      String contentId,
                                                      String inlineMimeType) throws MessagingException {
        MimeMessage message = mailSender.createMimeMessage();
        MimeMessageHelper helper = new MimeMessageHelper(message, true, "UTF-8");

        helper.setFrom(from);
        helper.setTo(to);
        helper.setSubject(subject);
        helper.setText(htmlText, true);
        helper.addAttachment(attachmentFilename, new ByteArrayResource(attachmentData));
        helper.addInline(contentId, new ByteArrayResource(inlineData), inlineMimeType);

        // 1) Envío SMTP normal
        mailSender.send(message);
        // 2) Guardado en carpeta Sent vía IMAPS
        saveToSent(message);
    }

    @Value("${spring.mail.imap.sent-folder:INBOX.Sent}")
    private String sentFolderName;

    private void saveToSent(MimeMessage message) {
        Properties props = new Properties();
        props.put("mail.store.protocol", "imaps");
        props.put("mail.imaps.host", imapHost);
        props.put("mail.imaps.port", String.valueOf(imapPort));
        props.put("mail.imaps.ssl.enable", String.valueOf(imapSslEnable));

        try {
            Session session = Session.getInstance(props);
            try (Store store = session.getStore("imaps")) {
                store.connect(imapHost, imapUsername, imapPassword);

                // Usa el nombre exacto de tu carpeta:
                Folder sent = store.getFolder(sentFolderName);
                if (!sent.exists()) {
                    sent.create(Folder.HOLDS_MESSAGES);
                }
                sent.open(Folder.READ_WRITE);
                sent.appendMessages(new Message[]{message});
                sent.close(false);
            }
        } catch (MessagingException e) {
            log.error("[EmailService] No se pudo guardar el mensaje en '{}'", sentFolderName, e);
        }
    }
}
