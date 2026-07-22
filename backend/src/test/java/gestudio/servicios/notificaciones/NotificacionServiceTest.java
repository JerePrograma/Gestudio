package gestudio.servicios.notificaciones;

import gestudio.entidades.Alumno;
import gestudio.entidades.Profesor;
import gestudio.repositorios.AlumnoRepositorio;
import gestudio.repositorios.NotificacionRepositorio;
import gestudio.repositorios.ProfesorRepositorio;
import gestudio.servicios.email.EmailAsyncService;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.transaction.support.TransactionSynchronizationUtils;

import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.same;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class NotificacionServiceTest {
    private static final ZoneId BUENOS_AIRES = ZoneId.of("America/Argentina/Buenos_Aires");

    @Mock private AlumnoRepositorio alumnos;
    @Mock private ProfesorRepositorio profesores;
    @Mock private NotificacionRepositorio notificaciones;
    @Mock private Environment environment;
    @Mock private EmailAsyncService email;
    private final Set<String> guardadas = new HashSet<>();

    @BeforeEach
    void iniciarTransaccionSimulada() {
        TransactionSynchronizationManager.initSynchronization();
        guardadas.clear();
        when(notificaciones.insertarSiAusente(
                anyString(), anyString(), any(Instant.class), any(LocalDate.class), anyString()))
                .thenAnswer(invocation -> guardadas.add(invocation.getArgument(4)) ? 1 : 0);
    }

    @AfterEach
    void limpiarTransaccionSimulada() {
        TransactionSynchronizationManager.clearSynchronization();
    }

    @Test
    void incluyeSoloCumpleaniosDelDiaDePersonasActivas() throws Exception {
        Alumno hoy = alumno(1L, "Hoy", LocalDate.of(2010, 7, 21), true);
        Alumno proximo = alumno(2L, "Próximo", LocalDate.of(2010, 7, 22), true);
        Alumno fuera = alumno(3L, "Fuera", LocalDate.of(2010, 8, 21), true);
        Alumno inactivo = alumno(4L, "Inactivo", LocalDate.of(2010, 7, 21), false);
        lenient().when(alumnos.findAll()).thenReturn(List.of(hoy, proximo, fuera, inactivo));
        when(alumnos.findByActivoTrue()).thenReturn(List.of(hoy, proximo, fuera));
        lenient().when(profesores.findAll()).thenReturn(List.of(
                profesor(5L, "Inactivo", LocalDate.of(1980, 7, 21), false)));
        when(profesores.findByActivoTrue()).thenReturn(List.of());

        List<String> mensajes = servicioEn("2026-07-21T15:00:00Z")
                .generarYObtenerCumpleanerosDelDia();

        assertThat(mensajes).containsExactly("Alumno: Hoy Prueba");
        verify(alumnos, never()).findAll();
        verify(profesores, never()).findAll();
    }

    @Test
    void respetaCambioDeAnio() throws Exception {
        Alumno finDeAnio = alumno(1L, "Diciembre", LocalDate.of(2010, 12, 31), true);
        Alumno inicioDeAnio = alumno(2L, "Enero", LocalDate.of(2010, 1, 1), true);
        personasActivas(finDeAnio, inicioDeAnio);

        assertThat(servicioEn("2026-12-31T15:00:00Z").generarYObtenerCumpleanerosDelDia())
                .containsExactly("Alumno: Diciembre Prueba");
        assertThat(servicioEn("2027-01-01T15:00:00Z").generarYObtenerCumpleanerosDelDia())
                .containsExactly("Alumno: Enero Prueba");
    }

    @Test
    void celebraEl29DeFebreroEl28SoloEnAniosNoBisiestos() throws Exception {
        personasActivas(alumno(1L, "Bisiesto", LocalDate.of(2012, 2, 29), true));

        assertThat(servicioEn("2027-02-28T15:00:00Z").generarYObtenerCumpleanerosDelDia())
                .containsExactly("Alumno: Bisiesto Prueba");
        assertThat(servicioEn("2028-02-28T15:00:00Z").generarYObtenerCumpleanerosDelDia()).isEmpty();
        assertThat(servicioEn("2028-02-29T15:00:00Z").generarYObtenerCumpleanerosDelDia())
                .containsExactly("Alumno: Bisiesto Prueba");
    }

    @Test
    void usaLaFechaDeNegocioDeBuenosAiresEIdempotenciaDiaria() throws Exception {
        personasActivas(alumno(1L, "Local", LocalDate.of(2010, 7, 21), true));
        NotificacionService service = servicioEn("2026-07-22T02:30:00Z");

        assertThat(service.generarYObtenerCumpleanerosDelDia()).containsExactly("Alumno: Local Prueba");
        assertThat(service.generarYObtenerCumpleanerosDelDia()).containsExactly("Alumno: Local Prueba");
        assertThat(guardadas).hasSize(1);
    }

    @Test
    void enviaElCorreoAfterCommitSoloParaLaTransaccionQueInserta() throws Exception {
        Alumno cumpleanero = alumno(1L, "Correo", LocalDate.of(2010, 7, 21), true);
        cumpleanero.setEmail("cumpleanero@example.test");
        personasActivas(cumpleanero);
        when(environment.acceptsProfiles(any(Profiles.class))).thenReturn(true);
        NotificacionService service = servicioEn("2026-07-21T15:00:00Z");

        service.generarYObtenerCumpleanerosDelDia();
        service.generarYObtenerCumpleanerosDelDia();

        verify(email, never()).enviarMailCumple(any(Alumno.class), any(byte[].class));
        TransactionSynchronizationUtils.triggerAfterCommit();
        verify(email, times(1)).enviarMailCumple(same(cumpleanero), any(byte[].class));
    }

    private NotificacionService servicioEn(String instant) {
        return new NotificacionService(alumnos, profesores, notificaciones, environment, email,
                Clock.fixed(Instant.parse(instant), BUENOS_AIRES));
    }

    private void personasActivas(Alumno... activos) {
        List<Alumno> personas = List.of(activos);
        when(alumnos.findByActivoTrue()).thenReturn(personas);
        when(profesores.findByActivoTrue()).thenReturn(List.of());
    }

    private static Alumno alumno(Long id, String nombre, LocalDate nacimiento, boolean activo) {
        Alumno alumno = new Alumno();
        alumno.setId(id);
        alumno.setNombre(nombre);
        alumno.setApellido("Prueba");
        alumno.setFechaNacimiento(nacimiento);
        alumno.setActivo(activo);
        return alumno;
    }

    private static Profesor profesor(Long id, String nombre, LocalDate nacimiento, boolean activo) {
        Profesor profesor = new Profesor();
        profesor.setId(id);
        profesor.setNombre(nombre);
        profesor.setApellido("Prueba");
        profesor.setFechaNacimiento(nacimiento);
        profesor.setActivo(activo);
        return profesor;
    }
}
