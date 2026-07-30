package gestudio.servicios.email;

import gestudio.entidades.Alumno;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.web.util.HtmlUtils;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;

import java.io.IOException;
import java.io.InputStream;

@Service
public class EmailAsyncService {

    private final IEmailService emailService;
    private static final Logger log = LoggerFactory.getLogger(EmailAsyncService.class);

    public EmailAsyncService(IEmailService emailService) {
        this.emailService = emailService;
    }

    @Async("taskExecutor")
    public void enviarMailCumple(Alumno alumno) {
        try {
            String subject = "¡Feliz Cumpleaños, " + alumno.getNombre() + "!";
            String nombre = HtmlUtils.htmlEscape(alumno.getNombre());
            String htmlBody =
                    "<p>FELICIDADES <strong>" + nombre + "</strong></p>"
                            + "<p>De parte de todo el Staff de Gestudio arte escuela, te deseamos un "
                            + "<strong>MUY FELIZ CUMPLEAÑOS!</strong></p>"
                            + "<p>Katia, Anto y Nati te desean un nuevo año lleno de deseos por cumplir!</p>"
                            + "<p>Te adoramos.</p>"
                            + "<img src='cid:signature' alt='Firma' style='max-width:200px;'/>";
            EmailDeliveryResult result = emailService.sendEmailWithInlineImage(
                    alumno.getEmail(),
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

    private byte[] firma() throws IOException {
        try (InputStream entrada = getClass().getResourceAsStream("/firma_mesa-de-trabajo-1.png")) {
            if (entrada == null) throw new IOException("Firma no disponible");
            return entrada.readAllBytes();
        }
    }
}
