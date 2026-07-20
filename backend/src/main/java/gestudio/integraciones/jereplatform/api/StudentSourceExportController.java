package gestudio.integraciones.jereplatform.api;

import gestudio.entidades.Usuario;
import gestudio.integraciones.jereplatform.application.SignedStudentSourceExportPage;
import gestudio.integraciones.jereplatform.application.StudentSourceExportService;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/integraciones/jere-platform/estudiantes")
public class StudentSourceExportController {
    private final StudentSourceExportService exports;

    public StudentSourceExportController(StudentSourceExportService exports) {
        this.exports = exports;
    }

    @PostMapping("/snapshots")
    public ResponseEntity<byte[]> createSnapshot(@AuthenticationPrincipal Usuario actor) {
        return response(exports.createSnapshot(actor));
    }

    @GetMapping("/snapshots/{checkpoint}")
    public ResponseEntity<byte[]> page(
            @PathVariable String checkpoint,
            @RequestParam(required = false) String cursor,
            @AuthenticationPrincipal Usuario actor
    ) {
        return response(exports.page(checkpoint, cursor, actor));
    }

    private static ResponseEntity<byte[]> response(SignedStudentSourceExportPage page) {
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        headers.setCacheControl(CacheControl.noStore());
        headers.set("X-Party-Source-Type", StudentSourceExportService.SOURCE_TYPE);
        headers.set("X-Party-Export-Signature", page.signature());
        headers.set("X-Party-Export-Checkpoint", page.checkpoint().toString());
        headers.set("X-Party-Export-Page", Integer.toString(page.pageNumber()));
        headers.set("X-Party-Export-Page-Count", Integer.toString(page.pageCount()));
        headers.set("X-Correlation-ID", page.correlationId().toString());
        if (page.nextCursor() != null) {
            headers.set("X-Party-Export-Next-Cursor", page.nextCursor());
        }
        return ResponseEntity.ok().headers(headers).body(page.payload());
    }
}
