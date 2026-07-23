package gestudio.infra.seguridad;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

@Component
@Profile("remote-demo")
@Order(Ordered.HIGHEST_PRECEDENCE + 1)
public final class RemoteDemoProxyTokenFilter extends OncePerRequestFilter {

    public static final String HEADER_NAME = "X-Gestudio-Proxy-Token";
    private static final String CF_CONNECTING_IP_HEADER = "CF-Connecting-IP";
    private static final String CF_RAY_HEADER = "CF-Ray";

    private final byte[] expectedToken;

    public RemoteDemoProxyTokenFilter(
            @Value("${app.remote-demo.proxy-token:}") String proxyToken) {
        byte[] configuredToken = proxyToken == null
                ? new byte[0]
                : proxyToken.getBytes(StandardCharsets.UTF_8);
        if (configuredToken.length < 32) {
            throw new IllegalStateException(
                    "remote-demo exige un token de proxy independiente de al menos 32 bytes UTF-8");
        }
        this.expectedToken = configuredToken.clone();
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        String path = request.getRequestURI();
        return !isApiPath(path) && !isCloudflareEdgeRequest(request);
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain filterChain)
            throws ServletException, IOException {
        if (!isApiPath(request.getRequestURI())) {
            hideResponse(response);
            return;
        }

        String candidate = request.getHeader(HEADER_NAME);
        byte[] candidateBytes = candidate == null
                ? new byte[0]
                : candidate.getBytes(StandardCharsets.UTF_8);
        if (!MessageDigest.isEqual(expectedToken, candidateBytes)) {
            hideResponse(response);
            return;
        }
        filterChain.doFilter(request, response);
    }

    private static boolean isApiPath(String path) {
        return path != null && (path.equals("/api") || path.startsWith("/api/"));
    }

    private static boolean isCloudflareEdgeRequest(HttpServletRequest request) {
        return hasText(request.getHeader(CF_CONNECTING_IP_HEADER))
                || hasText(request.getHeader(CF_RAY_HEADER));
    }

    private static boolean hasText(String value) {
        return value != null && !value.isBlank();
    }

    private static void hideResponse(HttpServletResponse response) throws IOException {
        response.setHeader("Cache-Control", "no-store");
        response.sendError(HttpServletResponse.SC_NOT_FOUND);
    }
}
