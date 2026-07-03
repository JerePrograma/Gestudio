package ledance.servicios.reporte;

import ledance.dto.reporte.request.ReporteLiquidacionRequest;
import ledance.dto.reporte.response.ReporteMensualidadResponse;
import ledance.entidades.Cargo;
import ledance.entidades.TipoCargo;
import ledance.repositorios.CargoRepositorio;
import ledance.servicios.cargo.CargoSaldoServicio;
import ledance.servicios.cargo.SaldoCargo;
import ledance.servicios.pdfs.PdfService;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;

@Service
public class ReporteServicio {
    private final CargoRepositorio cargos;
    private final CargoSaldoServicio saldos;
    private final PdfService pdf;

    public ReporteServicio(CargoRepositorio cargos, CargoSaldoServicio saldos, PdfService pdf) {
        this.cargos = cargos;
        this.saldos = saldos;
        this.pdf = pdf;
    }

    @Transactional(readOnly = true)
    public List<ReporteMensualidadResponse> buscar(LocalDate desde, LocalDate hasta,
                                                   Long disciplinaId, Long profesorId) {
        if (hasta.isBefore(desde)) {
            throw new IllegalArgumentException("La fecha fin no puede ser anterior a la fecha inicio");
        }
        List<Cargo> encontrados = cargos.findMensualidadesParaReporte(
                TipoCargo.MENSUALIDAD, desde, hasta, disciplinaId, profesorId);
        Map<Long, SaldoCargo> porCargo = saldos.calcularBatch(encontrados.stream().map(Cargo::getId).toList());
        return encontrados.stream().map(cargo -> respuesta(cargo, porCargo.get(cargo.getId()))).toList();
    }

    @Transactional(readOnly = true)
    public byte[] exportar(ReporteLiquidacionRequest request) {
        BigDecimal porcentaje = request.porcentajeEscuela().setScale(4, RoundingMode.UNNECESSARY);
        if (porcentaje.signum() < 0 || porcentaje.compareTo(new BigDecimal("100")) > 0) {
            throw new IllegalArgumentException("El porcentaje debe estar entre 0 y 100");
        }
        return pdf.generarLiquidacionProfesorPdf(buscar(request.fechaInicio(), request.fechaFin(),
                request.disciplinaId(), request.profesorId()), request.fechaInicio(), request.fechaFin(), porcentaje);
    }

    private ReporteMensualidadResponse respuesta(Cargo cargo, SaldoCargo saldo) {
        var disciplina = cargo.getMensualidad().getInscripcion().getDisciplina();
        return new ReporteMensualidadResponse(cargo.getId(), cargo.getFechaEmision(),
                (cargo.getAlumno().getApellido() + " " + cargo.getAlumno().getNombre()).trim(),
                disciplina.getNombre(),
                (disciplina.getProfesor().getApellido() + " " + disciplina.getProfesor().getNombre()).trim(),
                decimal(saldo.importeOriginal()), decimal(saldo.aplicadoTotal()),
                decimal(saldo.saldo()), cargo.getEstado().name());
    }

    private static String decimal(BigDecimal valor) {
        return valor.setScale(2, RoundingMode.UNNECESSARY).toPlainString();
    }
}
