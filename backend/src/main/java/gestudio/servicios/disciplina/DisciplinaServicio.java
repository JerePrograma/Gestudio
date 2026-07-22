package gestudio.servicios.disciplina;

import jakarta.persistence.EntityNotFoundException;
import gestudio.dto.alumno.AlumnoMapper;
import gestudio.dto.alumno.response.AlumnoResponse;
import gestudio.dto.disciplina.DisciplinaMapper;
import gestudio.dto.disciplina.request.DisciplinaModificacionRequest;
import gestudio.dto.disciplina.request.DisciplinaRegistroRequest;
import gestudio.dto.disciplina.response.DisciplinaHorarioResponse;
import gestudio.dto.disciplina.response.DisciplinaResponse;
import gestudio.dto.profesor.ProfesorMapper;
import gestudio.dto.profesor.response.ProfesorResponse;
import gestudio.entidades.DiaSemana;
import gestudio.entidades.Disciplina;
import gestudio.entidades.DisciplinaHorario;
import gestudio.entidades.Profesor;
import gestudio.entidades.Salon;
import gestudio.infra.errores.TratadorDeErrores.DisciplinaNotFoundException;
import gestudio.infra.errores.TratadorDeErrores.ProfesorNotFoundException;
import gestudio.infra.errores.TratadorDeErrores.ResourceNotFoundException;
import gestudio.repositorios.DisciplinaRepositorio;
import gestudio.repositorios.ProfesorRepositorio;
import gestudio.repositorios.SalonRepositorio;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.YearMonth;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

@Service
public class DisciplinaServicio {
    private final DisciplinaRepositorio disciplinas;
    private final ProfesorRepositorio profesores;
    private final SalonRepositorio salones;
    private final DisciplinaMapper mapper;
    private final AlumnoMapper alumnoMapper;
    private final ProfesorMapper profesorMapper;
    private final DisciplinaHorarioServicio horarios;
    private final Clock clock;

    public DisciplinaServicio(DisciplinaRepositorio disciplinas,
                              ProfesorRepositorio profesores,
                              SalonRepositorio salones,
                              DisciplinaMapper mapper,
                              AlumnoMapper alumnoMapper,
                              ProfesorMapper profesorMapper,
                              DisciplinaHorarioServicio horarios,
                              Clock clock) {
        this.disciplinas = disciplinas;
        this.profesores = profesores;
        this.salones = salones;
        this.mapper = mapper;
        this.alumnoMapper = alumnoMapper;
        this.profesorMapper = profesorMapper;
        this.horarios = horarios;
        this.clock = clock;
    }

    @Transactional
    public DisciplinaResponse crearDisciplina(DisciplinaRegistroRequest request) {
        Disciplina disciplina = mapper.toEntity(request);
        disciplina.setId(null);
        disciplina.setProfesor(profesor(request.profesorId()));
        disciplina.setSalon(salon(request.salonId()));
        disciplina.setHorarios(new ArrayList<>());
        disciplinas.save(disciplina);
        if (request.horarios() != null) {
            horarios.guardarHorarios(disciplina.getId(), request.horarios());
        }
        return mapper.toResponse(disciplina);
    }

    @Transactional
    public DisciplinaResponse actualizarDisciplina(Long id, DisciplinaModificacionRequest request) {
        Disciplina disciplina = obtener(id);
        mapper.updateEntityFromRequest(request, disciplina);
        disciplina.setProfesor(profesor(request.profesorId()));
        disciplina.setSalon(salon(request.salonId()));
        horarios.actualizarHorarios(disciplina,
                request.horarios() == null ? List.of() : request.horarios(), LocalDate.now(clock));
        return mapper.toResponse(disciplina);
    }

    @Transactional
    public void eliminarDisciplina(Long id) {
        darBajaDisciplina(id);
    }

    @Transactional
    public void darBajaDisciplina(Long id) {
        Disciplina disciplina = obtener(id);
        disciplina.setActivo(false);
    }

    @Transactional(readOnly = true)
    public DisciplinaResponse obtenerDisciplinaPorId(Long id) {
        return mapper.toResponse(obtener(id));
    }

    @Transactional(readOnly = true)
    public List<DisciplinaResponse> listarDisciplinas() {
        return disciplinas.findByActivoTrue().stream().map(mapper::toResponse).toList();
    }

    @Transactional(readOnly = true)
    public List<DisciplinaResponse> listarDisciplinasSimplificadas() {
        return listarDisciplinas();
    }

    @Transactional(readOnly = true)
    public List<DisciplinaResponse> buscarPorNombre(String nombre) {
        return disciplinas.buscarPorNombre(nombre).stream().map(mapper::toResponse).toList();
    }

    @Transactional(readOnly = true)
    public List<DisciplinaResponse> obtenerDisciplinasPorFecha(String fecha) {
        DiaSemana dia = switch (LocalDate.parse(fecha).getDayOfWeek()) {
            case MONDAY -> DiaSemana.LUNES;
            case TUESDAY -> DiaSemana.MARTES;
            case WEDNESDAY -> DiaSemana.MIERCOLES;
            case THURSDAY -> DiaSemana.JUEVES;
            case FRIDAY -> DiaSemana.VIERNES;
            case SATURDAY -> DiaSemana.SABADO;
            case SUNDAY -> DiaSemana.DOMINGO;
        };
        return horarios.obtenerHorariosPorDia(dia).stream()
                .map(DisciplinaHorario::getDisciplina).distinct().map(mapper::toResponse).toList();
    }

    @Transactional(readOnly = true)
    public List<DisciplinaResponse> obtenerDisciplinasPorHorario(LocalTime inicio) {
        return disciplinas.findByActivoTrue().stream()
                .filter(d -> d.getHorarios().stream().anyMatch(h -> h.getHorarioInicio().equals(inicio)))
                .map(mapper::toResponse).toList();
    }

    @Transactional(readOnly = true)
    public List<AlumnoResponse> obtenerAlumnosDeDisciplina(Long disciplinaId) {
        return disciplinas.findAlumnosPorDisciplina(disciplinaId).stream().map(alumnoMapper::toResponse).toList();
    }

    @Transactional(readOnly = true)
    public ProfesorResponse obtenerProfesorDeDisciplina(Long disciplinaId) {
        return profesorMapper.toResponse(disciplinas.findProfesorPorDisciplina(disciplinaId)
                .orElseThrow(() -> new DisciplinaNotFoundException(disciplinaId)));
    }

    @Transactional(readOnly = true)
    public List<LocalDate> obtenerDiasClase(Long disciplinaId, Integer mes, Integer anio) {
        Set<DayOfWeek> dias = new LinkedHashSet<>();
        horarios.obtenerHorariosEntidad(disciplinaId)
                .forEach(h -> dias.add(h.getDiaSemana().toDayOfWeek()));
        YearMonth periodo = YearMonth.of(anio, mes);
        List<LocalDate> fechas = new ArrayList<>();
        for (int dia = 1; dia <= periodo.lengthOfMonth(); dia++) {
            LocalDate fecha = periodo.atDay(dia);
            if (dias.contains(fecha.getDayOfWeek())) {
                fechas.add(fecha);
            }
        }
        return fechas;
    }

    @Transactional(readOnly = true)
    public List<DisciplinaHorarioResponse> obtenerHorarios(Long disciplinaId) {
        return horarios.obtenerHorarios(disciplinaId);
    }

    private Disciplina obtener(Long id) {
        return disciplinas.findById(id).orElseThrow(() -> new EntityNotFoundException("Disciplina no encontrada"));
    }

    private Profesor profesor(Long id) {
        return profesores.findById(id).orElseThrow(() -> new ProfesorNotFoundException(id));
    }

    private Salon salon(Long id) {
        return salones.findById(id).orElseThrow(() -> new ResourceNotFoundException("Salón no encontrado"));
    }
}
