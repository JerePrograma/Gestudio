package gestudio.servicios.asistencia;

import gestudio.dto.asistencia.AsistenciaDiariaMapper;
import gestudio.dto.asistencia.request.AsistenciaDiariaModificacionRequest;
import gestudio.dto.asistencia.request.AsistenciaDiariaRegistroRequest;
import gestudio.dto.asistencia.response.AsistenciaDiariaDetalleResponse;
import gestudio.entidades.AsistenciaAlumnoMensual;
import gestudio.entidades.AsistenciaDiaria;
import gestudio.infra.errores.TratadorDeErrores.RecursoNoEncontradoException;
import gestudio.repositorios.AsistenciaAlumnoMensualRepositorio;
import gestudio.repositorios.AsistenciaDiariaRepositorio;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;

@Service
public class AsistenciaDiariaServicio {
    private final AsistenciaDiariaRepositorio diarias;
    private final AsistenciaAlumnoMensualRepositorio alumnosMensuales;
    private final AsistenciaDiariaMapper mapper;
    private final Clock clock;

    public AsistenciaDiariaServicio(AsistenciaDiariaRepositorio diarias,
                                    AsistenciaAlumnoMensualRepositorio alumnosMensuales,
                                    AsistenciaDiariaMapper mapper,
                                    Clock clock) {
        this.diarias = diarias;
        this.alumnosMensuales = alumnosMensuales;
        this.mapper = mapper;
        this.clock = clock;
    }

    @Transactional
    public AsistenciaDiariaDetalleResponse registrarAsistencia(AsistenciaDiariaRegistroRequest request) {
        validarFecha(request.fecha());
        AsistenciaAlumnoMensual registro = registro(request.asistenciaAlumnoMensualId());
        if (diarias.existsByAsistenciaAlumnoMensualIdAndFecha(registro.getId(), request.fecha())) {
            throw new IllegalStateException("La asistencia ya existe");
        }
        AsistenciaDiaria diaria = new AsistenciaDiaria();
        diaria.setAsistenciaAlumnoMensual(registro);
        diaria.setFecha(request.fecha());
        diaria.setEstado(request.estado());
        diaria.setVigente(true);
        return mapper.toDTO(diarias.save(diaria));
    }

    @Transactional
    public AsistenciaDiariaDetalleResponse actualizarAsistencia(Long id, AsistenciaDiariaModificacionRequest request) {
        validarFecha(request.fecha());
        AsistenciaDiaria diaria = diarias.findById(id)
                .orElseThrow(() -> new RecursoNoEncontradoException("Asistencia no encontrada"));
        if (!diaria.getFecha().equals(request.fecha())) {
            throw new IllegalArgumentException("La fecha histórica de asistencia no puede cambiarse");
        }
        diaria.setEstado(request.estado());
        return mapper.toDTO(diaria);
    }

    @Transactional
    public AsistenciaDiariaDetalleResponse registrarOActualizarAsistencia(AsistenciaDiariaRegistroRequest request) {
        validarFecha(request.fecha());
        AsistenciaAlumnoMensual registro = registro(request.asistenciaAlumnoMensualId());
        AsistenciaDiaria diaria = diarias.findByAsistenciaAlumnoMensualIdAndFecha(registro.getId(), request.fecha())
                .orElseGet(() -> {
                    AsistenciaDiaria nueva = new AsistenciaDiaria();
                    nueva.setAsistenciaAlumnoMensual(registro);
                    nueva.setFecha(request.fecha());
                    return nueva;
                });
        diaria.setEstado(request.estado());
        diaria.setVigente(true);
        return mapper.toDTO(diarias.save(diaria));
    }

    @Transactional(readOnly = true)
    public Page<AsistenciaDiariaDetalleResponse> obtenerAsistenciasPorDisciplinaYFecha(Long disciplinaId, LocalDate fecha, Pageable pageable) {
        return diarias.findByAsistenciaAlumnoMensual_AsistenciaMensual_Disciplina_IdAndFecha(disciplinaId, fecha, pageable)
                .map(mapper::toDTO);
    }

    @Transactional(readOnly = true)
    public List<AsistenciaDiariaDetalleResponse> obtenerAsistenciasPorPlanilla(Long planillaId) {
        return obtenerAsistenciasPorAsistenciaMensual(planillaId);
    }

    @Transactional(readOnly = true)
    public List<AsistenciaDiariaDetalleResponse> obtenerAsistenciasPorAsistenciaMensual(Long planillaId) {
        return diarias.findByAsistenciaAlumnoMensual_AsistenciaMensual_Id(planillaId).stream()
                .map(mapper::toDTO).toList();
    }

    @Transactional
    public void eliminarAsistencia(Long id) {
        AsistenciaDiaria diaria = diarias.findById(id)
                .orElseThrow(() -> new RecursoNoEncontradoException("Asistencia no encontrada"));
        diaria.setVigente(false);
    }

    @Transactional(readOnly = true)
    public Map<Long, Integer> obtenerResumenAsistenciasPorAlumno(Long disciplinaId, LocalDate inicio, LocalDate fin) {
        return diarias.contarAsistenciasPorAlumno(disciplinaId, inicio, fin);
    }

    @Transactional
    public void eliminarAsistenciaAlumnoMensual(Long id) {
        registro(id).setActivo(false);
    }

    private AsistenciaAlumnoMensual registro(Long id) {
        return alumnosMensuales.findById(id)
                .orElseThrow(() -> new RecursoNoEncontradoException("Registro mensual de alumno no encontrado"));
    }

    private void validarFecha(LocalDate fecha) {
        if (fecha.isAfter(LocalDate.now(clock))) {
            throw new IllegalStateException("No se puede registrar asistencia futura");
        }
    }
}
