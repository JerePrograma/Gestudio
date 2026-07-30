package gestudio.servicios.notificaciones;

import gestudio.entidades.Alumno;
import gestudio.repositorios.AlumnoRepositorio;
import gestudio.repositorios.NotificacionRepositorio;
import gestudio.repositorios.ProfesorRepositorio;
import gestudio.servicios.email.EmailAsyncService;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

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
    private final EmailAsyncService email;
    private final Clock clock;

    public NotificacionService(AlumnoRepositorio alumnos,
                               ProfesorRepositorio profesores,
                               NotificacionRepositorio notificaciones,
                               EmailAsyncService email,
                               Clock clock) {
        this.alumnos = alumnos;
        this.profesores = profesores;
        this.notificaciones = notificaciones;
        this.email = email;
        this.clock = clock;
    }

    @Transactional
    public List<String> generarYObtenerCumpleanerosDelDia() {
        LocalDate hoy = LocalDate.now(clock);
        List<String> mensajes = new ArrayList<>();
        List<Runnable> efectos = new ArrayList<>();
        for (Alumno alumno : alumnos.findByActivoTrue()) {
            if (cumpleHoy(alumno.getFechaNacimiento(), hoy)) {
                String mensaje = "Alumno: " + alumno.getNombre() + " " + alumno.getApellido();
                mensajes.add(mensaje);
                if (guardar("alumno:" + alumno.getId() + ":" + hoy, mensaje, hoy)
                        && alumno.getEmail() != null && !alumno.getEmail().isBlank()) {
                    efectos.add(() -> email.enviarMailCumple(alumno));
                }
            }
        }
        profesores.findByActivoTrue().forEach(profesor -> {
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
        return notificaciones.insertarSiAusente(TIPO, mensaje, clock.instant(), fecha, key) == 1;
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
}
