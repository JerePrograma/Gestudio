package gestudio.servicios.cargo;

import jakarta.persistence.EntityNotFoundException;
import gestudio.dto.cargo.request.CargoConceptoRequest;
import gestudio.dto.cargo.response.CargoResponse;
import gestudio.entidades.Alumno;
import gestudio.entidades.Cargo;
import gestudio.entidades.Concepto;
import gestudio.entidades.EstadoCargo;
import gestudio.entidades.Matricula;
import gestudio.entidades.Mensualidad;
import gestudio.entidades.TipoCargo;
import gestudio.entidades.Usuario;
import gestudio.entidades.VentaStock;
import gestudio.infra.errores.TratadorDeErrores.OperacionNoPermitidaException;
import gestudio.infra.idempotencia.IdempotencyLockService;
import gestudio.infra.seguridad.RbacService;
import gestudio.repositorios.AlumnoRepositorio;
import gestudio.repositorios.CargoRepositorio;
import gestudio.repositorios.ConceptoRepositorio;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Clock;
import java.time.LocalDate;
import java.util.List;

import static gestudio.infra.seguridad.PermissionCodes.PERM_PAGOS_REGISTRAR;

@Service
public class CargoServicio {

    private final CargoRepositorio cargos;
    private final AlumnoRepositorio alumnos;
    private final ConceptoRepositorio conceptos;
    private final CargoSaldoServicio saldos;
    private final Clock clock;
    private final RbacService rbac;
    private final IdempotencyLockService idempotencyLocks;

    public CargoServicio(CargoRepositorio cargos,
                         AlumnoRepositorio alumnos,
                         ConceptoRepositorio conceptos,
                         CargoSaldoServicio saldos,
                         Clock clock,
                         RbacService rbac,
                         IdempotencyLockService idempotencyLocks) {
        this.cargos = cargos;
        this.alumnos = alumnos;
        this.conceptos = conceptos;
        this.saldos = saldos;
        this.clock = clock;
        this.rbac = rbac;
        this.idempotencyLocks = idempotencyLocks;
    }

    @Transactional
    public CargoResponse crearPorConcepto(CargoConceptoRequest request, Usuario principal) {
        rbac.exigirPermiso(principal, PERM_PAGOS_REGISTRAR, "CREAR_CARGO_CONCEPTO");

        idempotencyLocks.lock("CREAR_CARGO_CONCEPTO", request.idempotencyKey());

        Cargo previo = cargos.findByIdempotencyKey(request.idempotencyKey()).orElse(null);
        if (previo != null) {
            if (!previo.getAlumno().getId().equals(request.alumnoId())
                    || previo.getConcepto() == null
                    || !previo.getConcepto().getId().equals(request.conceptoId())) {
                throw new OperacionNoPermitidaException("La idempotency key ya fue usada con otro cargo");
            }

            return respuesta(previo);
        }

        Alumno alumno = alumnos.findActivoByIdForUpdate(request.alumnoId())
                .orElseThrow(() -> new OperacionNoPermitidaException("El alumno no existe o está inactivo"));

        previo = cargos.findByIdempotencyKey(request.idempotencyKey()).orElse(null);
        if (previo != null) {
            if (!previo.getAlumno().getId().equals(request.alumnoId())
                    || previo.getConcepto() == null
                    || !previo.getConcepto().getId().equals(request.conceptoId())) {
                throw new OperacionNoPermitidaException("La idempotency key ya fue usada con otro cargo");
            }

            return respuesta(previo);
        }

        Concepto concepto = conceptos.findById(request.conceptoId())
                .filter(c -> Boolean.TRUE.equals(c.getActivo()))
                .orElseThrow(() -> new OperacionNoPermitidaException("El concepto no existe o está inactivo"));

        String descripcion = request.descripcion() == null || request.descripcion().isBlank()
                ? concepto.getDescripcion()
                : request.descripcion().trim();

        Cargo cargo = base(alumno, TipoCargo.CONCEPTO, descripcion, concepto.getPrecio(), request.fechaVencimiento());
        cargo.setConcepto(concepto);
        cargo.setIdempotencyKey(request.idempotencyKey());

        return respuesta(cargos.save(cargo));
    }

    @Transactional
    public Cargo crearParaMensualidad(Mensualidad mensualidad, BigDecimal importe) {
        idempotencyLocks.lock("CREAR_CARGO_MENSUALIDAD", mensualidad.getId().toString());

        return cargos.findByMensualidadId(mensualidad.getId()).orElseGet(() -> {
            Cargo cargo = base(
                    mensualidad.getInscripcion().getAlumno(),
                    TipoCargo.MENSUALIDAD,
                    mensualidad.getDescripcion(),
                    importe,
                    mensualidad.getFechaVencimiento()
            );
            cargo.setMensualidad(mensualidad);
            return cargos.save(cargo);
        });
    }

    @Transactional
    public Cargo crearParaMatricula(Matricula matricula, BigDecimal importe, LocalDate vencimiento) {
        idempotencyLocks.lock("CREAR_CARGO_MATRICULA", matricula.getId().toString());

        return cargos.findByMatriculaId(matricula.getId()).orElseGet(() -> {
            Cargo cargo = base(
                    matricula.getAlumno(),
                    TipoCargo.MATRICULA,
                    "MATRICULA " + matricula.getAnio(),
                    importe,
                    vencimiento
            );
            cargo.setMatricula(matricula);
            return cargos.save(cargo);
        });
    }

    @Transactional
    public Cargo crearParaVenta(VentaStock venta, BigDecimal importe, LocalDate vencimiento) {
        idempotencyLocks.lock("CREAR_CARGO_VENTA_STOCK", venta.getId().toString());

        return cargos.findByVentaStockId(venta.getId()).orElseGet(() -> {
            Cargo cargo = base(
                    venta.getAlumno(),
                    TipoCargo.VENTA_STOCK,
                    venta.getStock().getNombre() + " x" + venta.getCantidad(),
                    importe,
                    vencimiento
            );
            cargo.setVentaStock(venta);
            return cargos.save(cargo);
        });
    }

    @Transactional
    public Cargo crearRecargo(Cargo origen, BigDecimal importe, String descripcion, String idempotencyKey) {
        idempotencyLocks.lock("CREAR_CARGO_RECARGO", idempotencyKey);

        return cargos.findByIdempotencyKey(idempotencyKey).orElseGet(() -> {
            Cargo cargo = base(
                    origen.getAlumno(),
                    TipoCargo.RECARGO,
                    descripcion,
                    importe,
                    origen.getFechaVencimiento()
            );
            cargo.setCargoOrigen(origen);
            cargo.setIdempotencyKey(idempotencyKey);
            return cargos.save(cargo);
        });
    }

    @Transactional(readOnly = true)
    public Page<CargoResponse> listarPendientes(Long alumnoId, Pageable pageable) {
        return cargos.findByAlumnoIdAndEstadoIn(
                        alumnoId,
                        List.of(EstadoCargo.PENDIENTE, EstadoCargo.PARCIAL),
                        pageable
                )
                .map(this::respuesta);
    }

    @Transactional(readOnly = true)
    public Page<CargoResponse> listarVencidos(Pageable pageable) {
        return cargos.findByEstadoInAndFechaVencimientoBefore(
                        List.of(EstadoCargo.PENDIENTE, EstadoCargo.PARCIAL),
                        LocalDate.now(clock),
                        pageable
                )
                .map(this::respuesta);
    }

    @Transactional(readOnly = true)
    public CargoResponse obtener(Long id) {
        return respuesta(cargos.findById(id).orElseThrow(() -> new EntityNotFoundException("Cargo no encontrado")));
    }

    private Cargo base(Alumno alumno, TipoCargo tipo, String descripcion, BigDecimal importe, LocalDate vencimiento) {
        BigDecimal normalizado;

        try {
            normalizado = importe.setScale(2, RoundingMode.UNNECESSARY);
        } catch (ArithmeticException e) {
            throw new IllegalArgumentException("El importe del cargo debe tener como máximo dos decimales");
        }

        if (normalizado.signum() < 0) {
            throw new IllegalArgumentException("El importe del cargo no puede ser negativo");
        }

        Cargo cargo = new Cargo();
        cargo.setAlumno(alumno);
        cargo.setTipo(tipo);
        cargo.setDescripcion(descripcion);
        cargo.setImporteOriginal(normalizado);
        cargo.setFechaEmision(LocalDate.now(clock));
        cargo.setFechaVencimiento(vencimiento);
        cargo.setEstado(normalizado.signum() == 0 ? EstadoCargo.PAGADO : EstadoCargo.PENDIENTE);

        return cargo;
    }

    private CargoResponse respuesta(Cargo cargo) {
        SaldoCargo saldo = saldos.calcular(cargo);

        return new CargoResponse(
                cargo.getId(),
                cargo.getAlumno().getId(),
                cargo.getTipo().name(),
                cargo.getDescripcion(),
                decimal(saldo.importeOriginal()),
                decimal(saldo.aplicadoTotal()),
                decimal(saldo.saldo()),
                cargo.getFechaEmision(),
                cargo.getFechaVencimiento(),
                cargo.getEstado().name()
        );
    }

    public BigDecimal saldo(Cargo cargo) {
        return saldos.calcular(cargo).saldo();
    }

    public void actualizarEstado(Cargo cargo) {
        SaldoCargo saldo = saldos.calcular(cargo);

        if (cargo.getEstado() == EstadoCargo.ANULADO) {
            return;
        }

        cargo.setEstado(saldo.estadoEsperado());
    }

    private static String decimal(BigDecimal importe) {
        return importe.setScale(2, RoundingMode.UNNECESSARY).toPlainString();
    }
}
