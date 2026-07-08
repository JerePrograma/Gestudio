package gestudio.dto.disciplina.request;

import gestudio.entidades.DiaSemana;

import java.math.BigDecimal;
import java.time.LocalTime;

public record DisciplinaHorarioRequest(DiaSemana diaSemana, LocalTime horarioInicio, BigDecimal duracion) {
}
