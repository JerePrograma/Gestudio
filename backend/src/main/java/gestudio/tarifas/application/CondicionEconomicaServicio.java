package gestudio.tarifas.application;

import gestudio.auditoria.application.AuditService;
import gestudio.entidades.Bonificacion;
import gestudio.entidades.Inscripcion;
import gestudio.entidades.Usuario;
import gestudio.infra.errores.TratadorDeErrores.OperacionNoPermitidaException;
import gestudio.infra.errores.TratadorDeErrores.RecursoNoEncontradoException;
import gestudio.repositorios.BonificacionRepositorio;
import gestudio.repositorios.InscripcionRepositorio;
import gestudio.repositorios.UsuarioRepositorio;
import gestudio.tarifas.api.CondicionEconomicaRequest;
import gestudio.tarifas.api.CondicionEconomicaResponse;
import gestudio.tarifas.persistence.CondicionEconomicaInscripcion;
import gestudio.tarifas.persistence.CondicionEconomicaRepositorio;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;

@Service
public class CondicionEconomicaServicio {

    private static final String PERM_TARIFAS_ADMIN = "PERM_TARIFAS_ADMIN";
    private static final String PERM_TARIFAS_HISTORICAS = "PERM_TARIFAS_HISTORICAS";

    private final CondicionEconomicaRepositorio condiciones;
    private final InscripcionRepositorio inscripciones;
    private final BonificacionRepositorio bonificaciones;
    private final UsuarioRepositorio usuarios;
    private final AuditService audit;
    private final Clock clock;

    public CondicionEconomicaServicio(CondicionEconomicaRepositorio condiciones,
                                      InscripcionRepositorio inscripciones,
                                      BonificacionRepositorio bonificaciones,
                                      UsuarioRepositorio usuarios,
                                      AuditService audit,
                                      Clock clock) {
        this.condiciones = condiciones;
        this.inscripciones = inscripciones;
        this.bonificaciones = bonificaciones;
        this.usuarios = usuarios;
        this.audit = audit;
        this.clock = clock;
    }

    @Transactional
    public CondicionEconomicaResponse crear(Long inscripcionId,
                                            CondicionEconomicaRequest request,
                                            Usuario actor) {
        Usuario actorActual = actorAutorizado(actor);

        if (request.vigenteDesde().isBefore(LocalDate.now(clock))
                && !actorActual.tienePermiso(PERM_TARIFAS_HISTORICAS)) {
            throw new OperacionNoPermitidaException("Permiso requerido: " + PERM_TARIFAS_HISTORICAS);
        }

        if (condiciones.existsByInscripcionIdAndVigenteDesde(inscripcionId, request.vigenteDesde())) {
            throw new OperacionNoPermitidaException("Ya existe una condición para la misma fecha efectiva");
        }

        Inscripcion inscripcion = inscripciones.findById(inscripcionId)
                .orElseThrow(() -> new RecursoNoEncontradoException("Inscripción no encontrada"));

        Bonificacion bonificacion = request.bonificacionId() == null
                ? null
                : bonificaciones.findById(request.bonificacionId())
                  .orElseThrow(() -> new RecursoNoEncontradoException("Bonificación no encontrada"));

        CondicionEconomicaInscripcion condicion = new CondicionEconomicaInscripcion();
        condicion.setInscripcion(inscripcion);
        condicion.setVigenteDesde(request.vigenteDesde());
        condicion.setCostoParticular(request.costoParticular());
        condicion.setBonificacion(bonificacion);
        condicion.setBonificacionDescripcionSnapshot(bonificacion == null ? null : bonificacion.getDescripcion());
        condicion.setBonificacionPorcentajeSnapshot(bonificacion == null
                ? BigDecimal.ZERO
                : bonificacion.getPorcentajeDescuento());
        condicion.setBonificacionValorFijoSnapshot(bonificacion == null
                ? BigDecimal.ZERO
                : bonificacion.getValorFijo());
        condicion.setMotivo(request.motivo().trim());
        condicion.setCreadaPor(actorActual);
        condicion.setCreatedAt(clock.instant());

        condicion = condiciones.saveAndFlush(condicion);

        audit.registrar(
                "TARIFAS",
                "CONDICION_ECONOMICA_CREADA",
                "INSCRIPCION_CONDICION",
                condicion.getId().toString(),
                actorActual,
                null,
                Map.of(
                        "inscripcionId", inscripcionId,
                        "vigenteDesde", request.vigenteDesde().toString()
                )
        );

        return response(condicion);
    }

    @Transactional(readOnly = true)
    public List<CondicionEconomicaResponse> listar(Long inscripcionId) {
        if (!inscripciones.existsById(inscripcionId)) {
            throw new RecursoNoEncontradoException("Inscripción no encontrada");
        }

        return condiciones.findByInscripcionIdOrderByVigenteDesdeDesc(inscripcionId)
                .stream()
                .map(this::response)
                .toList();
    }

    @Transactional(readOnly = true)
    public CondicionEconomicaInscripcion vigente(Long inscripcionId, LocalDate fecha) {
        return condiciones.findFirstByInscripcionIdAndVigenteDesdeLessThanEqualOrderByVigenteDesdeDesc(inscripcionId, fecha)
                .orElseThrow(() -> new CondicionHistoricaNoDefinidaException(fecha));
    }

    private Usuario actorAutorizado(Usuario actor) {
        if (actor == null || actor.getId() == null) {
            throw new OperacionNoPermitidaException("Actor requerido");
        }

        return usuarios.findByIdConRolesYPermisos(actor.getId())
                .filter(Usuario::isEnabled)
                .filter(usuario -> usuario.tienePermiso(PERM_TARIFAS_ADMIN))
                .orElseThrow(() -> new OperacionNoPermitidaException("Actor sin permisos para administrar condiciones económicas"));
    }

    private CondicionEconomicaResponse response(CondicionEconomicaInscripcion value) {
        return new CondicionEconomicaResponse(
                value.getId(),
                value.getInscripcion().getId(),
                value.getVigenteDesde(),
                decimalNullable(value.getCostoParticular()),
                value.getBonificacion() == null ? null : value.getBonificacion().getId(),
                value.getBonificacionDescripcionSnapshot(),
                value.getBonificacionPorcentajeSnapshot().toPlainString(),
                value.getBonificacionValorFijoSnapshot().toPlainString(),
                value.getMotivo(),
                value.getCreadaPor().getId(),
                value.getCreadaPor().getNombreUsuario(),
                value.getCreatedAt(),
                condiciones.estaUtilizada(value.getId())
        );
    }

    private static String decimalNullable(BigDecimal value) {
        return value == null ? null : value.toPlainString();
    }

    public static class CondicionHistoricaNoDefinidaException extends RuntimeException {
        public CondicionHistoricaNoDefinidaException(LocalDate fecha) {
            super("No existe una condición económica verificable para " + fecha);
        }
    }
}