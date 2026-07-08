package ledance.tarifas.application;

import ledance.auditoria.application.AuditService;
import ledance.entidades.RolSistema;
import ledance.entidades.Usuario;
import ledance.infra.errores.TratadorDeErrores.DisciplinaNotFoundException;
import ledance.infra.errores.TratadorDeErrores.OperacionNoPermitidaException;
import ledance.repositorios.DisciplinaRepositorio;
import ledance.repositorios.UsuarioRepositorio;
import ledance.tarifas.api.TarifaDisciplinaRequest;
import ledance.tarifas.api.TarifaDisciplinaResponse;
import ledance.tarifas.persistence.TarifaDisciplina;
import ledance.tarifas.persistence.TarifaDisciplinaRepositorio;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;

@Service
public class TarifaDisciplinaServicio {
    private final TarifaDisciplinaRepositorio tarifas;
    private final DisciplinaRepositorio disciplinas;
    private final UsuarioRepositorio usuarios;
    private final AuditService audit;
    private final Clock clock;

    public TarifaDisciplinaServicio(TarifaDisciplinaRepositorio tarifas, DisciplinaRepositorio disciplinas,
                                    UsuarioRepositorio usuarios, AuditService audit, Clock clock) {
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
                && !tieneRol(actorActual, RolSistema.SUPERADMIN)) {
            throw new OperacionNoPermitidaException("Sólo SUPERADMIN puede cargar una tarifa histórica");
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
        audit.registrar("TARIFAS", "TARIFA_CREADA", "DISCIPLINA_TARIFA", tarifa.getId().toString(),
                actorActual, null, Map.of("disciplinaId", disciplinaId,
                        "vigenteDesde", request.vigenteDesde().toString()));
        return response(tarifa);
    }

    @Transactional(readOnly = true)
    public List<TarifaDisciplinaResponse> listar(Long disciplinaId) {
        if (!disciplinas.existsById(disciplinaId)) throw new DisciplinaNotFoundException(disciplinaId);
        return tarifas.findByDisciplinaIdOrderByVigenteDesdeDesc(disciplinaId).stream()
                .map(this::response).toList();
    }

    @Transactional(readOnly = true)
    public TarifaDisciplina vigente(Long disciplinaId, LocalDate fecha) {
        return tarifas.findFirstByDisciplinaIdAndVigenteDesdeLessThanEqualOrderByVigenteDesdeDesc(
                disciplinaId, fecha).orElseThrow(() -> new TarifaHistoricaNoDefinidaException(fecha));
    }

    private Usuario actorAutorizado(Usuario actor) {
        if (actor == null || actor.getId() == null) throw new OperacionNoPermitidaException("Actor requerido");
        return usuarios.findWithAuthoritiesById(actor.getId()).filter(Usuario::isEnabled)
                .filter(value -> value.getAuthorities().stream()
                        .anyMatch(authority -> "PERM_DISCIPLINAS_WRITE".equals(authority.getAuthority())))
                .orElseThrow(() -> new OperacionNoPermitidaException("Actor sin permisos para administrar tarifas"));
    }

    private static boolean tieneRol(Usuario usuario, RolSistema rol) {
        return usuario.getRoles().stream().anyMatch(value -> Boolean.TRUE.equals(value.getActivo())
                && rol.name().equals(value.getCodigo()));
    }

    private TarifaDisciplinaResponse response(TarifaDisciplina value) {
        return new TarifaDisciplinaResponse(value.getId(), value.getDisciplina().getId(), value.getVigenteDesde(),
                value.getValorCuota().toPlainString(), value.getMatricula().toPlainString(),
                value.getClaseSuelta().toPlainString(), value.getClasePrueba().toPlainString(), value.getMotivo(),
                value.getCreadaPor().getId(), value.getCreadaPor().getNombreUsuario(), value.getCreatedAt(),
                tarifas.estaUtilizada(value.getId()));
    }

    public static class TarifaHistoricaNoDefinidaException extends RuntimeException {
        private final LocalDate fecha;

        public TarifaHistoricaNoDefinidaException(LocalDate fecha) {
            super("No existe una tarifa verificable para " + fecha);
            this.fecha = fecha;
        }

        public LocalDate fecha() { return fecha; }
    }
}
