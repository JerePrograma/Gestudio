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
import java.util.UUID;
import java.util.regex.Pattern;

@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
public final class RequestCorrelationFilter extends OncePerRequestFilter {

    public static final String HEADER_NAME = "X-Request-ID";
    public static final String MDC_KEY = "requestId";

    private static final Logger log = LoggerFactory.getLogger(RequestCorrelationFilter.class);
    private static final Pattern SAFE_REQUEST_ID =
            Pattern.compile("[A-Za-z0-9][A-Za-z0-9._:-]{0,127}");

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain filterChain)
            throws ServletException, IOException {
        String requestId = resolveRequestId(request.getHeader(HEADER_NAME));
        long startedAt = System.nanoTime();
        Throwable failure = null;

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

    static String resolveRequestId(String candidate) {
        if (candidate != null && SAFE_REQUEST_ID.matcher(candidate).matches()) {
            return candidate;
        }
        return UUID.randomUUID().toString();
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
