package gestudio.servicios.disciplina;

import gestudio.dto.alumno.AlumnoMapper;
import gestudio.dto.disciplina.DisciplinaMapper;
import gestudio.dto.disciplina.request.DisciplinaHorarioRequest;
import gestudio.dto.disciplina.request.DisciplinaRegistroRequest;
import gestudio.dto.profesor.ProfesorMapper;
import gestudio.entidades.DiaSemana;
import gestudio.entidades.Disciplina;
import gestudio.entidades.DisciplinaHorario;
import gestudio.entidades.Profesor;
import gestudio.entidades.Salon;
import gestudio.repositorios.DisciplinaRepositorio;
import gestudio.repositorios.ProfesorRepositorio;
import gestudio.repositorios.SalonRepositorio;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class DisciplinaServicioTest {

    @Mock private DisciplinaRepositorio disciplinas;
    @Mock private ProfesorRepositorio profesores;
    @Mock private SalonRepositorio salones;
    @Mock private DisciplinaMapper mapper;
    @Mock private AlumnoMapper alumnoMapper;
    @Mock private ProfesorMapper profesorMapper;
    @Mock private DisciplinaHorarioServicio horarios;

    @Test
    void crearDisciplinaNoDuplicaLosHorariosEnLaRespuesta() {
        DisciplinaHorarioRequest horarioRequest = new DisciplinaHorarioRequest(
                DiaSemana.LUNES, LocalTime.of(18, 0), new BigDecimal("1.00"));
        DisciplinaRegistroRequest request = new DisciplinaRegistroRequest(
                null, "Danza", 20L, 30L, new BigDecimal("100.00"), BigDecimal.ZERO,
                BigDecimal.ZERO, BigDecimal.ZERO, List.of(horarioRequest));
        Disciplina disciplina = new Disciplina();
        Profesor profesor = new Profesor();
        Salon salon = new Salon();

        when(mapper.toEntity(request)).thenReturn(disciplina);
        when(profesores.findById(30L)).thenReturn(Optional.of(profesor));
        when(salones.findById(20L)).thenReturn(Optional.of(salon));
        when(disciplinas.save(any(Disciplina.class))).thenAnswer(invocation -> {
            Disciplina saved = invocation.getArgument(0);
            saved.setId(10L);
            return saved;
        });
        when(horarios.guardarHorarios(10L, request.horarios())).thenAnswer(invocation -> {
            DisciplinaHorario saved = new DisciplinaHorario();
            saved.setDisciplina(disciplina);
            disciplina.getHorarios().clear();
            disciplina.getHorarios().add(saved);
            return List.of(saved);
        });

        servicio().crearDisciplina(request);

        assertThat(disciplina.getHorarios()).hasSize(1);
    }

    private DisciplinaServicio servicio() {
        return new DisciplinaServicio(disciplinas, profesores, salones, mapper, alumnoMapper,
                profesorMapper, horarios, Clock.fixed(Instant.EPOCH, ZoneOffset.UTC));
    }
}
