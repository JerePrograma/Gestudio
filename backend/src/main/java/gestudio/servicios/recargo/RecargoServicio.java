package gestudio.servicios.recargo;

import jakarta.persistence.EntityNotFoundException;
import gestudio.dto.recargo.request.RecargoRegistroRequest;
import gestudio.dto.recargo.response.RecargoResponse;
import gestudio.entidades.Cargo;
import gestudio.entidades.EstadoCargo;
import gestudio.entidades.Recargo;
import gestudio.entidades.TipoCargo;
import gestudio.repositorios.CargoRepositorio;
import gestudio.repositorios.RecargoRepositorio;
import gestudio.servicios.cargo.CargoServicio;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Clock;
import java.time.LocalDate;
import java.util.List;

@Service
public class RecargoServicio {
    private static final Logger log = LoggerFactory.getLogger(RecargoServicio.class);
    private final RecargoRepositorio recargos;
    private final CargoRepositorio cargos;
    private final CargoServicio cargoServicio;
    private final Clock clock;

    public RecargoServicio(RecargoRepositorio recargos, CargoRepositorio cargos,
                           CargoServicio cargoServicio, Clock clock) {
        this.recargos = recargos;
        this.cargos = cargos;
        this.cargoServicio = cargoServicio;
        this.clock = clock;
    }

    @Transactional
    public RecargoResponse crearRecargo(RecargoRegistroRequest request) {
        Recargo recargo = new Recargo();
        aplicar(request, recargo);
        return respuesta(recargos.save(recargo));
    }

    @Transactional(readOnly = true)
    public List<RecargoResponse> listarRecargos() {
        return recargos.findAll().stream().map(this::respuesta).toList();
    }

    @Transactional(readOnly = true)
    public RecargoResponse obtenerRecargo(Long id) {
        return respuesta(obtener(id));
    }

    @Transactional
    public RecargoResponse actualizarRecargo(Long id, RecargoRegistroRequest request) {
        Recargo recargo = obtener(id);
        aplicar(request, recargo);
        return respuesta(recargo);
    }

    @Transactional
    public void eliminarRecargo(Long id) {
        obtener(id).setActivo(false);
    }

    @Transactional
    public void aplicarRecargosAutomaticos() {
        LocalDate hoy = LocalDate.now(clock);
        List<Cargo> vencidos = cargos.findByTipoAndEstadoInAndFechaVencimientoBeforeOrderById(
                TipoCargo.MENSUALIDAD, List.of(EstadoCargo.PENDIENTE, EstadoCargo.PARCIAL), hoy);
        int creados = 0;
        for (Cargo origen : vencidos) {
            Recargo regla = origen.getMensualidad().getRecargo();
            if (regla == null || !Boolean.TRUE.equals(regla.getActivo())
                    || regla.getDiaDelMesAplicacion() == null
                    || hoy.getDayOfMonth() < regla.getDiaDelMesAplicacion()) {
                continue;
            }
            BigDecimal importe = origen.getImporteOriginal()
                    .multiply(regla.getPorcentaje())
                    .divide(new BigDecimal("100"), 2, RoundingMode.HALF_UP)
                    .add(regla.getValorFijo()).setScale(2, RoundingMode.HALF_UP);
            if (importe.signum() > 0) {
                cargoServicio.crearRecargo(origen, importe, regla.getDescripcion(),
                        "recargo:" + origen.getId() + ":" + regla.getId());
                creados++;
            }
        }
        log.info("Recargos automáticos procesados vencidos={} creados={}", vencidos.size(), creados);
    }

    private void aplicar(RecargoRegistroRequest request, Recargo recargo) {
        recargo.setDescripcion(request.descripcion().trim());
        recargo.setPorcentaje(porcentaje(request.porcentaje()));
        recargo.setValorFijo(moneda(request.valorFijo()));
        recargo.setDiaDelMesAplicacion(request.diaDelMesAplicacion());
        recargo.setActivo(request.activo() == null || request.activo());
    }

    private Recargo obtener(Long id) {
        return recargos.findById(id).orElseThrow(() -> new EntityNotFoundException("Recargo no encontrado"));
    }

    private RecargoResponse respuesta(Recargo r) {
        return new RecargoResponse(r.getId(), r.getDescripcion(), r.getPorcentaje().toPlainString(),
                r.getValorFijo().toPlainString(), r.getDiaDelMesAplicacion(), r.getActivo());
    }

    private static BigDecimal porcentaje(BigDecimal valor) {
        BigDecimal normalizado = valor.setScale(4, RoundingMode.UNNECESSARY);
        if (normalizado.signum() < 0 || normalizado.compareTo(new BigDecimal("100")) > 0) {
            throw new IllegalArgumentException("El porcentaje debe estar entre 0 y 100");
        }
        return normalizado;
    }

    private static BigDecimal moneda(BigDecimal valor) {
        BigDecimal normalizado = valor.setScale(2, RoundingMode.UNNECESSARY);
        if (normalizado.signum() < 0) {
            throw new IllegalArgumentException("El valor fijo no puede ser negativo");
        }
        return normalizado;
    }
}
