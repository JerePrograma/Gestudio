package gestudio.tarifas.application;

import gestudio.auditoria.application.AuditService;
import gestudio.entidades.Usuario;
import gestudio.infra.errores.TratadorDeErrores.DisciplinaNotFoundException;
import gestudio.infra.errores.TratadorDeErrores.OperacionNoPermitidaException;
import gestudio.repositorios.DisciplinaRepositorio;
import gestudio.repositorios.UsuarioRepositorio;
import gestudio.tarifas.api.TarifaDisciplinaRequest;
import gestudio.tarifas.api.TarifaDisciplinaResponse;
import gestudio.tarifas.persistence.TarifaDisciplina;
import gestudio.tarifas.persistence.TarifaDisciplinaRepositorio;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;

import static gestudio.infra.seguridad.PermissionCodes.PERM_TARIFAS_ADMIN;
import static gestudio.infra.seguridad.PermissionCodes.PERM_TARIFAS_HISTORICAS;

@Service
public class TarifaDisciplinaServicio {

    private final TarifaDisciplinaRepositorio tarifas;
    private final DisciplinaRepositorio disciplinas;
    private final UsuarioRepositorio usuarios;
    private final AuditService audit;
    private final Clock clock;

    public TarifaDisciplinaServicio(TarifaDisciplinaRepositorio tarifas,
                                    DisciplinaRepositorio disciplinas,
                                    UsuarioRepositorio usuarios,
                                    AuditService audit,
                                    Clock clock) {
        this.tarifas = tarifas;
        this.disciplinas = disciplinas;
        this.usuarios = usuarios;
        this.audit = audit;
        this.clock = clock;
    }

    @Transactional
    public TarifaDisciplinaResponse crear(Long disciplinaId, TarifaDisciplinaRequest request, Usuario actor) {
        Usuario actorActual = actorAutorizado(actor);

        if (request.vigenteDesde().isBefore(LocalDate.now(clock))
                && !actorActual.tienePermiso(PERM_TARIFAS_HISTORICAS)) {
            throw new AccessDeniedException("Permiso requerido: " + PERM_TARIFAS_HISTORICAS);
        }

        if (tarifas.existsByDisciplinaIdAndVigenteDesde(disciplinaId, request.vigenteDesde())) {
            throw new OperacionNoPermitidaException("Ya existe una tarifa para la misma fecha efectiva");
        }

        TarifaDisciplina tarifa = new TarifaDisciplina();
        tarifa.setDisciplina(disciplinas.findById(disciplinaId)
                .orElseThrow(() -> new DisciplinaNotFoundException(disciplinaId)));
        tarifa.setVigenteDesde(request.vigenteDesde());
        tarifa.setValorCuota(request.valorCuota());
        tarifa.setMatricula(request.matricula());
        tarifa.setClaseSuelta(request.claseSuelta());
        tarifa.setClasePrueba(request.clasePrueba());
        tarifa.setMotivo(request.motivo().trim());
        tarifa.setCreadaPor(actorActual);
        tarifa.setCreatedAt(clock.instant());

        tarifa = tarifas.saveAndFlush(tarifa);

        audit.registrar(
                "TARIFAS",
                "TARIFA_CREADA",
                "DISCIPLINA_TARIFA",
                tarifa.getId().toString(),
                actorActual,
                null,
                Map.of(
                        "disciplinaId", disciplinaId,
                        "vigenteDesde", request.vigenteDesde().toString()
                )
        );

        return response(tarifa);
    }

    @Transactional(readOnly = true)
    public List<TarifaDisciplinaResponse> listar(Long disciplinaId) {
        if (!disciplinas.existsById(disciplinaId)) {
            throw new DisciplinaNotFoundException(disciplinaId);
        }

        return tarifas.findByDisciplinaIdOrderByVigenteDesdeDesc(disciplinaId)
                .stream()
                .map(this::response)
                .toList();
    }

    @Transactional(readOnly = true)
    public TarifaDisciplina vigente(Long disciplinaId, LocalDate fecha) {
        return tarifas.findFirstByDisciplinaIdAndVigenteDesdeLessThanEqualOrderByVigenteDesdeDesc(disciplinaId, fecha)
                .orElseThrow(() -> new TarifaHistoricaNoDefinidaException(fecha));
    }

    private Usuario actorAutorizado(Usuario actor) {
        if (actor == null || actor.getId() == null) {
            throw new AccessDeniedException("Actor requerido");
        }

        return usuarios.findByIdConRolesYPermisos(actor.getId())
                .filter(Usuario::isEnabled)
                .filter(usuario -> usuario.tienePermiso(PERM_TARIFAS_ADMIN))
                .orElseThrow(() -> new AccessDeniedException("Actor sin permisos para administrar tarifas"));
    }

    private TarifaDisciplinaResponse response(TarifaDisciplina value) {
        return new TarifaDisciplinaResponse(
                value.getId(),
                value.getDisciplina().getId(),
                value.getVigenteDesde(),
                value.getValorCuota().toPlainString(),
                value.getMatricula().toPlainString(),
                value.getClaseSuelta().toPlainString(),
                value.getClasePrueba().toPlainString(),
                value.getMotivo(),
                value.getCreadaPor().getId(),
                value.getCreadaPor().getNombreUsuario(),
                value.getCreatedAt(),
                tarifas.estaUtilizada(value.getId())
        );
    }

    public static class TarifaHistoricaNoDefinidaException extends RuntimeException {
        private final LocalDate fecha;

        public TarifaHistoricaNoDefinidaException(LocalDate fecha) {
            super("No existe una tarifa verificable para " + fecha);
            this.fecha = fecha;
        }

        public LocalDate fecha() {
            return fecha;
        }
    }
}
