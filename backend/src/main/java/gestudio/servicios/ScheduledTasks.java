package gestudio.servicios;

import gestudio.servicios.asistencia.AsistenciaMensualServicio;
import gestudio.servicios.matricula.MatriculaServicio;
import gestudio.servicios.mensualidad.MensualidadServicio;
import gestudio.servicios.notificaciones.NotificacionService;
import gestudio.servicios.recargo.RecargoServicio;
import gestudio.tenancy.TenantExecutionService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

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
    private final TenantExecutionService tenants;

    public ScheduledTasks(MensualidadServicio mensualidadServicio,
                          MatriculaServicio matriculaServicio,
                          RecargoServicio recargoServicio,
                          AsistenciaMensualServicio asistenciaMensualServicio,
                          NotificacionService notificacionService,
                          TenantExecutionService tenants) {
        this.mensualidadServicio = mensualidadServicio;
        this.matriculaServicio = matriculaServicio;
        this.recargoServicio = recargoServicio;
        this.asistenciaMensualServicio = asistenciaMensualServicio;
        this.notificacionService = notificacionService;
        this.tenants = tenants;
    }

    /**
     * Genera las mensualidades para el mes vigente
     * Todos los dias 1 a medianoche.
     */
    @Scheduled(cron = "0 0 0 1 * *", zone = "${app.time-zone}")
    public void generarMensualidadesMesVigente() {
        tenants.forEachActiveTenant("monthly_fees",
                ignored -> mensualidadServicio.generarMensualidadesParaMesVigente());
    }

    /**
     * Genera las matriculas para el año vigente
     * Cada 1 de enero a medianoche.
     */
    @Scheduled(cron = "0 0 0 1 1 *", zone = "${app.time-zone}")
    public void generarMatriculasAnioVigente() {
        tenants.forEachActiveTenant("annual_enrollments",
                ignored -> matriculaServicio.generarMatriculasAnioVigente());
    }

    /**
     * Aplica recargos automaticos
     * Todos los dias a la 1:00AM.
     */
    @Scheduled(cron = "0 0 1 * * *", zone = "${app.time-zone}")
    public void aplicarRecargosAutomaticos() {
        tenants.forEachActiveTenant("surcharges",
                ignored -> recargoServicio.aplicarRecargosAutomaticos());
    }

    /**
     * Crea asistencias detalladas para las inscripciones activas
     * Todos los dias a las 2:00AM.
     */
    @Scheduled(cron = "0 0 2 * * *", zone = "${app.time-zone}")
    public void crearAsistenciasParaInscripcionesActivas() {
        tenants.forEachActiveTenant("attendance",
                ignored -> asistenciaMensualServicio.crearAsistenciasParaInscripcionesActivasDetallado());
    }

    /**
     * Genera y envia las notificaciones de cumpleaños del dia
     * Todos los dias a las 10:00AM.
     */
    @Scheduled(cron = "0 0 10 * * *", zone = "${app.time-zone}")
    public void enviarNotificacionesCumpleanios() {
        tenants.forEachActiveTenant("birthdays", ignored -> {
            List<String> mensajes = notificacionService.generarYObtenerCumpleanerosDelDia();
            log.info("Notificaciones de cumpleaños procesadas cantidad={}", mensajes.size());
        });
    }
}
