package gestudio.servicios.email;

public interface IEmailService {
    EmailDeliveryResult sendEmailWithInlineImage(String to,
                                                 String subject,
                                                 String htmlText,
                                                 byte[] inlineData,
                                                 String contentId,
                                                 String inlineMimeType);

    EmailDeliveryResult sendEmailWithAttachmentAndInlineImage(String to,
                                                              String subject,
                                                              String htmlText,
                                                              byte[] attachmentData,
                                                              String attachmentFilename,
                                                              String attachmentMimeType,
                                                              byte[] inlineData,
                                                              String contentId,
                                                              String inlineMimeType);
}
