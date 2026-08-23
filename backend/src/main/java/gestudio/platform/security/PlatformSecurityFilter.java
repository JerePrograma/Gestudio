package gestudio.platform.security;

import gestudio.infra.errores.ApiErrorResponse;
import gestudio.infra.seguridad.InvalidTokenException;
import gestudio.infra.seguridad.TokenService;
import gestudio.infra.seguridad.TokenType;
import gestudio.platform.PlatformMetrics;
import gestudio.tenancy.TenantContext;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.http.HttpStatus;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.time.Clock;
import java.util.List;

@Component
public class PlatformSecurityFilter extends OncePerRequestFilter {
    private final PlatformTokenService tokens;
    private final TokenService tenantTokens;
    private final PlatformAuthenticationService authentication;
    private final PlatformMetrics metrics;
    private final ObjectMapper objectMapper;
    private final Clock clock;

    public PlatformSecurityFilter(PlatformTokenService tokens, TokenService tenantTokens,
                                  PlatformAuthenticationService authentication,
                                  PlatformMetrics metrics, ObjectMapper objectMapper, Clock clock) {
        this.tokens = tokens;
        this.tenantTokens = tenantTokens;
        this.authentication = authentication;
        this.metrics = metrics;
        this.objectMapper = objectMapper;
        this.clock = clock;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
                                    FilterChain chain) throws ServletException, IOException {
        String header = request.getHeader("Authorization");
        if (header == null || !header.startsWith("Bearer ")) {
            chain.doFilter(request, response);
            return;
        }
        SecurityContextHolder.clearContext();
        TenantContext.clear();
        try {
            PlatformVerifiedToken verified = tokens.verify(header.substring(7), TokenType.ACCESS);
            PlatformPrincipal principal = authentication.revalidate(verified);
            SecurityContextHolder.getContext().setAuthentication(
                    new UsernamePasswordAuthenticationToken(principal, null,
                            List.of(new SimpleGrantedAuthority(PlatformPrincipal.AUTHORITY))));
            chain.doFilter(request, response);
        } catch (InvalidTokenException exception) {
            if (validTenantAccessToken(header.substring(7))) {
                metrics.authorizationDenied(PlatformMetrics.AuthorizationReason.CROSS_SCOPE,
                        PlatformMetrics.Scope.TENANT, PlatformMetrics.Scope.PLATFORM);
                write(response, HttpStatus.FORBIDDEN, "TOKEN_SCOPE_FORBIDDEN",
                        "La sesión tenant no autoriza el control plane");
            } else {
                metrics.authFailure(PlatformMetrics.AuthOperation.ACCESS,
                        PlatformMetrics.AuthFailureReason.INVALID_TOKEN);
                write(response, HttpStatus.UNAUTHORIZED, "INVALID_TOKEN", "Token inválido o expirado");
            }
        } finally {
            TenantContext.clear();
            SecurityContextHolder.clearContext();
        }
    }

    private boolean validTenantAccessToken(String raw) {
        try {
            tenantTokens.verify(raw, TokenType.ACCESS);
            return true;
        } catch (InvalidTokenException ignored) {
            return false;
        }
    }

    private void write(HttpServletResponse response, HttpStatus status,
                       String code, String message) throws IOException {
        response.setStatus(status.value());
        response.setContentType("application/json");
        response.setCharacterEncoding("UTF-8");
        objectMapper.writeValue(response.getWriter(), new ApiErrorResponse(
                clock.instant(), status.value(), code, message, List.of()));
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        String path = requestPath(request);
        return path == null || !path.startsWith("/api/platform/")
                || path.equals("/api/platform/auth/login")
                || path.equals("/api/platform/auth/refresh")
                || path.equals("/api/platform/auth/logout")
                || path.equals("/api/platform/identity/activate");
    }

    private static String requestPath(HttpServletRequest request) {
        String path = request.getServletPath();
        return path == null || path.isBlank() ? request.getRequestURI() : path;
    }
}
