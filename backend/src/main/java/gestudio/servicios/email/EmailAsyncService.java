package gestudio.servicios.email;

import gestudio.tenancy.TenantContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.web.util.HtmlUtils;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;

import java.io.IOException;
import java.io.InputStream;
import java.util.UUID;

@Service
public class EmailAsyncService {

    private final IEmailService emailService;
    private static final Logger log = LoggerFactory.getLogger(EmailAsyncService.class);

    public EmailAsyncService(IEmailService emailService) {
        this.emailService = emailService;
    }

    @Async("taskExecutor")
    public void enviarMailCumple(BirthdayEmail command) {
        try (TenantContext.Scope ignored = TenantContext.open(command.tenantId(), null)) {
            String subject = "¡Feliz Cumpleaños, " + command.nombre() + "!";
            String nombre = HtmlUtils.htmlEscape(command.nombre());
            String htmlBody =
                    "<p>FELICIDADES <strong>" + nombre + "</strong></p>"
                            + "<p>De parte de todo el Staff de Gestudio arte escuela, te deseamos un "
                            + "<strong>MUY FELIZ CUMPLEAÑOS!</strong></p>"
                            + "<p>Katia, Anto y Nati te desean un nuevo año lleno de deseos por cumplir!</p>"
                            + "<p>Te adoramos.</p>"
                            + "<img src='cid:signature' alt='Firma' style='max-width:200px;'/>";
            EmailDeliveryResult result = emailService.sendEmailWithInlineImage(
                    command.destinatario(),
                    subject,
                    htmlBody,
                    firma(),
                    "signature",
                    "image/png"
            );
            log.info("birthday_email result={}", result.status());
        } catch (Exception ex) {
            log.warn("birthday_email result=UNEXPECTED_FAILURE cause={}", ex.getClass().getSimpleName());
        }
    }

    public record BirthdayEmail(UUID tenantId, String destinatario, String nombre) {
        public BirthdayEmail {
            if (tenantId == null || destinatario == null || destinatario.isBlank()
                    || nombre == null || nombre.isBlank()) {
                throw new IllegalArgumentException("Birthday email command incompleto");
            }
        }
    }

    private byte[] firma() throws IOException {
        try (InputStream entrada = getClass().getResourceAsStream("/firma_mesa-de-trabajo-1.png")) {
            if (entrada == null) throw new IOException("Firma no disponible");
            return entrada.readAllBytes();
        }
    }
}
