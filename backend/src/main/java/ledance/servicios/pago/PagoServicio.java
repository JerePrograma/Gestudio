package ledance.servicios.pago;

import jakarta.persistence.EntityNotFoundException;
import ledance.dto.pago.request.AplicacionPagoRequest;
import ledance.dto.pago.request.PagoAnulacionRequest;
import ledance.dto.pago.request.PagoRegistroRequest;
import ledance.dto.pago.response.AplicacionPagoResponse;
import ledance.dto.pago.response.PagoResponse;
import ledance.dto.pago.response.PagoResumenResponse;
import ledance.entidades.Alumno;
import ledance.entidades.AplicacionPago;
import ledance.entidades.Cargo;
import ledance.entidades.EstadoAplicacionPago;
import ledance.entidades.EstadoCargo;
import ledance.entidades.EstadoPago;
import ledance.entidades.EstadoReciboPendiente;
import ledance.entidades.MetodoPago;
import ledance.entidades.MovimientoCaja;
import ledance.entidades.MovimientoCredito;
import ledance.entidades.Pago;
import ledance.entidades.Recibo;
import ledance.entidades.ReciboPendiente;
import ledance.entidades.TipoEfectoRecibo;
import ledance.entidades.TipoMovimientoCaja;
import ledance.entidades.TipoMovimientoCredito;
import ledance.entidades.Usuario;
import ledance.infra.errores.TratadorDeErrores.OperacionNoPermitidaException;
import ledance.infra.idempotencia.RequestHash;
import ledance.repositorios.AlumnoRepositorio;
import ledance.repositorios.AplicacionPagoRepositorio;
import ledance.repositorios.CargoRepositorio;
import ledance.repositorios.MetodoPagoRepositorio;
import ledance.repositorios.MovimientoCajaRepositorio;
import ledance.repositorios.MovimientoCreditoRepositorio;
import ledance.repositorios.PagoRepositorio;
import ledance.repositorios.ReciboPendienteRepositorio;
import ledance.repositorios.ReciboRepositorio;
import ledance.repositorios.UsuarioRepositorio;
import ledance.servicios.cargo.CargoServicio;
import ledance.cuotas.application.CargoEventoServicio;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Clock;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Map;

@Service
public class PagoServicio {
    private static final Logger log = LoggerFactory.getLogger(PagoServicio.class);
    private static final BigDecimal CERO = new BigDecimal("0.00");

    private final PagoRepositorio pagos;
    private final CargoRepositorio cargos;
    private final AplicacionPagoRepositorio aplicaciones;
    private final AlumnoRepositorio alumnos;
    private final MetodoPagoRepositorio metodos;
    private final UsuarioRepositorio usuarios;
    private final MovimientoCajaRepositorio movimientosCaja;
    private final MovimientoCreditoRepositorio movimientosCredito;
    private final ReciboRepositorio recibos;
    private final ReciboPendienteRepositorio recibosPendientes;
    private final Clock clock;
    private final CargoServicio cargoServicio;
    private final CargoEventoServicio eventos;

    public PagoServicio(PagoRepositorio pagos,
                        CargoRepositorio cargos,
                        AplicacionPagoRepositorio aplicaciones,
                        AlumnoRepositorio alumnos,
                        MetodoPagoRepositorio metodos,
                        UsuarioRepositorio usuarios,
                        MovimientoCajaRepositorio movimientosCaja,
                        MovimientoCreditoRepositorio movimientosCredito,
                        ReciboRepositorio recibos,
                        ReciboPendienteRepositorio recibosPendientes,
                        CargoServicio cargoServicio,
                        CargoEventoServicio eventos,
                        Clock clock) {
        this.pagos = pagos;
        this.cargos = cargos;
        this.aplicaciones = aplicaciones;
        this.alumnos = alumnos;
        this.metodos = metodos;
        this.usuarios = usuarios;
        this.movimientosCaja = movimientosCaja;
        this.movimientosCredito = movimientosCredito;
        this.recibos = recibos;
        this.recibosPendientes = recibosPendientes;
        this.cargoServicio = cargoServicio;
        this.eventos = eventos;
        this.clock = clock;
    }

    @Transactional
    public PagoResponse registrarPago(PagoRegistroRequest request, Usuario principal) {
        String hash = hash(request);
        Pago previo = pagos.findByIdempotencyKey(request.idempotencyKey()).orElse(null);
        if (previo != null) {
            return validarReintento(previo, hash);
        }

        Alumno alumno = alumnos.findActivoByIdForUpdate(request.alumnoId())
                .orElseThrow(() -> new OperacionNoPermitidaException("El alumno no existe o está inactivo"));

        previo = pagos.findByIdempotencyKey(request.idempotencyKey()).orElse(null);
        if (previo != null) {
            return validarReintento(previo, hash);
        }

        Usuario usuario = usuarioActivo(principal);
        MetodoPago metodo = metodos.findById(request.metodoPagoId())
                .filter(m -> Boolean.TRUE.equals(m.getActivo()))
                .orElseThrow(() -> new OperacionNoPermitidaException("El método de pago no existe o está inactivo"));
        BigDecimal monto = monedaPositiva(request.montoRecibido(), "montoRecibido");

        List<AplicacionPagoRequest> solicitadas = request.aplicaciones().stream()
                .sorted(Comparator.comparing(AplicacionPagoRequest::cargoId))
                .toList();
        if (new HashSet<>(solicitadas.stream().map(AplicacionPagoRequest::cargoId).toList()).size() != solicitadas.size()) {
            throw new IllegalArgumentException("Un cargo no puede repetirse en el mismo pago");
        }

        List<Cargo> cargosBloqueados = solicitadas.isEmpty()
                ? List.of()
                : cargos.findAllByIdForUpdate(solicitadas.stream().map(AplicacionPagoRequest::cargoId).toList());
        if (cargosBloqueados.size() != solicitadas.size()) {
            throw new EntityNotFoundException("Uno o más cargos no existen");
        }

        BigDecimal totalAplicado = CERO;
        List<BigDecimal> importes = new ArrayList<>(solicitadas.size());
        List<BigDecimal> saldosAnteriores = new ArrayList<>(solicitadas.size());
        List<EstadoCargo> estadosAnteriores = new ArrayList<>(solicitadas.size());
        for (int i = 0; i < solicitadas.size(); i++) {
            AplicacionPagoRequest solicitada = solicitadas.get(i);
            Cargo cargo = cargosBloqueados.get(i);
            if (!cargo.getId().equals(solicitada.cargoId())) {
                throw new IllegalStateException("Los cargos no se bloquearon en orden determinista");
            }
            validarCargo(alumno, cargo);
            BigDecimal importe = monedaPositiva(solicitada.importe(), "aplicaciones.importe");
            BigDecimal saldo = cargoServicio.saldo(cargo);
            if (importe.compareTo(saldo) > 0) {
                throw new OperacionNoPermitidaException("La aplicación supera el saldo del cargo " + cargo.getId());
            }
            totalAplicado = totalAplicado.add(importe);
            importes.add(importe);
            saldosAnteriores.add(saldo);
            estadosAnteriores.add(cargo.getEstado());
        }
        if (totalAplicado.compareTo(monto) > 0) {
            throw new OperacionNoPermitidaException("La suma aplicada supera el monto recibido");
        }
        BigDecimal excedente = monto.subtract(totalAplicado).setScale(2, RoundingMode.UNNECESSARY);
        if (excedente.signum() > 0 && !request.generarCredito()) {
            throw new OperacionNoPermitidaException("El sobrepago requiere generación explícita de crédito");
        }

        LocalDate hoy = LocalDate.now(clock);
        Pago pago = new Pago();
        pago.setAlumno(alumno);
        pago.setMetodoPago(metodo);
        pago.setUsuario(usuario);
        pago.setFecha(hoy);
        pago.setMontoRecibido(monto);
        pago.setEstado(EstadoPago.REGISTRADO);
        pago.setIdempotencyKey(request.idempotencyKey());
        pago.setRequestHash(hash);
        pago.setObservaciones(request.observaciones());
        pago.setCreatedAt(clock.instant());
        pagos.save(pago);

        for (int i = 0; i < cargosBloqueados.size(); i++) {
            Cargo cargo = cargosBloqueados.get(i);
            AplicacionPago aplicacion = new AplicacionPago();
            aplicacion.setPago(pago);
            aplicacion.setCargo(cargo);
            aplicacion.setUsuario(usuario);
            aplicacion.setImporteAplicado(importes.get(i));
            aplicacion.setEstado(EstadoAplicacionPago.APLICADA);
            aplicacion.setFecha(hoy);
            aplicaciones.save(aplicacion);
            cargoServicio.actualizarEstado(cargo);
            eventos.registrar(cargo, "PAGO_APLICADO", estadosAnteriores.get(i), saldosAnteriores.get(i),
                    saldosAnteriores.get(i).subtract(importes.get(i)), "APLICACION_PAGO", aplicacion.getId(),
                    "pago:" + request.idempotencyKey() + ":cargo:" + cargo.getId() + ":aplicado", usuario,
                    Map.of("importe", decimal(importes.get(i)), "pagoId", pago.getId()));
        }

        MovimientoCaja ingreso = new MovimientoCaja();
        ingreso.setTipo(TipoMovimientoCaja.INGRESO_PAGO);
        ingreso.setFecha(hoy);
        ingreso.setImporte(monto);
        ingreso.setMetodoPago(metodo);
        ingreso.setPago(pago);
        ingreso.setUsuario(usuario);
        ingreso.setIdempotencyKey("pago:" + request.idempotencyKey());
        movimientosCaja.save(ingreso);

        if (excedente.signum() > 0) {
            MovimientoCredito credito = new MovimientoCredito();
            credito.setAlumno(alumno);
            credito.setTipo(TipoMovimientoCredito.GENERACION);
            credito.setImporte(excedente);
            credito.setPago(pago);
            credito.setUsuario(usuario);
            credito.setIdempotencyKey("credito:" + request.idempotencyKey());
            credito.setRequestHash(RequestHash.sha256("PAGO_CREDITO", request.idempotencyKey(), decimal(excedente)));
            movimientosCredito.save(credito);
        }

        Recibo recibo = new Recibo();
        recibo.setPago(pago);
        recibos.save(recibo);

        ReciboPendiente pendiente = new ReciboPendiente();
        pendiente.setPago(pago);
        pendiente.setTipo(TipoEfectoRecibo.GENERAR_Y_ENVIAR);
        pendiente.setEstado(EstadoReciboPendiente.PENDIENTE);
        pendiente.setNextAttemptAt(clock.instant());
        pendiente.setIdempotencyKey("recibo:" + pago.getId() + ":GENERAR_Y_ENVIAR");
        recibosPendientes.save(pendiente);

        log.info("Pago registrado id={} alumnoId={} aplicaciones={} credito={}",
                pago.getId(), alumno.getId(), solicitadas.size(), decimal(excedente));
        return respuesta(pago);
    }

    @Transactional
    public PagoResponse anularPago(Long pagoId, PagoAnulacionRequest request, Usuario principal) {
        String reversalHash = RequestHash.sha256("ANULAR_PAGO", pagoId.toString(), request.motivo());
        Pago pago = pagos.findByIdForUpdate(pagoId)
                .orElseThrow(() -> new EntityNotFoundException("Pago no encontrado"));
        if (pago.getEstado() == EstadoPago.ANULADO) {
            if (request.idempotencyKey().equals(pago.getReversalIdempotencyKey())) {
                if (!reversalHash.equals(pago.getReversalRequestHash())) {
                    throw new OperacionNoPermitidaException("La idempotency key ya fue usada con otro contenido");
                }
                return respuesta(pago);
            }
            throw new OperacionNoPermitidaException("El pago ya fue anulado");
        }

        Usuario usuario = usuarioActivo(principal);
        alumnos.findActivoByIdForUpdate(pago.getAlumno().getId())
                .orElseThrow(() -> new OperacionNoPermitidaException("El alumno está inactivo"));

        List<AplicacionPago> activas = aplicaciones.findByPagoIdAndEstadoOrderById(
                pagoId, EstadoAplicacionPago.APLICADA);
        List<Cargo> cargosBloqueados = activas.isEmpty()
                ? List.of()
                : cargos.findAllByIdForUpdate(activas.stream().map(a -> a.getCargo().getId()).sorted().toList());
        if (cargosBloqueados.size() != activas.size()) {
            throw new IllegalStateException("No fue posible bloquear todos los cargos del pago");
        }
        Map<Long, BigDecimal> saldosAnteriores = cargosBloqueados.stream().collect(
                java.util.stream.Collectors.toMap(Cargo::getId, cargoServicio::saldo));
        Map<Long, EstadoCargo> estadosAnteriores = cargosBloqueados.stream().collect(
                java.util.stream.Collectors.toMap(Cargo::getId, Cargo::getEstado));

        List<MovimientoCredito> creditosPago = movimientosCredito.findByPagoId(pagoId).stream()
                .filter(m -> m.getTipo() == TipoMovimientoCredito.GENERACION)
                .toList();
        BigDecimal creditoGenerado = creditosPago.stream()
                .map(MovimientoCredito::getImporte).reduce(CERO, BigDecimal::add);
        if (creditoGenerado.signum() > 0
                && movimientosCredito.saldoByAlumnoId(pago.getAlumno().getId()).compareTo(creditoGenerado) < 0) {
            throw new OperacionNoPermitidaException("El crédito generado por el pago ya fue consumido");
        }

        for (AplicacionPago aplicacion : activas) {
            aplicacion.setEstado(EstadoAplicacionPago.REVERTIDA);
            aplicacion.setMotivoReversion(request.motivo());
            aplicacion.setFechaReversion(clock.instant());
        }
        for (Cargo cargo : cargosBloqueados) {
            cargoServicio.actualizarEstado(cargo);
            eventos.registrar(cargo, "PAGO_REVERTIDO", estadosAnteriores.get(cargo.getId()),
                    saldosAnteriores.get(cargo.getId()), cargoServicio.saldo(cargo), "PAGO", pago.getId(),
                    "pago:" + request.idempotencyKey() + ":cargo:" + cargo.getId() + ":revertido", usuario,
                    Map.of("motivo", request.motivo()));
        }

        MovimientoCaja original = movimientosCaja.findByPagoIdAndTipo(pagoId, TipoMovimientoCaja.INGRESO_PAGO)
                .orElseThrow(() -> new IllegalStateException("El pago no posee movimiento de caja"));
        MovimientoCaja reversoCaja = new MovimientoCaja();
        reversoCaja.setTipo(TipoMovimientoCaja.REVERSO);
        reversoCaja.setFecha(LocalDate.now(clock));
        reversoCaja.setImporte(original.getImporte());
        reversoCaja.setMetodoPago(original.getMetodoPago());
        reversoCaja.setPago(pago);
        reversoCaja.setMovimientoRevertido(original);
        reversoCaja.setUsuario(usuario);
        reversoCaja.setIdempotencyKey("anulacion-pago:" + request.idempotencyKey());
        reversoCaja.setMotivo(request.motivo());
        movimientosCaja.save(reversoCaja);

        for (MovimientoCredito originalCredito : creditosPago) {
            MovimientoCredito reversoCredito = new MovimientoCredito();
            reversoCredito.setAlumno(pago.getAlumno());
            reversoCredito.setTipo(TipoMovimientoCredito.REVERSO);
            reversoCredito.setImporte(originalCredito.getImporte());
            reversoCredito.setPago(pago);
            reversoCredito.setMovimientoRevertido(originalCredito);
            reversoCredito.setUsuario(usuario);
            reversoCredito.setIdempotencyKey("anulacion-credito:" + request.idempotencyKey());
            reversoCredito.setRequestHash(RequestHash.sha256(
                    "ANULAR_CREDITO_PAGO", originalCredito.getId().toString(), request.motivo()));
            reversoCredito.setMotivo(request.motivo());
            movimientosCredito.save(reversoCredito);
        }

        pago.setEstado(EstadoPago.ANULADO);
        pago.setMotivoAnulacion(request.motivo());
        pago.setFechaAnulacion(clock.instant());
        pago.setReversalIdempotencyKey(request.idempotencyKey());
        pago.setReversalRequestHash(reversalHash);
        log.info("Pago anulado id={} alumnoId={}", pago.getId(), pago.getAlumno().getId());
        return respuesta(pago);
    }

    @Transactional(readOnly = true)
    public PagoResponse obtenerPagoPorId(Long id) {
        return respuesta(pagos.findById(id).orElseThrow(() -> new EntityNotFoundException("Pago no encontrado")));
    }

    @Transactional(readOnly = true)
    public Page<PagoResumenResponse> listarPagosPorAlumno(Long alumnoId, Pageable pageable) {
        return pagos.findByAlumnoId(alumnoId, pageable)
                .map(p -> new PagoResumenResponse(p.getId(), p.getFecha(), decimal(p.getMontoRecibido()), p.getEstado().name()));
    }

    private Usuario usuarioActivo(Usuario principal) {
        if (principal == null || principal.getId() == null) {
            throw new OperacionNoPermitidaException("Usuario autenticado requerido");
        }
        return usuarios.findById(principal.getId())
                .filter(u -> Boolean.TRUE.equals(u.getActivo()))
                .orElseThrow(() -> new OperacionNoPermitidaException("El usuario está inactivo"));
    }

    private void validarCargo(Alumno alumno, Cargo cargo) {
        if (!cargo.getAlumno().getId().equals(alumno.getId())) {
            throw new OperacionNoPermitidaException("El cargo no pertenece al alumno del pago");
        }
        if (cargo.getEstado() == EstadoCargo.ANULADO || cargo.getEstado() == EstadoCargo.PAGADO) {
            throw new OperacionNoPermitidaException("El cargo " + cargo.getId() + " no admite aplicaciones");
        }
    }

    private PagoResponse validarReintento(Pago pago, String hash) {
        if (!pago.getRequestHash().equals(hash)) {
            throw new OperacionNoPermitidaException("La idempotency key ya fue usada con otro contenido");
        }
        return respuesta(pago);
    }

    private PagoResponse respuesta(Pago pago) {
        List<AplicacionPagoResponse> detalle = aplicaciones.findByPagoIdOrderById(pago.getId()).stream()
                .map(a -> new AplicacionPagoResponse(
                        a.getId(),
                        a.getCargo().getId(),
                        decimal(a.getImporteAplicado()),
                        a.getEstado().name(),
                        decimal(cargoServicio.saldo(a.getCargo()))))
                .toList();
        BigDecimal credito = movimientosCredito.findByPagoId(pago.getId()).stream()
                .map(m -> m.getTipo() == TipoMovimientoCredito.GENERACION ? m.getImporte() : m.getImporte().negate())
                .reduce(CERO, BigDecimal::add);
        return new PagoResponse(
                pago.getId(), pago.getAlumno().getId(), pago.getMetodoPago().getId(), pago.getUsuario().getId(),
                pago.getFecha(), decimal(pago.getMontoRecibido()), pago.getEstado().name(), pago.getIdempotencyKey(),
                pago.getObservaciones(), decimal(credito), detalle);
    }

    private static BigDecimal monedaPositiva(String valor, String campo) {
        try {
            BigDecimal normalizado = new BigDecimal(valor).setScale(2, RoundingMode.UNNECESSARY);
            if (normalizado.signum() <= 0) {
                throw new IllegalArgumentException(campo + " debe ser mayor que cero");
            }
            return normalizado;
        } catch (ArithmeticException | NumberFormatException e) {
            throw new IllegalArgumentException(campo + " debe tener como máximo dos decimales");
        }
    }

    private static String decimal(BigDecimal valor) {
        return valor.setScale(2, RoundingMode.UNNECESSARY).toPlainString();
    }

    private static String hash(PagoRegistroRequest request) {
        String aplicaciones = request.aplicaciones().stream()
                .sorted(Comparator.comparing(AplicacionPagoRequest::cargoId))
                .map(a -> a.cargoId() + ":" + monedaPositiva(a.importe(), "aplicaciones.importe").toPlainString())
                .reduce((a, b) -> a + "," + b).orElse("");
        String canonico = request.alumnoId() + "|" + request.metodoPagoId() + "|"
                + monedaPositiva(request.montoRecibido(), "montoRecibido").toPlainString() + "|"
                + aplicaciones + "|" + request.generarCredito() + "|"
                + (request.observaciones() == null ? "" : request.observaciones());
        return RequestHash.sha256("REGISTRAR_PAGO", canonico);
    }
}
