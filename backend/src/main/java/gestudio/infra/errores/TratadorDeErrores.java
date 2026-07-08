package gestudio.infra.errores;

import jakarta.persistence.EntityNotFoundException;
import jakarta.validation.ConstraintViolationException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.orm.ObjectOptimisticLockingFailureException;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.AuthenticationException;
import org.springframework.web.HttpRequestMethodNotSupportedException;
import org.springframework.web.servlet.resource.NoResourceFoundException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.HttpServerErrorException;
import gestudio.infra.seguridad.InvalidTokenException;
import gestudio.infra.seguridad.RefreshTokenReuseException;
import gestudio.tarifas.application.TarifaDisciplinaServicio.TarifaHistoricaNoDefinidaException;
import gestudio.tarifas.application.CondicionEconomicaServicio.CondicionHistoricaNoDefinidaException;

import java.time.Clock;
import java.util.List;
import java.util.Locale;
import java.util.NoSuchElementException;

@RestControllerAdvice
public class TratadorDeErrores {

    private static final Logger log = LoggerFactory.getLogger(TratadorDeErrores.class);
    private final Clock clock;

    public TratadorDeErrores(Clock clock) {
        this.clock = clock;
    }

    @ExceptionHandler({EntityNotFoundException.class, RecursoNoEncontradoException.class,
            DisciplinaNotFoundException.class, ProfesorNotFoundException.class,
            NoSuchElementException.class, ResourceNotFoundException.class, NoResourceFoundException.class})
    public ResponseEntity<ApiErrorResponse> notFound(Exception exception) {
        log.warn("Recurso no encontrado type={}", exception.getClass().getSimpleName());
        return response(HttpStatus.NOT_FOUND, "NOT_FOUND", safeMessage(exception, "Recurso no encontrado"));
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ApiErrorResponse> validation(MethodArgumentNotValidException exception) {
        List<ApiErrorResponse.FieldViolation> fields = exception.getFieldErrors().stream()
                .map(error -> new ApiErrorResponse.FieldViolation(error.getField(), error.getDefaultMessage()))
                .toList();
        return response(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", "La solicitud contiene campos inválidos", fields);
    }

    @ExceptionHandler(MissingServletRequestParameterException.class)
    public ResponseEntity<ApiErrorResponse> missingParameter(MissingServletRequestParameterException exception) {
        return response(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", "Falta un parámetro requerido",
                List.of(new ApiErrorResponse.FieldViolation(exception.getParameterName(), "es requerido")));
    }

    @ExceptionHandler(ConstraintViolationException.class)
    public ResponseEntity<ApiErrorResponse> constraintValidation(ConstraintViolationException exception) {
        List<ApiErrorResponse.FieldViolation> fields = exception.getConstraintViolations().stream()
                .map(violation -> new ApiErrorResponse.FieldViolation(
                        violation.getPropertyPath().toString(), violation.getMessage()))
                .toList();
        return response(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", "La solicitud contiene parámetros inválidos", fields);
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<ApiErrorResponse> invalidArgument(IllegalArgumentException exception) {
        return response(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", safeMessage(exception, "Solicitud inválida"));
    }

    @ExceptionHandler({ErrorDeAutenticacionException.class, AuthenticationException.class})
    public ResponseEntity<ApiErrorResponse> unauthorized(RuntimeException exception) {
        log.warn("Autenticación rechazada type={}", exception.getClass().getSimpleName());
        return response(HttpStatus.UNAUTHORIZED, "UNAUTHORIZED", "Credenciales inválidas");
    }

    @ExceptionHandler(InvalidTokenException.class)
    public ResponseEntity<ApiErrorResponse> invalidToken(InvalidTokenException exception) {
        return response(HttpStatus.UNAUTHORIZED, "INVALID_TOKEN", "Token inválido o expirado");
    }

    @ExceptionHandler(RefreshTokenReuseException.class)
    public ResponseEntity<ApiErrorResponse> refreshReuse(RefreshTokenReuseException exception) {
        return response(HttpStatus.CONFLICT, "REFRESH_TOKEN_REUSE_DETECTED",
                "Se detectó reutilización del refresh token; la sesión fue revocada");
    }

    @ExceptionHandler({TarifaHistoricaNoDefinidaException.class, CondicionHistoricaNoDefinidaException.class})
    public ResponseEntity<ApiErrorResponse> historicalPricing(RuntimeException exception) {
        return response(HttpStatus.CONFLICT, "HISTORICAL_PRICING_NOT_DEFINED",
                safeMessage(exception, "No existe una tarifa histórica verificable"));
    }

    @ExceptionHandler(AccessDeniedException.class)
    public ResponseEntity<ApiErrorResponse> forbidden(AccessDeniedException exception) {
        return response(HttpStatus.FORBIDDEN, "FORBIDDEN", "Permisos insuficientes");
    }

    @ExceptionHandler(HttpRequestMethodNotSupportedException.class)
    public ResponseEntity<ApiErrorResponse> methodNotAllowed(HttpRequestMethodNotSupportedException exception) {
        return response(HttpStatus.METHOD_NOT_ALLOWED, "METHOD_NOT_ALLOWED", "Método HTTP no permitido");
    }

    @ExceptionHandler(OperacionNoPermitidaException.class)
    public ResponseEntity<ApiErrorResponse> businessConflict(OperacionNoPermitidaException exception) {
        return response(HttpStatus.CONFLICT, businessCode(exception.getMessage()),
                safeMessage(exception, "La operación entra en conflicto con el estado actual"));
    }

    @ExceptionHandler(SinStockException.class)
    public ResponseEntity<ApiErrorResponse> insufficientStock(SinStockException exception) {
        return response(HttpStatus.CONFLICT, "INSUFFICIENT_STOCK", safeMessage(exception, "Stock insuficiente"));
    }

    @ExceptionHandler(DataIntegrityViolationException.class)
    public ResponseEntity<ApiErrorResponse> dataConflict(DataIntegrityViolationException exception) {
        String detail = rootMessage(exception).toLowerCase(Locale.ROOT);
        String code = constraintCode(detail);
        log.warn("Conflicto de integridad code={}", code);
        return response(HttpStatus.CONFLICT, code, conflictMessage(code));
    }

    @ExceptionHandler(ObjectOptimisticLockingFailureException.class)
    public ResponseEntity<ApiErrorResponse> optimisticConflict(ObjectOptimisticLockingFailureException exception) {
        return response(HttpStatus.CONFLICT, "OPTIMISTIC_LOCK_CONFLICT",
                "El recurso fue modificado por otra operación; vuelva a cargarlo");
    }

    @ExceptionHandler({HttpClientErrorException.class, HttpServerErrorException.class})
    public ResponseEntity<ApiErrorResponse> externalFailure(Exception exception) {
        log.error("Fallo de dependencia externa type={}", exception.getClass().getSimpleName());
        return response(HttpStatus.BAD_GATEWAY, "EXTERNAL_SERVICE_ERROR", "Falló una dependencia externa");
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ApiErrorResponse> internalError(Exception exception) {
        log.error("Error interno type={}", exception.getClass().getSimpleName());
        return response(HttpStatus.INTERNAL_SERVER_ERROR, "INTERNAL_ERROR", "Ocurrió un error inesperado");
    }

    private ResponseEntity<ApiErrorResponse> response(HttpStatus status, String code, String message) {
        return response(status, code, message, List.of());
    }

    private ResponseEntity<ApiErrorResponse> response(HttpStatus status, String code, String message,
                                                       List<ApiErrorResponse.FieldViolation> fields) {
        return ResponseEntity.status(status).body(new ApiErrorResponse(
                clock.instant(), status.value(), code, message, fields));
    }

    private static String businessCode(String message) {
        String normalized = message == null ? "" : message.toLowerCase(Locale.ROOT);
        if (normalized.contains("idempotency")) return "IDEMPOTENCY_CONFLICT";
        if (normalized.contains("inscripción activa")) return "DUPLICATE_ACTIVE_ENROLLMENT";
        if (normalized.contains("sobrepago") || normalized.contains("supera el saldo")) return "OVERAPPLICATION";
        if (normalized.contains("crédito") && (normalized.contains("insuficiente") || normalized.contains("negativo"))) {
            return "INSUFFICIENT_CREDIT";
        }
        return "BUSINESS_CONFLICT";
    }

    private static String constraintCode(String detail) {
        if (detail.contains("idempotency")) return "IDEMPOTENCY_CONFLICT";
        if (detail.contains("uq_inscripciones_activas")) return "DUPLICATE_ACTIVE_ENROLLMENT";
        if (detail.contains("uq_mensualidades_periodo")) return "DUPLICATE_MONTHLY_FEE";
        if (detail.contains("uq_matriculas_periodo")) return "DUPLICATE_REGISTRATION";
        if (detail.contains("uq_disciplina_tarifas_inicio")) return "DUPLICATE_EFFECTIVE_DATE";
        if (detail.contains("uq_inscripcion_condicion_inicio")) return "DUPLICATE_EFFECTIVE_DATE";
        if (detail.contains("ck_aplicaciones") || detail.contains("ck_pagos_monto")) return "OVERAPPLICATION";
        if (detail.contains("ck_movimientos_credito")) return "INSUFFICIENT_CREDIT";
        if (detail.contains("ck_stocks") || detail.contains("ck_movimientos_stock")) return "INSUFFICIENT_STOCK";
        return "DATA_CONFLICT";
    }

    private static String conflictMessage(String code) {
        return switch (code) {
            case "IDEMPOTENCY_CONFLICT" -> "La clave de idempotencia ya fue utilizada";
            case "DUPLICATE_ACTIVE_ENROLLMENT" -> "Ya existe una inscripción activa equivalente";
            case "DUPLICATE_MONTHLY_FEE" -> "La mensualidad del período ya existe";
            case "DUPLICATE_REGISTRATION" -> "La matrícula del período ya existe";
            case "DUPLICATE_EFFECTIVE_DATE" -> "Ya existe una condición para la misma fecha efectiva";
            case "OVERAPPLICATION" -> "La aplicación excede el importe disponible";
            case "INSUFFICIENT_CREDIT" -> "El crédito disponible es insuficiente";
            case "INSUFFICIENT_STOCK" -> "El stock disponible es insuficiente";
            default -> "La operación viola una restricción de datos";
        };
    }

    private static String rootMessage(Throwable throwable) {
        Throwable current = throwable;
        while (current.getCause() != null) current = current.getCause();
        return current.getMessage() == null ? "" : current.getMessage();
    }

    private static String safeMessage(Throwable exception, String fallback) {
        return exception.getMessage() == null || exception.getMessage().isBlank() ? fallback : exception.getMessage();
    }

    public static class RecursoNoEncontradoException extends RuntimeException {
        public RecursoNoEncontradoException(String message) { super(message); }
    }

    public static class OperacionNoPermitidaException extends RuntimeException {
        public OperacionNoPermitidaException(String message) { super(message); }
    }

    public static class ErrorDeAutenticacionException extends RuntimeException {
        public ErrorDeAutenticacionException(String message) { super(message); }
    }

    public static class ResourceNotFoundException extends RuntimeException {
        public ResourceNotFoundException(String message) { super(message); }
    }

    public static class InvalidInscripcionException extends RuntimeException {
        public InvalidInscripcionException(String message) { super(message); }
    }

    public static class DisciplinaNotFoundException extends RuntimeException {
        public DisciplinaNotFoundException(Long id) { super("No se encontró la disciplina con id=" + id); }
    }

    public static class ProfesorNotFoundException extends RuntimeException {
        public ProfesorNotFoundException(Long id) { super("No se encontró el profesor con id=" + id); }
    }
}
