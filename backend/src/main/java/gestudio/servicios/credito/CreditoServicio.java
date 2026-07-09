package gestudio.servicios.credito;

import jakarta.persistence.EntityNotFoundException;
import gestudio.cuotas.application.CargoEventoServicio;
import gestudio.dto.credito.request.CreditoAjusteRequest;
import gestudio.dto.credito.request.CreditoConsumoRequest;
import gestudio.dto.credito.request.CreditoReversionRequest;
import gestudio.dto.credito.response.MovimientoCreditoResponse;
import gestudio.entidades.Alumno;
import gestudio.entidades.Cargo;
import gestudio.entidades.EstadoCargo;
import gestudio.entidades.MovimientoCredito;
import gestudio.entidades.TipoMovimientoCredito;
import gestudio.entidades.Usuario;
import gestudio.infra.errores.TratadorDeErrores.OperacionNoPermitidaException;
import gestudio.infra.idempotencia.IdempotencyLockService;
import gestudio.infra.idempotencia.RequestHash;
import gestudio.infra.seguridad.RbacService;
import gestudio.repositorios.AlumnoRepositorio;
import gestudio.repositorios.CargoRepositorio;
import gestudio.repositorios.MovimientoCreditoRepositorio;
import gestudio.servicios.cargo.CargoServicio;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.Map;

@Service
public class CreditoServicio {

    private static final String PERM_CREDITOS_ADMIN = "PERM_CREDITOS_ADMIN";
    private static final String PERM_CREDITOS_CONSUMIR = "PERM_CREDITOS_CONSUMIR";

    private final MovimientoCreditoRepositorio movimientos;
    private final AlumnoRepositorio alumnos;
    private final CargoRepositorio cargos;
    private final CargoServicio cargoServicio;
    private final CargoEventoServicio eventos;
    private final RbacService rbac;
    private final IdempotencyLockService idempotencyLocks;

    public CreditoServicio(MovimientoCreditoRepositorio movimientos,
                           AlumnoRepositorio alumnos,
                           CargoRepositorio cargos,
                           CargoServicio cargoServicio,
                           CargoEventoServicio eventos,
                           RbacService rbac,
                           IdempotencyLockService idempotencyLocks) {
        this.movimientos = movimientos;
        this.alumnos = alumnos;
        this.cargos = cargos;
        this.cargoServicio = cargoServicio;
        this.eventos = eventos;
        this.rbac = rbac;
        this.idempotencyLocks = idempotencyLocks;
    }

    @Transactional
    public MovimientoCreditoResponse consumir(CreditoConsumoRequest request, Usuario principal) {
        Usuario usuario = rbac.exigirPermiso(principal, PERM_CREDITOS_CONSUMIR, "CONSUMIR_CREDITO");

        String requestHash = RequestHash.sha256(
                "CONSUMIR_CREDITO",
                request.alumnoId().toString(),
                request.cargoId().toString(),
                decimal(monedaPositiva(request.importe()))
        );

        idempotencyLocks.lock("CONSUMIR_CREDITO", request.idempotencyKey());

        MovimientoCredito previo = movimientos.findByIdempotencyKey(request.idempotencyKey()).orElse(null);
        if (previo != null) {
            validarReintento(previo, requestHash);
            return respuesta(previo);
        }

        Alumno alumno = alumnoBloqueado(request.alumnoId());

        previo = movimientos.findByIdempotencyKey(request.idempotencyKey()).orElse(null);
        if (previo != null) {
            validarReintento(previo, requestHash);
            return respuesta(previo);
        }

        Cargo cargo = cargos.findByIdForUpdate(request.cargoId())
                .orElseThrow(() -> new EntityNotFoundException("Cargo no encontrado"));

        BigDecimal importe = monedaPositiva(request.importe());

        if (!cargo.getAlumno().getId().equals(alumno.getId())) {
            throw new OperacionNoPermitidaException("El cargo no pertenece al alumno");
        }

        if (cargo.getEstado() == EstadoCargo.ANULADO || cargo.getEstado() == EstadoCargo.PAGADO) {
            throw new OperacionNoPermitidaException("El cargo no admite crédito");
        }

        if (importe.compareTo(movimientos.saldoByAlumnoId(alumno.getId())) > 0) {
            throw new OperacionNoPermitidaException("El crédito disponible es insuficiente");
        }

        if (importe.compareTo(cargoServicio.saldo(cargo)) > 0) {
            throw new OperacionNoPermitidaException("El consumo supera el saldo del cargo");
        }

        var estadoAnterior = cargo.getEstado();
        BigDecimal saldoAnterior = cargoServicio.saldo(cargo);

        MovimientoCredito movimiento = new MovimientoCredito();
        movimiento.setAlumno(alumno);
        movimiento.setCargo(cargo);
        movimiento.setTipo(TipoMovimientoCredito.CONSUMO);
        movimiento.setImporte(importe);
        movimiento.setUsuario(usuario);
        movimiento.setIdempotencyKey(request.idempotencyKey());
        movimiento.setRequestHash(requestHash);
        movimientos.saveAndFlush(movimiento);

        cargoServicio.actualizarEstado(cargo);

        eventos.registrar(
                cargo,
                "CREDITO_APLICADO",
                estadoAnterior,
                saldoAnterior,
                cargoServicio.saldo(cargo),
                "MOVIMIENTO_CREDITO",
                movimiento.getId(),
                "credito:" + request.idempotencyKey() + ":aplicado",
                usuario,
                Map.of("importe", decimal(importe))
        );

        return respuesta(movimiento);
    }

    @Transactional
    public MovimientoCreditoResponse revertirConsumo(Long movimientoId,
                                                     CreditoReversionRequest request,
                                                     Usuario principal) {
        Usuario usuario = rbac.exigirPermiso(principal, PERM_CREDITOS_ADMIN, "REVERTIR_CONSUMO_CREDITO");

        String requestHash = RequestHash.sha256(
                "REVERTIR_CONSUMO_CREDITO",
                movimientoId.toString(),
                request.motivo()
        );

        idempotencyLocks.lock("REVERTIR_CONSUMO_CREDITO", request.idempotencyKey());

        MovimientoCredito previo = movimientos.findByIdempotencyKey(request.idempotencyKey()).orElse(null);
        if (previo != null) {
            validarReintento(previo, requestHash);
            return respuesta(previo);
        }

        MovimientoCredito referencia = movimientos.findById(movimientoId)
                .orElseThrow(() -> new EntityNotFoundException("Movimiento de crédito no encontrado"));

        Alumno alumno = alumnoBloqueado(referencia.getAlumno().getId());

        previo = movimientos.findByIdempotencyKey(request.idempotencyKey()).orElse(null);
        if (previo != null) {
            validarReintento(previo, requestHash);
            return respuesta(previo);
        }

        MovimientoCredito original = movimientos.findByIdForUpdate(movimientoId)
                .orElseThrow(() -> new EntityNotFoundException("Movimiento de crédito no encontrado"));

        if (original.getTipo() != TipoMovimientoCredito.CONSUMO || original.getCargo() == null) {
            throw new OperacionNoPermitidaException("Sólo puede revertirse un consumo de crédito");
        }

        if (movimientos.findByMovimientoRevertidoId(movimientoId).isPresent()) {
            throw new OperacionNoPermitidaException("El consumo de crédito ya fue revertido");
        }

        Cargo cargo = cargos.findByIdForUpdate(original.getCargo().getId())
                .orElseThrow(() -> new EntityNotFoundException("Cargo no encontrado"));

        var estadoAnterior = cargo.getEstado();
        BigDecimal saldoAnterior = cargoServicio.saldo(cargo);

        MovimientoCredito reverso = new MovimientoCredito();
        reverso.setAlumno(alumno);
        reverso.setTipo(TipoMovimientoCredito.REVERSO);
        reverso.setImporte(original.getImporte());
        reverso.setMovimientoRevertido(original);
        reverso.setUsuario(usuario);
        reverso.setIdempotencyKey(request.idempotencyKey());
        reverso.setRequestHash(requestHash);
        reverso.setMotivo(request.motivo());
        movimientos.saveAndFlush(reverso);

        cargoServicio.actualizarEstado(cargo);

        eventos.registrar(
                cargo,
                "CREDITO_REVERTIDO",
                estadoAnterior,
                saldoAnterior,
                cargoServicio.saldo(cargo),
                "MOVIMIENTO_CREDITO",
                reverso.getId(),
                "credito:" + request.idempotencyKey() + ":revertido",
                usuario,
                Map.of("importe", decimal(reverso.getImporte()), "movimientoOriginalId", original.getId())
        );

        return respuesta(reverso);
    }

    @Transactional
    public MovimientoCreditoResponse ajustar(CreditoAjusteRequest request, Usuario principal) {
        Usuario usuario = rbac.exigirPermiso(principal, PERM_CREDITOS_ADMIN, "AJUSTAR_CREDITO");

        String requestHash = RequestHash.sha256(
                "AJUSTAR_CREDITO",
                request.alumnoId().toString(),
                decimal(monedaPositiva(request.importe())),
                request.direccion(),
                request.motivo()
        );

        idempotencyLocks.lock("AJUSTAR_CREDITO", request.idempotencyKey());

        MovimientoCredito previo = movimientos.findByIdempotencyKey(request.idempotencyKey()).orElse(null);
        if (previo != null) {
            validarReintento(previo, requestHash);
            return respuesta(previo);
        }

        Alumno alumno = alumnoBloqueado(request.alumnoId());

        previo = movimientos.findByIdempotencyKey(request.idempotencyKey()).orElse(null);
        if (previo != null) {
            validarReintento(previo, requestHash);
            return respuesta(previo);
        }

        BigDecimal importe = monedaPositiva(request.importe());

        TipoMovimientoCredito tipo = request.direccion().equals("CREDITO")
                ? TipoMovimientoCredito.AJUSTE_CREDITO
                : TipoMovimientoCredito.AJUSTE_DEBITO;

        if (tipo == TipoMovimientoCredito.AJUSTE_DEBITO
                && importe.compareTo(movimientos.saldoByAlumnoId(alumno.getId())) > 0) {
            throw new OperacionNoPermitidaException("El ajuste dejaría crédito negativo");
        }

        MovimientoCredito ajuste = new MovimientoCredito();
        ajuste.setAlumno(alumno);
        ajuste.setTipo(tipo);
        ajuste.setImporte(importe);
        ajuste.setUsuario(usuario);
        ajuste.setIdempotencyKey(request.idempotencyKey());
        ajuste.setRequestHash(requestHash);
        ajuste.setMotivo(request.motivo());
        movimientos.saveAndFlush(ajuste);

        return respuesta(ajuste);
    }

    @Transactional(readOnly = true)
    public String saldo(Long alumnoId) {
        return decimal(movimientos.saldoByAlumnoId(alumnoId));
    }

    private Alumno alumnoBloqueado(Long id) {
        return alumnos.findActivoByIdForUpdate(id)
                .orElseThrow(() -> new OperacionNoPermitidaException("El alumno no existe o está inactivo"));
    }

    private void validarReintento(MovimientoCredito previo, String requestHash) {
        if (!requestHash.equals(previo.getRequestHash())) {
            throw new OperacionNoPermitidaException("La idempotency key ya fue usada con otro contenido");
        }
    }

    private MovimientoCreditoResponse respuesta(MovimientoCredito movimiento) {
        Cargo cargo = movimiento.getCargo() != null
                ? movimiento.getCargo()
                : movimiento.getMovimientoRevertido() != null
                  ? movimiento.getMovimientoRevertido().getCargo()
                  : null;

        return new MovimientoCreditoResponse(
                movimiento.getId(),
                movimiento.getAlumno().getId(),
                cargo == null ? null : cargo.getId(),
                movimiento.getTipo().name(),
                decimal(movimiento.getImporte()),
                decimal(movimientos.saldoByAlumnoId(movimiento.getAlumno().getId())),
                cargo == null ? null : decimal(cargoServicio.saldo(cargo)),
                movimiento.getIdempotencyKey()
        );
    }

    private static BigDecimal monedaPositiva(String valor) {
        try {
            BigDecimal importe = new BigDecimal(valor).setScale(2, RoundingMode.UNNECESSARY);

            if (importe.signum() <= 0) {
                throw new IllegalArgumentException("El importe debe ser mayor que cero");
            }

            return importe;
        } catch (NumberFormatException | ArithmeticException e) {
            throw new IllegalArgumentException("El importe debe tener como máximo dos decimales");
        }
    }

    private static String decimal(BigDecimal importe) {
        return importe.setScale(2, RoundingMode.UNNECESSARY).toPlainString();
    }
}