package gestudio.controladores;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.PositiveOrZero;
import gestudio.dto.PageResponse;
import gestudio.dto.pago.request.PagoAnulacionRequest;
import gestudio.dto.pago.request.PagoRegistroRequest;
import gestudio.dto.pago.response.PagoResponse;
import gestudio.dto.pago.response.PagoResumenResponse;
import gestudio.entidades.Usuario;
import gestudio.infra.configuracion.AppProperties;
import gestudio.repositorios.ReciboRepositorio;
import gestudio.servicios.pago.PagoServicio;
import gestudio.servicios.pdfs.ReciboPathResolver;
import org.springframework.core.io.ByteArrayResource;
import org.springframework.core.io.Resource;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

@RestController
@RequestMapping("/api/pagos")
@Validated
public class PagoControlador {

    private final PagoServicio pagos;
    private final ReciboRepositorio recibos;
    private final AppProperties appProperties;

    public PagoControlador(PagoServicio pagos,
                           ReciboRepositorio recibos,
                           AppProperties appProperties) {
        this.pagos = pagos;
        this.recibos = recibos;
        this.appProperties = appProperties;
    }

    @PostMapping
    public ResponseEntity<PagoResponse> registrar(@Valid @RequestBody PagoRegistroRequest request,
                                                  @AuthenticationPrincipal Usuario usuario) {
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(pagos.registrarPago(request, usuario));
    }

    @PostMapping("/{id}/anulacion")
    public PagoResponse anular(@PathVariable Long id,
                               @Valid @RequestBody PagoAnulacionRequest request,
                               @AuthenticationPrincipal Usuario usuario) {
        return pagos.anularPago(id, request, usuario);
    }

    @GetMapping("/{id}")
    public PagoResponse obtener(@PathVariable Long id) {
        return pagos.obtenerPagoPorId(id);
    }

    @GetMapping("/alumno/{alumnoId}")
    public PageResponse<PagoResumenResponse> listarPorAlumno(
            @PathVariable Long alumnoId,
            @RequestParam(defaultValue = "0") @PositiveOrZero int page,
            @RequestParam(defaultValue = "50") @Min(1) @Max(200) int size) {
        return PageResponse.from(pagos.listarPagosPorAlumno(
                alumnoId,
                PageRequest.of(page, size, Sort.by(Sort.Direction.DESC, "fecha", "id"))
        ));
    }

    @GetMapping("/recibo/{pagoId}")
    public ResponseEntity<Resource> descargarRecibo(@PathVariable Long pagoId) throws IOException {
        var recibo = recibos.findByPagoId(pagoId).orElse(null);

        if (recibo == null || recibo.getStorageKey() == null) {
            return ResponseEntity.notFound().build();
        }

        Path archivo = ReciboPathResolver.resolveExistingFile(
                appProperties.receiptsPath(), recibo.getStorageKey());
        if (archivo == null) {
            return ResponseEntity.notFound().build();
        }

        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_PDF);
        headers.setContentDisposition(ContentDisposition.inline()
                .filename("recibo_" + pagoId + ".pdf")
                .build());

        return new ResponseEntity<>(
                new ByteArrayResource(Files.readAllBytes(archivo)),
                headers,
                HttpStatus.OK
        );
    }
}
