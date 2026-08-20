package gestudio.infra.observabilidad;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.UUID;
import java.util.regex.Pattern;

@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
public final class RequestCorrelationFilter extends OncePerRequestFilter {

    public static final String HEADER_NAME = "X-Request-ID";
    public static final String MDC_KEY = "requestId";
    public static final String ATTRIBUTE_NAME =
            "gestudio.infra.observabilidad.RequestCorrelationFilter.correlationId";

    private static final Logger log = LoggerFactory.getLogger(RequestCorrelationFilter.class);
    private static final Pattern SAFE_REQUEST_ID =
            Pattern.compile("[A-Za-z0-9][A-Za-z0-9._:-]{0,127}");

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain filterChain)
            throws ServletException, IOException {
        UUID correlationId = resolveRequestId(request.getHeader(HEADER_NAME));
        String requestId = correlationId.toString();
        long startedAt = System.nanoTime();
        Throwable failure = null;

        request.setAttribute(ATTRIBUTE_NAME, correlationId);
        MDC.put(MDC_KEY, requestId);
        response.setHeader(HEADER_NAME, requestId);
        try {
            filterChain.doFilter(request, response);
        } catch (ServletException | IOException | RuntimeException exception) {
            failure = exception;
            throw exception;
        } finally {
            try {
                logApiRequest(request, response, startedAt, failure);
            } finally {
                MDC.remove(MDC_KEY);
            }
        }
    }

    static UUID resolveRequestId(String candidate) {
        if (candidate == null || !SAFE_REQUEST_ID.matcher(candidate).matches()) {
            return UUID.randomUUID();
        }
        try {
            return UUID.fromString(candidate);
        } catch (IllegalArgumentException ignored) {
            return UUID.nameUUIDFromBytes(candidate.getBytes(StandardCharsets.UTF_8));
        }
    }

    private static void logApiRequest(HttpServletRequest request,
                                      HttpServletResponse response,
                                      long startedAt,
                                      Throwable failure) {
        String path = request.getRequestURI();
        if (path == null || !path.startsWith("/api/")) {
            return;
        }

        long durationMs = Math.max(0L, (System.nanoTime() - startedAt) / 1_000_000L);
        String safeMethod = sanitize(request.getMethod());
        String safePath = sanitize(path);
        String outcome = failure == null ? "completed" : "exception";

        log.info("http_request method={} path={} status={} durationMs={} outcome={}",
                safeMethod,
                safePath,
                response.getStatus(),
                durationMs,
                outcome);
    }

    private static String sanitize(String value) {
        if (value == null) {
            return "-";
        }
        return value.replace('\r', '_').replace('\n', '_').replace('\t', '_');
    }
}
