package gestudio.servicios.stock;

import jakarta.persistence.EntityNotFoundException;
import gestudio.dto.cargo.response.CargoResponse;
import gestudio.dto.stock.StockMapper;
import gestudio.dto.stock.request.ReversionStockRequest;
import gestudio.dto.stock.request.StockRegistroRequest;
import gestudio.dto.stock.request.VentaStockRequest;
import gestudio.dto.stock.response.StockResponse;
import gestudio.entidades.Alumno;
import gestudio.entidades.Cargo;
import gestudio.entidades.EstadoCargo;
import gestudio.entidades.EstadoVentaStock;
import gestudio.entidades.MovimientoStock;
import gestudio.entidades.Stock;
import gestudio.entidades.TipoMovimientoStock;
import gestudio.entidades.Usuario;
import gestudio.entidades.VentaStock;
import gestudio.infra.errores.SinStockException;
import gestudio.infra.errores.TratadorDeErrores.OperacionNoPermitidaException;
import gestudio.infra.idempotencia.RequestHash;
import gestudio.repositorios.AlumnoRepositorio;
import gestudio.repositorios.CargoRepositorio;
import gestudio.repositorios.MovimientoStockRepositorio;
import gestudio.repositorios.StockRepositorio;
import gestudio.repositorios.UsuarioRepositorio;
import gestudio.repositorios.VentaStockRepositorio;
import gestudio.servicios.cargo.CargoServicio;
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
import java.util.List;
import java.util.Locale;

@Service
public class StockServicio {
    private static final Logger log = LoggerFactory.getLogger(StockServicio.class);
    private final StockRepositorio stocks;
    private final VentaStockRepositorio ventas;
    private final MovimientoStockRepositorio movimientos;
    private final AlumnoRepositorio alumnos;
    private final UsuarioRepositorio usuarios;
    private final CargoRepositorio cargos;
    private final CargoServicio cargoServicio;
    private final StockMapper mapper;
    private final Clock clock;

    public StockServicio(StockRepositorio stocks,
                         VentaStockRepositorio ventas,
                         MovimientoStockRepositorio movimientos,
                         AlumnoRepositorio alumnos,
                         UsuarioRepositorio usuarios,
                         CargoRepositorio cargos,
                         CargoServicio cargoServicio,
                         StockMapper mapper,
                         Clock clock) {
        this.stocks = stocks;
        this.ventas = ventas;
        this.movimientos = movimientos;
        this.alumnos = alumnos;
        this.usuarios = usuarios;
        this.cargos = cargos;
        this.cargoServicio = cargoServicio;
        this.mapper = mapper;
        this.clock = clock;
    }

    @Transactional
    public StockResponse crearStock(StockRegistroRequest request, Usuario principal) {
        if (stocks.findByNombreIgnoreCase(request.nombre().trim()).isPresent()) {
            throw new OperacionNoPermitidaException("Ya existe un producto con ese nombre");
        }
        Usuario usuario = usuarioActivo(principal);
        Stock stock = mapper.toEntity(request);
        stock.setNombre(request.nombre().trim().toUpperCase(Locale.ROOT));
        stock.setPrecio(monedaNoNegativa(request.precio()));
        stock.setStock(request.stock());
        stocks.save(stock);
        if (request.stock() > 0) {
            MovimientoStock ingreso = new MovimientoStock();
            ingreso.setStock(stock);
            ingreso.setTipo(TipoMovimientoStock.INGRESO);
            ingreso.setCantidad(request.stock());
            ingreso.setUsuario(usuario);
            ingreso.setIdempotencyKey("stock-inicial:" + request.idempotencyKey());
            ingreso.setMotivo("STOCK_INICIAL");
            movimientos.save(ingreso);
        }
        log.info("Producto de stock creado id={} cantidad={}", stock.getId(), stock.getStock());
        return respuesta(stock);
    }

    @Transactional(readOnly = true)
    public Page<StockResponse> listarStocks(Pageable pageable) {
        return stocks.findAll(pageable).map(this::respuesta);
    }

    @Transactional(readOnly = true)
    public List<StockResponse> listarStocksActivos() {
        return stocks.findByActivoTrue().stream().map(this::respuesta).toList();
    }

    @Transactional(readOnly = true)
    public StockResponse obtenerStockPorId(Long id) {
        return respuesta(stocks.findById(id).orElseThrow(() -> new EntityNotFoundException("Stock no encontrado")));
    }

    @Transactional
    public StockResponse actualizarStock(Long id, StockRegistroRequest request) {
        Stock stock = stocks.findActivoByIdForUpdate(id)
                .orElseThrow(() -> new EntityNotFoundException("Stock no encontrado"));
        if (!stock.getStock().equals(request.stock())) {
            throw new OperacionNoPermitidaException("La cantidad se modifica mediante movimientos de stock");
        }
        mapper.updateEntityFromRequest(request, stock);
        stock.setNombre(request.nombre().trim().toUpperCase(Locale.ROOT));
        stock.setPrecio(monedaNoNegativa(request.precio()));
        return respuesta(stock);
    }

    @Transactional
    public void eliminarStock(Long id) {
        Stock stock = stocks.findById(id).orElseThrow(() -> new EntityNotFoundException("Stock no encontrado"));
        stock.setActivo(false);
    }

    @Transactional
    public CargoResponse vender(VentaStockRequest request, Usuario principal) {
        String requestHash = RequestHash.sha256("VENDER_STOCK", request.alumnoId().toString(),
                request.stockId().toString(), request.cantidad().toString(), request.fechaVencimiento().toString());
        VentaStock previa = ventas.findByIdempotencyKey(request.idempotencyKey()).orElse(null);
        if (previa != null) {
            if (!requestHash.equals(previa.getRequestHash())) {
                throw new OperacionNoPermitidaException("La idempotency key ya fue usada con otro contenido");
            }
            return cargoServicio.obtener(cargos.findByVentaStockId(previa.getId()).orElseThrow().getId());
        }
        Alumno alumno = alumnos.findActivoByIdForUpdate(request.alumnoId())
                .orElseThrow(() -> new OperacionNoPermitidaException("El alumno no existe o está inactivo"));
        previa = ventas.findByIdempotencyKey(request.idempotencyKey()).orElse(null);
        if (previa != null) {
            if (!requestHash.equals(previa.getRequestHash())) {
                throw new OperacionNoPermitidaException("La idempotency key ya fue usada con otro contenido");
            }
            return cargoServicio.obtener(cargos.findByVentaStockId(previa.getId()).orElseThrow().getId());
        }
        Usuario usuario = usuarioActivo(principal);
        Stock stock = stocks.findActivoByIdForUpdate(request.stockId())
                .orElseThrow(() -> new EntityNotFoundException("Stock no encontrado"));
        if (Boolean.TRUE.equals(stock.getRequiereControlDeStock()) && stock.getStock() < request.cantidad()) {
            throw new SinStockException("Stock insuficiente para el producto " + stock.getNombre());
        }
        VentaStock venta = new VentaStock();
        venta.setAlumno(alumno);
        venta.setStock(stock);
        venta.setCantidad(request.cantidad());
        venta.setPrecioUnitario(stock.getPrecio());
        venta.setFecha(LocalDate.now(clock));
        venta.setEstado(EstadoVentaStock.REGISTRADA);
        venta.setIdempotencyKey(request.idempotencyKey());
        venta.setRequestHash(requestHash);
        ventas.save(venta);

        if (Boolean.TRUE.equals(stock.getRequiereControlDeStock())) {
            stock.setStock(stock.getStock() - request.cantidad());
        }
        MovimientoStock salida = new MovimientoStock();
        salida.setStock(stock);
        salida.setTipo(TipoMovimientoStock.VENTA);
        salida.setCantidad(request.cantidad());
        salida.setVentaStock(venta);
        salida.setUsuario(usuario);
        salida.setIdempotencyKey("venta:" + request.idempotencyKey());
        movimientos.save(salida);

        Cargo cargo = cargoServicio.crearParaVenta(venta,
                stock.getPrecio().multiply(BigDecimal.valueOf(request.cantidad())), request.fechaVencimiento());
        log.info("Venta de stock registrada id={} stockId={} cantidad={}", venta.getId(), stock.getId(), venta.getCantidad());
        return cargoServicio.obtener(cargo.getId());
    }

    @Transactional
    public CargoResponse revertirVenta(Long ventaId, ReversionStockRequest request, Usuario principal) {
        String reversalHash = RequestHash.sha256("REVERTIR_VENTA_STOCK", ventaId.toString(), request.motivo());
        VentaStock venta = ventas.findByIdForUpdate(ventaId)
                .orElseThrow(() -> new EntityNotFoundException("Venta no encontrada"));
        if (venta.getEstado() == EstadoVentaStock.ANULADA) {
            if (request.idempotencyKey().equals(venta.getReversalIdempotencyKey())) {
                if (!reversalHash.equals(venta.getReversalRequestHash())) {
                    throw new OperacionNoPermitidaException("La idempotency key ya fue usada con otro contenido");
                }
                return cargoServicio.obtener(cargos.findByVentaStockId(ventaId).orElseThrow().getId());
            }
            throw new OperacionNoPermitidaException("La venta ya fue anulada");
        }
        Usuario usuario = usuarioActivo(principal);
        Stock stock = stocks.findActivoByIdForUpdate(venta.getStock().getId())
                .orElseThrow(() -> new EntityNotFoundException("Stock no encontrado"));
        Cargo cargo = cargos.findByVentaStockId(ventaId).orElseThrow(() -> new IllegalStateException("Venta sin cargo"));
        if (cargo.getEstado() != EstadoCargo.PENDIENTE) {
            throw new OperacionNoPermitidaException("Primero debe anularse el pago aplicado a la venta");
        }
        MovimientoStock original = movimientos.findByVentaStockIdAndTipo(ventaId, TipoMovimientoStock.VENTA)
                .orElseThrow(() -> new IllegalStateException("Venta sin movimiento de stock"));
        MovimientoStock reverso = new MovimientoStock();
        reverso.setStock(stock);
        reverso.setTipo(TipoMovimientoStock.REVERSO);
        reverso.setCantidad(venta.getCantidad());
        reverso.setVentaStock(venta);
        reverso.setMovimientoRevertido(original);
        reverso.setUsuario(usuario);
        reverso.setIdempotencyKey("reversion-venta:" + request.idempotencyKey());
        reverso.setMotivo(request.motivo());
        movimientos.save(reverso);
        if (Boolean.TRUE.equals(stock.getRequiereControlDeStock())) {
            stock.setStock(stock.getStock() + venta.getCantidad());
        }
        venta.setEstado(EstadoVentaStock.ANULADA);
        venta.setReversalIdempotencyKey(request.idempotencyKey());
        venta.setReversalRequestHash(reversalHash);
        cargo.setEstado(EstadoCargo.ANULADO);
        return cargoServicio.obtener(cargo.getId());
    }

    @Transactional(readOnly = true)
    public boolean obtenerStockPorNombre(String nombre) {
        return stocks.findByNombreIgnoreCase(nombre.trim()).isPresent();
    }

    private Usuario usuarioActivo(Usuario principal) {
        if (principal == null || principal.getId() == null) {
            throw new OperacionNoPermitidaException("Usuario autenticado requerido");
        }
        return usuarios.findById(principal.getId()).filter(u -> Boolean.TRUE.equals(u.getActivo()))
                .orElseThrow(() -> new OperacionNoPermitidaException("El usuario está inactivo"));
    }

    private StockResponse respuesta(Stock stock) {
        return new StockResponse(stock.getId(), stock.getNombre(), decimal(stock.getPrecio()), stock.getStock(),
                stock.getRequiereControlDeStock(), stock.getActivo(), stock.getCodigoBarras());
    }

    private static BigDecimal monedaNoNegativa(BigDecimal valor) {
        try {
            BigDecimal normalizado = valor.setScale(2, RoundingMode.UNNECESSARY);
            if (normalizado.signum() < 0) {
                throw new IllegalArgumentException("El precio no puede ser negativo");
            }
            return normalizado;
        } catch (ArithmeticException e) {
            throw new IllegalArgumentException("El precio debe tener como máximo dos decimales");
        }
    }

    private static String decimal(BigDecimal importe) {
        return importe.setScale(2, RoundingMode.UNNECESSARY).toPlainString();
    }
}
