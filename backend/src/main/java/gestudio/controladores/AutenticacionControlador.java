package gestudio.controladores;

import jakarta.servlet.http.Cookie;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import gestudio.dto.request.LoginRequest;
import gestudio.dto.usuario.response.UsuarioResponse;
import gestudio.infra.configuracion.AppProperties;
import gestudio.infra.seguridad.AutenticacionService;
import gestudio.infra.seguridad.SecurityProperties;
import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseCookie;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.*;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import gestudio.entidades.Usuario;
import gestudio.tenancy.TenantSummaryResponse;

import java.time.Clock;
import java.time.Duration;
import java.util.Arrays;
import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/login")
@Validated
public class AutenticacionControlador {
    private final AutenticacionService autenticacion;
    private final SecurityProperties.RefreshCookie cookie;
    private final AppProperties app;
    private final Clock clock;

    public AutenticacionControlador(AutenticacionService autenticacion, SecurityProperties security,
                                    AppProperties app, Clock clock) {
        this.autenticacion = autenticacion;
        this.cookie = security.refreshCookie();
        this.app = app;
        this.clock = clock;
    }

    @PostMapping
    public ResponseEntity<?> login(@RequestBody @Valid LoginRequest request,
                                   HttpServletRequest http, HttpServletResponse response) {
        AutenticacionService.Resultado result =
                autenticacion.login(request, http.getHeader("User-Agent"), http.getRemoteAddr());
        if (result.selectionRequired()) {
            return ResponseEntity.status(409).body(new TenantSelectionResponse(true, result.tenants()));
        }
        return responder(result, response);
    }

    @PostMapping("/refresh")
    public ResponseEntity<LoginResponse> refresh(HttpServletRequest request, HttpServletResponse response) {
        validarOrigin(request);
        return responder(autenticacion.refresh(refreshCookie(request),
                request.getHeader("User-Agent"), request.getRemoteAddr()), response);
    }

    @PostMapping("/logout")
    public ResponseEntity<Void> logout(HttpServletRequest request, HttpServletResponse response) {
        validarOrigin(request);
        autenticacion.logout(refreshCookieOrNull(request));
        response.addHeader(HttpHeaders.SET_COOKIE, cookie("", Duration.ZERO).toString());
        return ResponseEntity.noContent().build();
    }

    @PostMapping("/tenant")
    public ResponseEntity<LoginResponse> switchTenant(@RequestBody @Valid TenantSwitchRequest body,
                                                       @AuthenticationPrincipal Usuario usuario,
                                                       HttpServletRequest request,
                                                       HttpServletResponse response) {
        validarOrigin(request);
        return responder(autenticacion.switchTenant(
                usuario,
                body.tenantId(),
                refreshCookie(request),
                request.getHeader("User-Agent"),
                request.getRemoteAddr()
        ), response);
    }

    private ResponseEntity<LoginResponse> responder(AutenticacionService.Resultado result,
                                                     HttpServletResponse response) {
        Duration maxAge = Duration.between(clock.instant(), result.refreshExpiresAt());
        response.addHeader(HttpHeaders.SET_COOKIE, cookie(result.refreshToken(), maxAge).toString());
        return ResponseEntity.ok(new LoginResponse(result.accessToken(), result.usuario()));
    }

    private ResponseCookie cookie(String value, Duration maxAge) {
        ResponseCookie.ResponseCookieBuilder builder = ResponseCookie.from(cookie.name(), value)
                .httpOnly(true).secure(cookie.secure()).sameSite(cookie.sameSite())
                .path(cookie.path()).maxAge(maxAge);
        if (cookie.domain() != null && !cookie.domain().isBlank()) builder.domain(cookie.domain());
        return builder.build();
    }

    private String refreshCookie(HttpServletRequest request) {
        String value = refreshCookieOrNull(request);
        if (value == null) throw new gestudio.infra.seguridad.InvalidTokenException();
        return value;
    }

    private String refreshCookieOrNull(HttpServletRequest request) {
        return request.getCookies() == null ? null : Arrays.stream(request.getCookies())
                .filter(value -> cookie.name().equals(value.getName()))
                .map(Cookie::getValue).findFirst().orElse(null);
    }

    private void validarOrigin(HttpServletRequest request) {
        String origin = request.getHeader(HttpHeaders.ORIGIN);
        if (origin == null || !app.corsAllowedOrigins().contains(origin)) {
            throw new org.springframework.security.access.AccessDeniedException("Origin no permitido");
        }
    }

    public record LoginResponse(String accessToken, UsuarioResponse usuario) {
    }

    public record TenantSelectionResponse(boolean selectionRequired, List<TenantSummaryResponse> tenants) {
    }

    public record TenantSwitchRequest(@NotNull UUID tenantId) {
    }
}
