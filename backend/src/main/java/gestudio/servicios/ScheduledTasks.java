package gestudio.servicios;

import gestudio.servicios.asistencia.AsistenciaMensualServicio;
import gestudio.servicios.matricula.MatriculaServicio;
import gestudio.servicios.mensualidad.MensualidadServicio;
import gestudio.servicios.notificaciones.NotificacionService;
import gestudio.servicios.recargo.RecargoServicio;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.util.List;

@Component
@ConditionalOnProperty(name = "app.scheduling-enabled", havingValue = "true")
public class ScheduledTasks {

    private static final Logger log = LoggerFactory.getLogger(ScheduledTasks.class);

    private final MensualidadServicio mensualidadServicio;
    private final MatriculaServicio matriculaServicio;
    private final RecargoServicio recargoServicio;
    private final AsistenciaMensualServicio asistenciaMensualServicio;
    private final NotificacionService notificacionService;

    public ScheduledTasks(MensualidadServicio mensualidadServicio,
                          MatriculaServicio matriculaServicio,
                          RecargoServicio recargoServicio,
                          AsistenciaMensualServicio asistenciaMensualServicio,
                          NotificacionService notificacionService) {
        this.mensualidadServicio = mensualidadServicio;
        this.matriculaServicio = matriculaServicio;
        this.recargoServicio = recargoServicio;
        this.asistenciaMensualServicio = asistenciaMensualServicio;
        this.notificacionService = notificacionService;
    }

    /**
     * Genera las mensualidades para el mes vigente
     * Todos los dias 1 a medianoche.
     */
    @Scheduled(cron = "0 0 0 1 * *", zone = "${app.time-zone}")
    public void generarMensualidadesMesVigente() {
        mensualidadServicio.generarMensualidadesParaMesVigente();
    }

    /**
     * Genera las matriculas para el año vigente
     * Cada 1 de enero a medianoche.
     */
    @Scheduled(cron = "0 0 0 1 1 *", zone = "${app.time-zone}")
    public void generarMatriculasAnioVigente() {
        matriculaServicio.generarMatriculasAnioVigente();
    }

    /**
     * Aplica recargos automaticos
     * Todos los dias a la 1:00AM.
     */
    @Scheduled(cron = "0 0 1 * * *", zone = "${app.time-zone}")
    public void aplicarRecargosAutomaticos() {
        recargoServicio.aplicarRecargosAutomaticos();
    }

    /**
     * Crea asistencias detalladas para las inscripciones activas
     * Todos los dias a las 2:00AM.
     */
    @Scheduled(cron = "0 0 2 * * *", zone = "${app.time-zone}")
    public void crearAsistenciasParaInscripcionesActivas() {
        asistenciaMensualServicio.crearAsistenciasParaInscripcionesActivasDetallado();
    }

    /**
     * Genera y envia las notificaciones de cumpleaños del dia
     * Todos los dias a las 8:00AM.
     */
    @Scheduled(cron = "0 0 10 * * *", zone = "${app.time-zone}")
    public void enviarNotificacionesCumpleanios() {
        try {
            List<String> mensajes = notificacionService.generarYObtenerCumpleanerosDelDia();
            log.info("Notificaciones de cumpleaños procesadas cantidad={}", mensajes.size());
        } catch (IOException e) {
            log.error("Falló el proceso de notificaciones de cumpleaños", e);
        }
    }
}
