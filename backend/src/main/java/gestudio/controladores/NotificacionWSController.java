package gestudio.controladores;

import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.messaging.handler.annotation.SendTo;
import org.springframework.stereotype.Controller;

@Controller
public class NotificacionWSController {

    /**
     * Metodo para recibir mensajes desde el cliente. Por ejemplo, al marcar una notificacion como leida.
     */
    @MessageMapping("/notificacion/marcarLeida")
    @SendTo("/topic/notificaciones")
    public String marcarNotificacionLeida(String notificacionId) {
        // Aqui se implementaria la logica para actualizar la notificacion en la BD.
        // Luego se podria devolver una confirmacion o actualizar el listado.
        return "Notificacion " + notificacionId + " marcada como leida.";
    }
}
