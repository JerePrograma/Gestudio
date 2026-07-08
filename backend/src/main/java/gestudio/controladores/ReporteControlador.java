package gestudio.controladores;

import jakarta.validation.Valid;
import gestudio.dto.reporte.request.ReporteLiquidacionRequest;
import gestudio.dto.reporte.response.ReporteMensualidadResponse;
import gestudio.servicios.reporte.ReporteServicio;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDate;
import java.util.List;

@RestController
@RequestMapping("/api/reportes")
public class ReporteControlador {
    private final ReporteServicio reportes;

    public ReporteControlador(ReporteServicio reportes) {
        this.reportes = reportes;
    }

    @GetMapping("/mensualidades")
    public List<ReporteMensualidadResponse> buscar(
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate desde,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate hasta,
            @RequestParam(required = false) Long disciplinaId,
            @RequestParam(required = false) Long profesorId) {
        return reportes.buscar(desde, hasta, disciplinaId, profesorId);
    }

    @PostMapping("/mensualidades/exportar")
    public ResponseEntity<byte[]> exportar(@Valid @RequestBody ReporteLiquidacionRequest request) {
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_PDF);
        headers.setContentDisposition(ContentDisposition.attachment().filename("liquidacion.pdf").build());
        return ResponseEntity.ok().headers(headers).body(reportes.exportar(request));
    }
}
