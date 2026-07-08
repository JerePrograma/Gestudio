package gestudio.servicios.disciplina;

import gestudio.dto.disciplina.DisciplinaHorarioMapper;
import gestudio.dto.disciplina.request.DisciplinaHorarioModificacionRequest;
import gestudio.dto.disciplina.request.DisciplinaHorarioRequest;
import gestudio.dto.disciplina.response.DisciplinaHorarioResponse;
import gestudio.entidades.DiaSemana;
import gestudio.entidades.Disciplina;
import gestudio.entidades.DisciplinaHorario;
import gestudio.infra.errores.TratadorDeErrores;
import gestudio.repositorios.DisciplinaHorarioRepositorio;
import gestudio.repositorios.DisciplinaRepositorio;
import jakarta.transaction.Transactional;
import gestudio.servicios.asistencia.AsistenciaMensualServicio;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@Service
public class DisciplinaHorarioServicio {

    private static final Logger log = LoggerFactory.getLogger(DisciplinaHorarioServicio.class);

    private final DisciplinaHorarioRepositorio disciplinaHorarioRepositorio;
    private final DisciplinaRepositorio disciplinaRepositorio;
    private final DisciplinaHorarioMapper disciplinaHorarioMapper;
    private final AsistenciaMensualServicio asistenciaMensualServicio;

    public DisciplinaHorarioServicio(
            DisciplinaHorarioRepositorio disciplinaHorarioRepositorio,
            DisciplinaRepositorio disciplinaRepositorio,
            DisciplinaHorarioMapper disciplinaHorarioMapper, AsistenciaMensualServicio asistenciaMensualServicio) {
        this.disciplinaHorarioRepositorio = disciplinaHorarioRepositorio;
        this.disciplinaRepositorio = disciplinaRepositorio;
        this.disciplinaHorarioMapper = disciplinaHorarioMapper;
        this.asistenciaMensualServicio = asistenciaMensualServicio;
    }


    /**
     * Actualiza los horarios de una disciplina en base a una lista de solicitudes de modificacion.
     * Se actualizan los horarios existentes, se crean nuevos y se eliminan los que no vienen en la solicitud.
     * Finalmente, se invoca la actualizacion de la planilla de asistencia (por cambio de horario)
     * usando la fecha de cambio proporcionada por el caso de uso.
     *
     * @param disciplina   la disciplina a la cual se actualizaran los horarios
     * @param horariosRequest lista de solicitudes de modificacion de horarios
     * @param fechaCambio  la fecha a partir de la cual se deben recalcular las asistencias
     * @return la lista de horarios guardados
     */
    @Transactional
    public List<DisciplinaHorario> actualizarHorarios(Disciplina disciplina,
                                                      List<DisciplinaHorarioModificacionRequest> horariosRequest,
                                                      LocalDate fechaCambio) {
        log.info("Actualizando {} horarios para disciplina id: {}", horariosRequest.size(), disciplina.getId());

        // Obten la lista actual de horarios asociados a la disciplina
        List<DisciplinaHorario> existentes = new ArrayList<>(disciplina.getHorarios());

        // Mapea los horarios existentes por su ID para facilitar actualizaciones
        Map<Long, DisciplinaHorario> existentesMap = existentes.stream()
                .filter(h -> h.getId() != null)
                .collect(Collectors.toMap(DisciplinaHorario::getId, h -> h));

        List<DisciplinaHorario> updatedHorarios = new ArrayList<>();

        // Procesa cada DTO recibido: si tiene ID y existe, se actualiza; si no, se crea nuevo
        for (DisciplinaHorarioModificacionRequest dto : horariosRequest) {
            if (dto.id() != null && existentesMap.containsKey(dto.id())) {
                // Actualizar horario existente
                DisciplinaHorario horarioExistente = existentesMap.get(dto.id());
                horarioExistente.setDiaSemana(dto.diaSemana());
                horarioExistente.setHorarioInicio(dto.horarioInicio());
                horarioExistente.setDuracion(dto.duracion());
                updatedHorarios.add(horarioExistente);
                // Remueve del mapa para identificar los que deben eliminarse
                existentesMap.remove(dto.id());
            } else {
                // Se trata de un nuevo horario; se mapea y se asigna la disciplina
                DisciplinaHorario nuevo = disciplinaHorarioMapper.toEntity(
                        new DisciplinaHorarioRequest(dto.diaSemana(), dto.horarioInicio(), dto.duracion())
                );
                nuevo.setDisciplina(disciplina);
                updatedHorarios.add(nuevo);
            }
        }

        // Los horarios que quedan en existentesMap son los que deben eliminarse
        for (DisciplinaHorario eliminado : existentesMap.values()) {
            disciplina.getHorarios().remove(eliminado);
            disciplinaHorarioRepositorio.delete(eliminado);
        }

        // Actualiza la coleccion de horarios en la disciplina sin reemplazar la instancia
        disciplina.getHorarios().clear();
        disciplina.getHorarios().addAll(updatedHorarios);
        List<DisciplinaHorario> savedHorarios = disciplinaHorarioRepositorio.saveAll(updatedHorarios);
        log.info("Actualizados {} horarios para disciplina id: {}", savedHorarios.size(), disciplina.getId());

        // Invoca la actualizacion de las planillas de asistencia debido al cambio de horario.
        // Se utiliza la fecha de cambio proporcionada.
        asistenciaMensualServicio.actualizarPlanillaPorCambioHorario(disciplina.getId(), fechaCambio);

        return savedHorarios;
    }

    /**
     * Guarda los horarios para una disciplina.
     * Primero elimina los horarios existentes y luego guarda los nuevos.
     */
    @Transactional
    public List<DisciplinaHorario> guardarHorarios(Long disciplinaId, List<DisciplinaHorarioRequest> horariosRequest) {
        log.info("Guardando {} horarios para disciplina id: {}", horariosRequest.size(), disciplinaId);

        // Recupera la disciplina
        Disciplina disciplina = disciplinaRepositorio.findById(disciplinaId)
                .orElseThrow(() -> new TratadorDeErrores.DisciplinaNotFoundException(disciplinaId));
        log.info("Disciplina recuperada: id={}, nombre={}", disciplina.getId(), disciplina.getNombre());

        // Elimina los horarios previos asociados a la disciplina
        log.info("Eliminando horarios previos para disciplina id: {}", disciplinaId);
        disciplinaHorarioRepositorio.deleteByDisciplinaId(disciplinaId);

        // Mapear cada request a entidad y asignarle la disciplina
        List<DisciplinaHorario> nuevosHorarios = horariosRequest.stream()
                .map(req -> {
                    DisciplinaHorario horario = disciplinaHorarioMapper.toEntity(req);
                    // Asignacion exclusiva en el servicio:
                    horario.setDisciplina(disciplina);
                    log.info("Horario mapeado: dia={}, inicio={}, duracion={}, disciplina asignada: {}",
                            horario.getDiaSemana(), horario.getHorarioInicio(), horario.getDuracion(),
                            (horario.getDisciplina() != null ? horario.getDisciplina().getId() : "null"));
                    return horario;
                })
                .collect(Collectors.toList());
        log.info("Mapeados {} horarios para guardar", nuevosHorarios.size());

        // Guarda todos los nuevos horarios y actualiza la coleccion en la disciplina
        List<DisciplinaHorario> savedHorarios = disciplinaHorarioRepositorio.saveAll(nuevosHorarios);
        log.info("Se guardaron {} horarios para disciplina id: {}", savedHorarios.size(), disciplinaId);
        disciplina.getHorarios().clear();
        disciplina.getHorarios().addAll(savedHorarios);

        log.info("Coleccion de horarios actualizada en la disciplina: {}", disciplina.getHorarios());

        return savedHorarios;
    }

    /**
     * Obtiene los horarios asociados a una disciplina y los retorna en formato de respuesta.
     */
    public List<DisciplinaHorarioResponse> obtenerHorarios(Long disciplinaId) {
        log.info("Obteniendo horarios para disciplina id: {}", disciplinaId);
        List<DisciplinaHorario> horarios = disciplinaHorarioRepositorio.findByDisciplinaId(disciplinaId);
        log.info("Se encontraron {} horarios", horarios.size());
        List<DisciplinaHorarioResponse> response = disciplinaHorarioMapper.toResponseList(horarios);
        log.info("Mapeo de horarios completado, retornando respuesta");
        return response;
    }

    /**
     * Elimina todos los horarios asociados a una disciplina.
     */
    @Transactional
    public void eliminarHorarios(Long disciplinaId) {
        log.info("Eliminando todos los horarios para disciplina id: {}", disciplinaId);
        disciplinaHorarioRepositorio.deleteByDisciplinaId(disciplinaId);
        log.info("Horarios eliminados para disciplina id: {}", disciplinaId);
    }

    /**
     * Obtiene los horarios que corresponden a un dia especifico.
     */
    public List<DisciplinaHorario> obtenerHorariosPorDia(DiaSemana diaSemana) {
        log.info("Obteniendo horarios para el dia: {}", diaSemana);
        List<DisciplinaHorario> horarios = disciplinaHorarioRepositorio.findByDiaSemana(diaSemana);
        log.info("Se encontraron {} horarios para el dia {}", horarios.size(), diaSemana);
        return horarios;
    }

    @Transactional
    public List<DisciplinaHorario> obtenerHorariosEntidad(Long disciplinaId) {
        // Este metodo usa el repositorio y retorna las entidades directamente
        return disciplinaHorarioRepositorio.findByDisciplinaId(disciplinaId);
    }

}
