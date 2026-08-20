package gestudio.infra.seguridad;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import gestudio.entidades.Usuario;
import gestudio.tenancy.TenantAccess;
import gestudio.tenancy.TenantAccessService;
import gestudio.tenancy.TenantContext;
import gestudio.tenancy.TenantMetrics;
import gestudio.platform.PlatformMetrics;
import gestudio.platform.security.PlatformTokenService;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.web.AuthenticationEntryPoint;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.time.Clock;
import java.util.List;
import java.util.Objects;

@Component
public class SecurityFilter extends OncePerRequestFilter {

    private final TokenService tokenService;
    private final PlatformTokenService platformTokenService;
    private final AuthenticationEntryPoint authenticationEntryPoint;
    private final TenantAccessService tenantAccess;
    private final TenantMetrics tenantMetrics;
    private final PlatformMetrics platformMetrics;
    private final ObjectMapper objectMapper;
    private final Clock clock;

    public SecurityFilter(TokenService tokenService,
                          PlatformTokenService platformTokenService,
                          AuthenticationEntryPoint authenticationEntryPoint,
                          TenantAccessService tenantAccess,
                          TenantMetrics tenantMetrics,
                          PlatformMetrics platformMetrics,
                          ObjectMapper objectMapper,
                          Clock clock) {
        this.tokenService = tokenService;
        this.platformTokenService = platformTokenService;
        this.authenticationEntryPoint = authenticationEntryPoint;
        this.tenantAccess = tenantAccess;
        this.tenantMetrics = tenantMetrics;
        this.platformMetrics = platformMetrics;
        this.objectMapper = objectMapper;
        this.clock = clock;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain filterChain)
            throws ServletException, IOException {
        String authHeader = request.getHeader("Authorization");

        if (authHeader == null || !authHeader.startsWith("Bearer ")) {
            if (SecurityContextHolder.getContext().getAuthentication() == null) {
                TenantContext.clear();
            }
            filterChain.doFilter(request, response);
            return;
        }

        TenantContext.clear();
        SecurityContextHolder.clearContext();
        TenantContext.Scope scope = null;

        try {
            String token = authHeader.substring("Bearer ".length());

            try {
                VerifiedToken verified = tokenService.verify(token, TokenType.ACCESS);

                TenantAccess access = tenantAccess.revalidate(
                                verified.userId(), verified.membershipId(), verified.tenantId(),
                                verified.tenantSecurityVersion(), verified.membershipSecurityVersion())
                        .orElseThrow(InvalidTokenException::new);

                Usuario userEntity = access.usuario();
                if (!Objects.equals(userEntity.getNombreUsuario(), verified.subject())
                        || !userEntity.isEnabled()
                        || !Objects.equals(userEntity.getAuthVersion(), verified.authVersion())) {
                    throw new InvalidTokenException();
                }

                scope = TenantContext.open(access.tenantId(), access.membershipId());

                var authentication = new UsernamePasswordAuthenticationToken(
                        userEntity,
                        null,
                        access.authorities()
                );

                SecurityContextHolder.getContext().setAuthentication(authentication);
                tenantMetrics.resolution("success", "token_bound");
            } catch (InvalidTokenException ex) {
                SecurityContextHolder.clearContext();
                tenantMetrics.resolution("denied", "invalid_session");
                tenantMetrics.accessDenied("invalid_session", "http_request");
                if (validPlatformAccessToken(token)) {
                    platformMetrics.authorizationDenied(
                            PlatformMetrics.AuthorizationReason.CROSS_SCOPE,
                            PlatformMetrics.Scope.PLATFORM, PlatformMetrics.Scope.TENANT);
                    response.setStatus(org.springframework.http.HttpStatus.FORBIDDEN.value());
                    response.setContentType("application/json");
                    response.setCharacterEncoding("UTF-8");
                    objectMapper.writeValue(response.getWriter(), new gestudio.infra.errores.ApiErrorResponse(
                            clock.instant(), 403, "TOKEN_SCOPE_FORBIDDEN",
                            "La sesión de plataforma no autoriza recursos tenant", List.of()));
                    return;
                }
                authenticationEntryPoint.commence(
                        request,
                        response,
                        new BadCredentialsException("Token inválido", ex)
                );
                return;
            }

            filterChain.doFilter(request, response);
        } finally {
            if (scope != null) {
                scope.close();
            }
            TenantContext.clear();
            SecurityContextHolder.clearContext();
        }
    }

    private boolean validPlatformAccessToken(String token) {
        try {
            platformTokenService.verify(token, TokenType.ACCESS);
            return true;
        } catch (InvalidTokenException ignored) {
            return false;
        }
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        String path = request.getServletPath();
        return (path != null && path.startsWith("/api/platform/"))
                || "/api/login".equals(path)
                || "/api/login/refresh".equals(path)
                || "/api/login/logout".equals(path);
    }
}
