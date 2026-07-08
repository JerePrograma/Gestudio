package gestudio.dto.profesor.response;

import gestudio.dto.disciplina.response.DisciplinaResponse;

import java.time.LocalDate;
import java.util.List;

public record ProfesorResponse(
        Long id,
        String nombre,
        String apellido,
        LocalDate fechaNacimiento, // ✅ NUEVO
        Integer edad, // ✅ Se calcula automaticamente
        String telefono, // ✅ NUEVO
        Boolean activo,
        List<DisciplinaResponse> disciplinas // ✅ Lista de disciplinas que imparte
) {
}