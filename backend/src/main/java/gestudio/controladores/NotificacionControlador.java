package gestudio.controladores;

import jakarta.mail.MessagingException;
import gestudio.servicios.notificaciones.NotificacionService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.*;

import java.io.IOException;
import java.util.List;

@RestController
@RequestMapping("/api/notificaciones")
@Validated
public class NotificacionControlador {

    private final NotificacionService notificacionService;

    @Autowired
    public NotificacionControlador(NotificacionService notificacionService) {
        this.notificacionService = notificacionService;
    }

    /**
     * Endpoint para obtener las notificaciones de cumpleaños del dia (u otros tipos si se desean).
     */
    @GetMapping("/cumpleaneros")
    public ResponseEntity<List<String>> obtenerCumpleanerosDelDia() throws MessagingException, IOException {
        List<String> notificaciones = notificacionService.generarYObtenerCumpleanerosDelDia();
        return ResponseEntity.ok(notificaciones);
    }
}

