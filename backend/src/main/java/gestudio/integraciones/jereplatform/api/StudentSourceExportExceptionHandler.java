package gestudio.integraciones.jereplatform.api;

import gestudio.infra.errores.ApiErrorResponse;
import gestudio.integraciones.jereplatform.application.StudentSourceExportException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.time.Clock;
import java.util.List;

@RestControllerAdvice(assignableTypes = StudentSourceExportController.class)
public class StudentSourceExportExceptionHandler {
    private final Clock clock;

    public StudentSourceExportExceptionHandler(Clock clock) {
        this.clock = clock;
    }

    @ExceptionHandler(StudentSourceExportException.class)
    public ResponseEntity<ApiErrorResponse> handle(StudentSourceExportException exception) {
        HttpStatus status = switch (exception.code()) {
            case TENANT_MAPPING_DISABLED, TENANT_MAPPING_MISSING, SOURCE_SECRET_MISSING,
                    SOURCE_SECRET_TOO_SHORT -> HttpStatus.SERVICE_UNAVAILABLE;
            case SNAPSHOT_NOT_FOUND -> HttpStatus.NOT_FOUND;
            case CURSOR_INVALID, TENANT_MAPPING_INVALID -> HttpStatus.BAD_REQUEST;
            case PAGE_TOO_LARGE, PAYLOAD_TOO_LARGE, STUDENT_REFERENCE_INVALID ->
                    HttpStatus.UNPROCESSABLE_ENTITY;
            case SERIALIZATION_FAILED, SIGNATURE_FAILED -> HttpStatus.INTERNAL_SERVER_ERROR;
        };
        return ResponseEntity.status(status).body(new ApiErrorResponse(
                clock.instant(),
                status.value(),
                exception.code().value(),
                "No se pudo generar la exportación solicitada",
                List.of()
        ));
    }
}
