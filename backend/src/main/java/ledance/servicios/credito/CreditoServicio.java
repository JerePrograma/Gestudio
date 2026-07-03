package ledance.servicios.credito;

import jakarta.persistence.EntityNotFoundException;
import ledance.dto.credito.request.CreditoAjusteRequest;
import ledance.dto.credito.request.CreditoConsumoRequest;
import ledance.dto.credito.request.CreditoReversionRequest;
import ledance.dto.credito.response.MovimientoCreditoResponse;
import ledance.entidades.Alumno;
import ledance.entidades.Cargo;
import ledance.entidades.EstadoCargo;
import ledance.entidades.MovimientoCredito;
import ledance.entidades.TipoMovimientoCredito;
import ledance.entidades.Usuario;
import ledance.infra.errores.TratadorDeErrores.OperacionNoPermitidaException;
import ledance.infra.idempotencia.RequestHash;
import ledance.repositorios.AlumnoRepositorio;
import ledance.repositorios.CargoRepositorio;
import ledance.repositorios.MovimientoCreditoRepositorio;
import ledance.repositorios.UsuarioRepositorio;
import ledance.servicios.cargo.CargoServicio;
import ledance.cuotas.application.CargoEventoServicio;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.Map;

@Service
public class CreditoServicio {
    private final MovimientoCreditoRepositorio movimientos;
    private final AlumnoRepositorio alumnos;
    private final CargoRepositorio cargos;
    private final UsuarioRepositorio usuarios;
    private final CargoServicio cargoServicio;
    private final CargoEventoServicio eventos;

    public CreditoServicio(MovimientoCreditoRepositorio movimientos, AlumnoRepositorio alumnos,
                           CargoRepositorio cargos, UsuarioRepositorio usuarios, CargoServicio cargoServicio,
                           CargoEventoServicio eventos) {
        this.movimientos = movimientos;
        this.alumnos = alumnos;
        this.cargos = cargos;
        this.usuarios = usuarios;
        this.cargoServicio = cargoServicio;
        this.eventos = eventos;
    }

    @Transactional
    public MovimientoCreditoResponse consumir(CreditoConsumoRequest request, Usuario principal) {
        String requestHash = RequestHash.sha256("CONSUMIR_CREDITO", request.alumnoId().toString(),
                request.cargoId().toString(), decimal(monedaPositiva(request.importe())));
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
        Usuario usuario = usuarioActivo(principal);
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
        eventos.registrar(cargo, "CREDITO_APLICADO", estadoAnterior, saldoAnterior,
                cargoServicio.saldo(cargo), "MOVIMIENTO_CREDITO", movimiento.getId(),
                "credito:" + request.idempotencyKey() + ":aplicado", usuario,
                Map.of("importe", decimal(importe)));
        return respuesta(movimiento);
    }

    @Transactional
    public MovimientoCreditoResponse revertirConsumo(Long movimientoId, CreditoReversionRequest request,
                                                      Usuario principal) {
        String requestHash = RequestHash.sha256(
                "REVERTIR_CONSUMO_CREDITO", movimientoId.toString(), request.motivo());
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
        Usuario usuario = usuarioActivo(principal);
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
        eventos.registrar(cargo, "CREDITO_REVERTIDO", estadoAnterior, saldoAnterior,
                cargoServicio.saldo(cargo), "MOVIMIENTO_CREDITO", reverso.getId(),
                "credito:" + request.idempotencyKey() + ":revertido", usuario,
                Map.of("importe", decimal(reverso.getImporte()), "movimientoOriginalId", original.getId()));
        return respuesta(reverso);
    }

    @Transactional
    public MovimientoCreditoResponse ajustar(CreditoAjusteRequest request, Usuario principal) {
        String requestHash = RequestHash.sha256("AJUSTAR_CREDITO", request.alumnoId().toString(),
                decimal(monedaPositiva(request.importe())), request.direccion(), request.motivo());
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
                ? TipoMovimientoCredito.AJUSTE_CREDITO : TipoMovimientoCredito.AJUSTE_DEBITO;
        if (tipo == TipoMovimientoCredito.AJUSTE_DEBITO
                && importe.compareTo(movimientos.saldoByAlumnoId(alumno.getId())) > 0) {
            throw new OperacionNoPermitidaException("El ajuste dejaría crédito negativo");
        }
        MovimientoCredito ajuste = new MovimientoCredito();
        ajuste.setAlumno(alumno);
        ajuste.setTipo(tipo);
        ajuste.setImporte(importe);
        ajuste.setUsuario(usuarioActivo(principal));
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

    private Usuario usuarioActivo(Usuario principal) {
        if (principal == null || principal.getId() == null) {
            throw new OperacionNoPermitidaException("Usuario autenticado requerido");
        }
        return usuarios.findById(principal.getId()).filter(u -> Boolean.TRUE.equals(u.getActivo()))
                .orElseThrow(() -> new OperacionNoPermitidaException("El usuario está inactivo"));
    }

    private void validarReintento(MovimientoCredito previo, String requestHash) {
        if (!requestHash.equals(previo.getRequestHash())) {
            throw new OperacionNoPermitidaException("La idempotency key ya fue usada con otro contenido");
        }
    }

    private MovimientoCreditoResponse respuesta(MovimientoCredito movimiento) {
        Cargo cargo = movimiento.getCargo() != null ? movimiento.getCargo()
                : movimiento.getMovimientoRevertido() != null ? movimiento.getMovimientoRevertido().getCargo() : null;
        return new MovimientoCreditoResponse(movimiento.getId(), movimiento.getAlumno().getId(),
                cargo == null ? null : cargo.getId(), movimiento.getTipo().name(), decimal(movimiento.getImporte()),
                decimal(movimientos.saldoByAlumnoId(movimiento.getAlumno().getId())),
                cargo == null ? null : decimal(cargoServicio.saldo(cargo)), movimiento.getIdempotencyKey());
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
