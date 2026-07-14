package gestudio.servicios.notificaciones;

import gestudio.entidades.Alumno;
import gestudio.entidades.Notificacion;
import gestudio.repositorios.AlumnoRepositorio;
import gestudio.repositorios.NotificacionRepositorio;
import gestudio.repositorios.ProfesorRepositorio;
import gestudio.servicios.email.EmailAsyncService;
import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import java.io.IOException;
import java.io.InputStream;
import java.time.Clock;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

@Service
public class NotificacionService {
    private static final String TIPO = "CUMPLEANOS";
    private final AlumnoRepositorio alumnos;
    private final ProfesorRepositorio profesores;
    private final NotificacionRepositorio notificaciones;
    private final Environment environment;
    private final EmailAsyncService email;
    private final Clock clock;

    public NotificacionService(AlumnoRepositorio alumnos,
                               ProfesorRepositorio profesores,
                               NotificacionRepositorio notificaciones,
                               Environment environment,
                               EmailAsyncService email,
                               Clock clock) {
        this.alumnos = alumnos;
        this.profesores = profesores;
        this.notificaciones = notificaciones;
        this.environment = environment;
        this.email = email;
        this.clock = clock;
    }

    @Transactional
    public List<String> generarYObtenerCumpleanerosDelDia() throws IOException {
        LocalDate hoy = LocalDate.now(clock);
        List<String> mensajes = new ArrayList<>();
        List<Runnable> efectos = new ArrayList<>();
        boolean prod = environment.acceptsProfiles(Profiles.of("prod"));
        byte[] firma = prod ? firma() : new byte[0];

        for (Alumno alumno : alumnos.findAll()) {
            if (cumpleHoy(alumno.getFechaNacimiento(), hoy)) {
                String mensaje = "Alumno: " + alumno.getNombre() + " " + alumno.getApellido();
                mensajes.add(mensaje);
                if (guardar("alumno:" + alumno.getId() + ":" + hoy, mensaje, hoy)
                        && prod && alumno.getEmail() != null && !alumno.getEmail().isBlank()) {
                    efectos.add(() -> email.enviarMailCumple(alumno, firma));
                }
            }
        }
        profesores.findAll().forEach(profesor -> {
            if (cumpleHoy(profesor.getFechaNacimiento(), hoy)) {
                String mensaje = "Profesor: " + profesor.getNombre() + " " + profesor.getApellido();
                mensajes.add(mensaje);
                guardar("profesor:" + profesor.getId() + ":" + hoy, mensaje, hoy);
            }
        });

        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCommit() {
                efectos.forEach(Runnable::run);
            }
        });
        return mensajes;
    }

    private boolean guardar(String key, String mensaje, LocalDate fecha) {
        if (notificaciones.existsByDedupKey(key)) {
            return false;
        }
        Notificacion notificacion = new Notificacion();
        notificacion.setTipo(TIPO);
        notificacion.setMensaje(mensaje);
        notificacion.setFechaNegocio(fecha);
        notificacion.setFechaCreacion(clock.instant());
        notificacion.setDedupKey(key);
        notificacion.setLeida(false);
        notificaciones.save(notificacion);
        return true;
    }

    private static boolean cumpleHoy(LocalDate nacimiento, LocalDate hoy) {
        if (nacimiento == null) {
            return false;
        }
        if (nacimiento.getMonthValue() == hoy.getMonthValue()
                && nacimiento.getDayOfMonth() == hoy.getDayOfMonth()) {
            return true;
        }
        return !hoy.isLeapYear() && nacimiento.getMonthValue() == 2 && nacimiento.getDayOfMonth() == 29
                && hoy.getMonthValue() == 2 && hoy.getDayOfMonth() == 28;
    }

    private byte[] firma() throws IOException {
        try (InputStream entrada = getClass().getResourceAsStream("/firma_mesa-de-trabajo-1.png")) {
            if (entrada == null) {
                throw new IOException("Firma no disponible");
            }
            return entrada.readAllBytes();
        }
    }
}
