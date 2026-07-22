package gestudio.servicios.alumno;

import com.fasterxml.jackson.databind.ObjectMapper;
import gestudio.controladores.AlumnoControlador;
import gestudio.dto.alumno.AlumnoMapper;
import gestudio.dto.alumno.request.AlumnoRegistroRequest;
import gestudio.dto.alumno.response.AlumnoResponse;
import gestudio.entidades.Alumno;
import gestudio.infra.errores.TratadorDeErrores;
import gestudio.repositorios.AlumnoRepositorio;
import gestudio.repositorios.InscripcionRepositorio;
import gestudio.dto.disciplina.DisciplinaMapper;
import org.junit.jupiter.api.Test;
import org.mapstruct.factory.Mappers;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

class AlumnoStateContractTest {

    private static final Clock CLOCK = Clock.fixed(
            Instant.parse("2026-07-21T12:00:00Z"), ZoneId.of("America/Argentina/Buenos_Aires"));
    private final AlumnoMapper mapper = Mappers.getMapper(AlumnoMapper.class);

    @Test
    void mapperIgnoresIdentityStateAndDeactivationFields() {
        AlumnoRegistroRequest request = request(999L, false, LocalDate.of(2026, 7, 20));

        Alumno created = mapper.toEntity(request);
        assertThat(created.getId()).isNull();
        assertThat(created.getActivo()).isTrue();
        assertThat(created.getFechaDeBaja()).isNull();

        Alumno existing = alumno(41L, true, null);
        existing.setVersion(7L);
        mapper.updateEntityFromRequest(request, existing);

        assertThat(existing.getId()).isEqualTo(41L);
        assertThat(existing.getVersion()).isEqualTo(7L);
        assertThat(existing.getActivo()).isTrue();
        assertThat(existing.getFechaDeBaja()).isNull();
        assertThat(existing.getNombre()).isEqualTo("Nombre editado");
    }

    @Test
    void updateUseCaseCannotDeactivateStudentThroughMassAssignment() {
        AlumnoRepositorio alumnos = mock(AlumnoRepositorio.class);
        Alumno existing = alumno(41L, true, null);
        when(alumnos.findByIdAndActivoTrue(41L)).thenReturn(Optional.of(existing));
        AlumnoServicio service = new AlumnoServicio(
                alumnos,
                mock(InscripcionRepositorio.class),
                mapper,
                mock(DisciplinaMapper.class),
                CLOCK);

        AlumnoResponse response = service.actualizarAlumno(
                41L, request(999L, false, LocalDate.of(2026, 7, 20)));

        assertThat(response.id()).isEqualTo(41L);
        assertThat(response.activo()).isTrue();
        assertThat(response.fechaDeBaja()).isNull();
    }

    @Test
    void putValidatesRequestBodyBeforeCallingUseCase() throws Exception {
        AlumnoServicio service = mock(AlumnoServicio.class);
        MockMvc mockMvc = MockMvcBuilders.standaloneSetup(new AlumnoControlador(service))
                .setControllerAdvice(new TratadorDeErrores(CLOCK))
                .build();

        String invalidRequest = new ObjectMapper().findAndRegisterModules().writeValueAsString(
                withName(request(999L, false, LocalDate.of(2026, 7, 20)), " "));

        mockMvc.perform(put("/api/alumnos/41")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(invalidRequest))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"))
                .andExpect(jsonPath("$.fieldErrors[0].field").value("nombre"));
        verifyNoInteractions(service);
    }

    private static Alumno alumno(Long id, boolean activo, LocalDate fechaDeBaja) {
        Alumno alumno = new Alumno();
        alumno.setId(id);
        alumno.setNombre("Nombre actual");
        alumno.setApellido("Apellido");
        alumno.setFechaIncorporacion(LocalDate.of(2025, 1, 10));
        alumno.setActivo(activo);
        alumno.setFechaDeBaja(fechaDeBaja);
        return alumno;
    }

    private static AlumnoRegistroRequest request(Long id, boolean activo, LocalDate fechaDeBaja) {
        return new AlumnoRegistroRequest(
                id,
                "Nombre editado",
                "Apellido",
                LocalDate.of(2010, 5, 15),
                LocalDate.of(2025, 1, 10),
                "111",
                "222",
                "alumno@example.test",
                "12345678",
                fechaDeBaja,
                "Responsable",
                true,
                activo,
                "Notas",
                List.of());
    }

    private static AlumnoRegistroRequest withName(AlumnoRegistroRequest request, String nombre) {
        return new AlumnoRegistroRequest(
                request.id(), nombre, request.apellido(), request.fechaNacimiento(),
                request.fechaIncorporacion(), request.celular1(), request.celular2(),
                request.email(), request.documento(), request.fechaDeBaja(), request.nombrePadres(),
                request.autorizadoParaSalirSolo(), request.activo(), request.otrasNotas(),
                request.inscripciones());
    }
}
