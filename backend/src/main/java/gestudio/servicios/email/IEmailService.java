package gestudio.servicios.email;

import jakarta.mail.MessagingException;

// interfaz común (opcional, pero recomendable)
public interface IEmailService {
    void sendEmailWithInlineImage(String from,
                                  String to,
                                  String subject,
                                  String htmlText,
                                  byte[] inlineData,
                                  String contentId,
                                  String inlineMimeType) throws MessagingException;
    void sendEmailWithAttachmentAndInlineImage(String from,
                                               String to,
                                               String subject,
                                               String htmlText,
                                               byte[] attachmentData,
                                               String attachmentFilename,
                                               byte[] inlineData,
                                               String contentId,
                                               String inlineMimeType) throws MessagingException;
}
