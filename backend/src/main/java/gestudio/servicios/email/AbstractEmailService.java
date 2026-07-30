package gestudio.servicios.email;

import jakarta.mail.internet.AddressException;
import jakarta.mail.internet.InternetAddress;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.nio.charset.StandardCharsets;
import java.util.regex.Pattern;

abstract class AbstractEmailService implements IEmailService {
    private static final Logger log = LoggerFactory.getLogger(AbstractEmailService.class);
    private static final int MAX_SUBJECT_CHARACTERS = 200;
    private static final int MAX_HTML_BYTES = 256_000;
    private static final int MAX_INLINE_BYTES = 2_000_000;
    private static final int MAX_ATTACHMENT_BYTES = 10_000_000;
    private static final int MAX_FILENAME_CHARACTERS = 128;
    private static final Pattern MIME_TYPE = Pattern.compile("[A-Za-z0-9!#$&^_.+-]+/[A-Za-z0-9!#$&^_.+-]+");
    private static final Pattern CONTENT_ID = Pattern.compile("[A-Za-z0-9._-]{1,100}");

    private final EmailDeliveryProperties properties;
    private final EmailDeliveryMetrics metrics;

    protected AbstractEmailService(EmailDeliveryProperties properties, EmailDeliveryMetrics metrics) {
        this.properties = properties;
        this.metrics = metrics;
    }

    protected final EmailDeliveryProperties properties() {
        return properties;
    }

    @Override
    public final EmailDeliveryResult sendEmailWithInlineImage(String to,
                                                              String subject,
                                                              String htmlText,
                                                              byte[] inlineData,
                                                              String contentId,
                                                              String inlineMimeType) {
        return deliver(new EmailMessage("BIRTHDAY", to, subject, htmlText,
                null, null, null, inlineData, contentId, inlineMimeType));
    }

    @Override
    public final EmailDeliveryResult sendEmailWithAttachmentAndInlineImage(String to,
                                                                           String subject,
                                                                           String htmlText,
                                                                           byte[] attachmentData,
                                                                           String attachmentFilename,
                                                                           String attachmentMimeType,
                                                                           byte[] inlineData,
                                                                           String contentId,
                                                                           String inlineMimeType) {
        return deliver(new EmailMessage("RECEIPT", to, subject, htmlText,
                attachmentData, attachmentFilename, attachmentMimeType,
                inlineData, contentId, inlineMimeType));
    }

    protected abstract EmailDeliveryResult deliverValidated(EmailMessage message);

    private EmailDeliveryResult deliver(EmailMessage message) {
        String validation = validate(message);
        EmailDeliveryResult result = validation == null
                ? deliverValidated(message)
                : EmailDeliveryResult.of(EmailDeliveryResult.Status.INVALID_MESSAGE, validation);
        metrics.record(properties.provider(), result, message.messageType());
        log.info("email_delivery provider={} result={} messageType={} cause={}",
                properties.provider(), result.status(), message.messageType(),
                result.reason().isBlank() ? "none" : result.reason());
        return result;
    }

    private static String validate(EmailMessage message) {
        if (!validAddress(message.to())) return "invalid_recipient";
        if (!validHeader(message.subject(), MAX_SUBJECT_CHARACTERS)) return "invalid_subject";
        if (message.htmlText() == null || message.htmlText().isBlank()
                || message.htmlText().getBytes(StandardCharsets.UTF_8).length > MAX_HTML_BYTES) {
            return "invalid_html";
        }
        if (!validBytes(message.inlineData(), MAX_INLINE_BYTES)
                || !CONTENT_ID.matcher(nullToEmpty(message.contentId())).matches()
                || !validMime(message.inlineMimeType())) {
            return "invalid_inline";
        }
        if (message.attachmentData() != null
                && (!validBytes(message.attachmentData(), MAX_ATTACHMENT_BYTES)
                || !validFilename(message.attachmentFilename())
                || !validMime(message.attachmentMimeType()))) {
            return "invalid_attachment";
        }
        return null;
    }

    static boolean validAddress(String value) {
        if (value == null || value.isBlank() || value.length() > 320 || containsLineBreak(value)) return false;
        try {
            InternetAddress[] parsed = InternetAddress.parse(value, true);
            return parsed.length == 1
                    && parsed[0].getPersonal() == null
                    && value.equals(parsed[0].getAddress());
        } catch (AddressException exception) {
            return false;
        }
    }

    private static boolean validHeader(String value, int maxCharacters) {
        return value != null && !value.isBlank() && value.length() <= maxCharacters && !containsLineBreak(value);
    }

    private static boolean validBytes(byte[] value, int maxBytes) {
        return value != null && value.length > 0 && value.length <= maxBytes;
    }

    private static boolean validFilename(String value) {
        if (value == null || value.isBlank() || value.length() > MAX_FILENAME_CHARACTERS
                || value.equals(".") || value.equals("..") || value.contains("/") || value.contains("\\")) {
            return false;
        }
        return value.chars().noneMatch(character -> Character.isISOControl(character));
    }

    private static boolean validMime(String value) {
        return value != null && value.length() <= 100 && MIME_TYPE.matcher(value).matches();
    }

    private static boolean containsLineBreak(String value) {
        return value.indexOf('\r') >= 0 || value.indexOf('\n') >= 0;
    }

    private static String nullToEmpty(String value) {
        return value == null ? "" : value;
    }
}

record EmailMessage(
        String messageType,
        String to,
        String subject,
        String htmlText,
        byte[] attachmentData,
        String attachmentFilename,
        String attachmentMimeType,
        byte[] inlineData,
        String contentId,
        String inlineMimeType
) {
}
