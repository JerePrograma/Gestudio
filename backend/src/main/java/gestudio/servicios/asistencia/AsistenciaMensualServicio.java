package gestudio.servicios.asistencia;

import gestudio.dto.asistencia.AsistenciaMensualMapper;
import gestudio.dto.asistencia.request.AsistenciaMensualModificacionRequest;
import gestudio.dto.asistencia.response.AsistenciaMensualDetalleResponse;
import gestudio.dto.asistencia.response.AsistenciaMensualListadoResponse;
import gestudio.dto.asistencia.response.AsistenciasActivasResponse;
import gestudio.entidades.AsistenciaAlumnoMensual;
import gestudio.entidades.AsistenciaDiaria;
import gestudio.entidades.AsistenciaMensual;
import gestudio.entidades.Disciplina;
import gestudio.entidades.DisciplinaHorario;
import gestudio.entidades.EstadoAsistencia;
import gestudio.entidades.EstadoInscripcion;
import gestudio.entidades.Inscripcion;
import gestudio.repositorios.AsistenciaAlumnoMensualRepositorio;
import gestudio.repositorios.AsistenciaDiariaRepositorio;
import gestudio.repositorios.AsistenciaMensualRepositorio;
import gestudio.repositorios.DisciplinaHorarioRepositorio;
import gestudio.repositorios.DisciplinaRepositorio;
import gestudio.repositorios.InscripcionRepositorio;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.YearMonth;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.NoSuchElementException;
import java.util.Set;

@Service
public class AsistenciaMensualServicio {
    private static final Logger log = LoggerFactory.getLogger(AsistenciaMensualServicio.class);
    private final AsistenciaMensualRepositorio planillas;
    private final AsistenciaAlumnoMensualRepositorio alumnosMensuales;
    private final AsistenciaDiariaRepositorio diarias;
    private final InscripcionRepositorio inscripciones;
    private final DisciplinaRepositorio disciplinas;
    private final DisciplinaHorarioRepositorio horarios;
    private final AsistenciaMensualMapper mapper;
    private final Clock clock;

    public AsistenciaMensualServicio(AsistenciaMensualRepositorio planillas,
                                     AsistenciaAlumnoMensualRepositorio alumnosMensuales,
                                     AsistenciaDiariaRepositorio diarias,
                                     InscripcionRepositorio inscripciones,
                                     DisciplinaRepositorio disciplinas,
                                     DisciplinaHorarioRepositorio horarios,
                                     AsistenciaMensualMapper mapper,
                                     Clock clock) {
        this.planillas = planillas;
        this.alumnosMensuales = alumnosMensuales;
        this.diarias = diarias;
        this.inscripciones = inscripciones;
        this.disciplinas = disciplinas;
        this.horarios = horarios;
        this.mapper = mapper;
        this.clock = clock;
    }

    @Transactional
    public AsistenciaMensualDetalleResponse crearPlanilla(Long disciplinaId, int mes, int anio) {
        Disciplina disciplina = disciplinas.findByIdForUpdate(disciplinaId)
                .orElseThrow(() -> new IllegalArgumentException("Disciplina no encontrada"));
        AsistenciaMensual planilla = planillas.findByDisciplina_IdAndMesAndAnio(disciplinaId, mes, anio)
                .orElseGet(() -> {
                    AsistenciaMensual nueva = new AsistenciaMensual();
                    nueva.setDisciplina(disciplina);
                    nueva.setMes(mes);
                    nueva.setAnio(anio);
                    return planillas.save(nueva);
                });
        return mapper.toDetalleDTO(planilla);
    }

    @Transactional
    public void agregarAlumnoAPlanilla(Long inscripcionId, int mes, int anio) {
        Inscripcion inscripcion = inscripciones.findById(inscripcionId)
                .orElseThrow(() -> new IllegalArgumentException("Inscripción no encontrada"));
        Long disciplinaId = inscripcion.getDisciplina().getId();
        crearPlanilla(disciplinaId, mes, anio);
        AsistenciaMensual planilla = planillas.findByDisciplina_IdAndMesAndAnio(disciplinaId, mes, anio).orElseThrow();
        AsistenciaAlumnoMensual registro = alumnosMensuales
                .findByInscripcionIdAndAsistenciaMensualId(inscripcionId, planilla.getId())
                .orElseGet(() -> {
                    AsistenciaAlumnoMensual nuevo = new AsistenciaAlumnoMensual();
                    nuevo.setInscripcion(inscripcion);
                    nuevo.setAsistenciaMensual(planilla);
                    nuevo.setActivo(true);
                    return alumnosMensuales.save(nuevo);
                });
        sincronizarFechas(registro, fechasClase(disciplinaId, mes, anio), LocalDate.MIN);
    }

    @Transactional(readOnly = true)
    public AsistenciaMensualDetalleResponse obtenerPlanillaPorDisciplinaYMes(Long disciplinaId, int mes, int anio) {
        return planillas.findByDisciplina_IdAndMesAndAnioFetch(disciplinaId, mes, anio)
                .map(mapper::toDetalleDTO)
                .orElseThrow(() -> new NoSuchElementException("Planilla no encontrada"));
    }

    @Transactional
    public AsistenciaMensualDetalleResponse actualizarPlanillaAsistencia(Long id, AsistenciaMensualModificacionRequest request) {
        AsistenciaMensual planilla = planillas.findById(id)
                .orElseThrow(() -> new IllegalArgumentException("Planilla no encontrada"));
        request.asistenciasAlumnoMensual().forEach(modificacion -> alumnosMensuales.findById(modificacion.id())
                .filter(a -> a.getAsistenciaMensual().getId().equals(id))
                .ifPresent(a -> a.setObservacion(modificacion.observacion())));
        return mapper.toDetalleDTO(planilla);
    }

    @Transactional(readOnly = true)
    public List<AsistenciaMensualListadoResponse> listarPlanillas(Long profesorId, Long disciplinaId, Integer mes, Integer anio) {
        return planillas.buscarPlanillas(profesorId, disciplinaId, mes, anio).stream()
                .map(mapper::toListadoDTO).toList();
    }

    @Transactional
    public void actualizarPlanillaPorCambioHorario(Long disciplinaId, LocalDate fechaCambio) {
        planillas.findByDisciplina_IdAndMesAndAnio(disciplinaId, fechaCambio.getMonthValue(), fechaCambio.getYear())
                .ifPresent(planilla -> alumnosMensuales.findAll().stream()
                        .filter(a -> a.getAsistenciaMensual().getId().equals(planilla.getId()))
                        .forEach(a -> sincronizarFechas(a,
                                fechasClase(disciplinaId, planilla.getMes(), planilla.getAnio()), fechaCambio)));
    }

    public AsistenciaMensualDetalleResponse obtenerAsistenciaMensualPorParametros(Long disciplinaId, int mes, int anio) {
        return obtenerPlanillaPorDisciplinaYMes(disciplinaId, mes, anio);
    }

    @Transactional
    public AsistenciasActivasResponse crearAsistenciasParaInscripcionesActivasDetallado() {
        YearMonth periodo = YearMonth.now(clock);
        List<Inscripcion> activas = inscripciones.findByEstado(EstadoInscripcion.ACTIVA);
        Set<Long> planillasAntes = new HashSet<>();
        planillas.findAll().forEach(p -> planillasAntes.add(p.getId()));
        int antes = (int) diarias.count();
        for (Inscripcion inscripcion : activas) {
            agregarAlumnoAPlanilla(inscripcion.getId(), periodo.getMonthValue(), periodo.getYear());
        }
        int creadas = (int) planillas.findAll().stream().filter(p -> !planillasAntes.contains(p.getId())).count();
        int generadas = (int) diarias.count() - antes;
        log.info("Asistencias generadas período={} inscripciones={} planillas={} diarias={}",
                periodo, activas.size(), creadas, generadas);
        return new AsistenciasActivasResponse(activas.size(), creadas, generadas, List.of());
    }

    private void sincronizarFechas(AsistenciaAlumnoMensual registro, List<LocalDate> fechas, LocalDate desde) {
        Set<LocalDate> esperadas = new HashSet<>(fechas);
        List<AsistenciaDiaria> existentes = diarias.findByAsistenciaAlumnoMensual_IdAndFechaGreaterThanEqual(
                registro.getId(), desde);
        existentes.forEach(a -> a.setVigente(esperadas.contains(a.getFecha())));
        Set<LocalDate> actuales = new HashSet<>();
        diarias.findByAsistenciaAlumnoMensualId(registro.getId()).forEach(a -> actuales.add(a.getFecha()));
        List<AsistenciaDiaria> nuevas = fechas.stream().filter(f -> !f.isBefore(desde) && !actuales.contains(f))
                .map(f -> {
                    AsistenciaDiaria diaria = new AsistenciaDiaria();
                    diaria.setAsistenciaAlumnoMensual(registro);
                    diaria.setFecha(f);
                    diaria.setEstado(EstadoAsistencia.AUSENTE);
                    diaria.setVigente(true);
                    return diaria;
                }).toList();
        diarias.saveAll(nuevas);
    }

    private List<LocalDate> fechasClase(Long disciplinaId, int mes, int anio) {
        Set<DayOfWeek> dias = new HashSet<>();
        horarios.findByDisciplinaId(disciplinaId).stream()
                .map(DisciplinaHorario::getDiaSemana).map(d -> d.toDayOfWeek()).forEach(dias::add);
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
}
