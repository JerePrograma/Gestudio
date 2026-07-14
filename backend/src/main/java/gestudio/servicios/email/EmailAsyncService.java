package gestudio.servicios.email;

import gestudio.entidades.Alumno;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;

// 1) Un nuevo bean dedicado al envío asíncrono
@Service
public class EmailAsyncService {

    private final IEmailService emailService;
    private static final Logger log = LoggerFactory.getLogger(EmailAsyncService.class);

    public EmailAsyncService(IEmailService emailService) {
        this.emailService = emailService;
    }

    @Async("taskExecutor")
    public void enviarMailCumple(Alumno alumno, byte[] firmaBytes) {
        try {
            String subject = "¡Feliz Cumpleaños, " + alumno.getNombre() + "!";
            String htmlBody =
                    "<p>FELICIDADES <strong>" + alumno.getNombre() + "</strong></p>"
                            + "<p>De parte de todo el Staff de Gestudio arte escuela, te deseamos un "
                            + "<strong>MUY FELIZ CUMPLEAÑOS!</strong></p>"
                            + "<p>Katia, Anto y Nati te desean un nuevo año lleno de deseos por cumplir!</p>"
                            + "<p>Te adoramos.</p>"
                            + "<img src='cid:signature' alt='Firma' style='max-width:200px;'/>";
            emailService.sendEmailWithInlineImage(
                    "administracion@gestudio.com.ar",
                    alumno.getEmail(),
                    subject,
                    htmlBody,
                    firmaBytes,
                    "signature",
                    "image/png"
            );
        } catch (Exception ex) {
            // logueá el error y seguí
            log.warn("Falló el email de cumpleaños alumnoId={} type={}", alumno.getId(), ex.getClass().getSimpleName());
        }
    }
}
