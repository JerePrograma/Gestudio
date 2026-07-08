package gestudio.dto.disciplina.response;

import gestudio.entidades.DiaSemana;

import java.math.BigDecimal;
import java.time.LocalTime;

public record DisciplinaHorarioResponse(Long id, DiaSemana diaSemana, LocalTime horarioInicio, BigDecimal duracion) {
}
