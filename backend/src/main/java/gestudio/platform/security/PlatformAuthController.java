package gestudio.platform.security;

import gestudio.infra.configuracion.AppProperties;
import gestudio.infra.errores.ApiErrorResponse;
import jakarta.servlet.http.Cookie;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseCookie;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Arrays;
import java.util.List;

@RestController
@RequestMapping("/api/platform")
@Validated
public class PlatformAuthController {
    private static final String NO_CACHE = "no-cache";

    private final PlatformAuthenticationService authentication;
    private final PlatformSecurityProperties properties;
    private final AppProperties app;
    private final Clock clock;

    public PlatformAuthController(PlatformAuthenticationService authentication,
                                  PlatformSecurityProperties properties,
                                  AppProperties app, Clock clock) {
        this.authentication = authentication;
        this.properties = properties;
        this.app = app;
        this.clock = clock;
    }

    @PostMapping("/auth/login")
    public ResponseEntity<SessionResponse> login(@RequestBody @Valid LoginRequest body,
                                                  HttpServletRequest request,
                                                  HttpServletResponse response) {
        validateOrigin(request);
        var emission = authentication.login(body.nombreUsuario(), body.contrasena(),
                body.metodo(), body.codigo(), request.getHeader("User-Agent"), request.getRemoteAddr());
        return session(emission, response);
    }

    @PostMapping("/auth/refresh")
    public ResponseEntity<SessionResponse> refresh(HttpServletRequest request,
                                                    HttpServletResponse response) {
        validateOrigin(request);
        var emission = authentication.refresh(refreshCookie(request),
                request.getHeader("User-Agent"), request.getRemoteAddr());
        return session(emission, response);
    }

    @PostMapping("/auth/logout")
    public ResponseEntity<Void> logout(HttpServletRequest request, HttpServletResponse response) {
        validateOrigin(request);
        authentication.logout(refreshCookieOrNull(request));
        response.addHeader(HttpHeaders.SET_COOKIE, cookie("", Duration.ZERO).toString());
        return ResponseEntity.noContent().cacheControl(CacheControl.noStore())
                .header(HttpHeaders.PRAGMA, NO_CACHE).build();
    }

    @GetMapping("/me")
    public ResponseEntity<ProfileResponse> profile(@AuthenticationPrincipal PlatformPrincipal principal) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore())
                .header(HttpHeaders.PRAGMA, NO_CACHE)
                .body(profile(principal.userId(), principal.username()));
    }

    @ExceptionHandler(PlatformMfaRateLimitedException.class)
    public ResponseEntity<ApiErrorResponse> rateLimited(PlatformMfaRateLimitedException exception) {
        long seconds = Math.max(1, exception.retryAfter().toSeconds());
        return ResponseEntity.status(HttpStatus.TOO_MANY_REQUESTS)
                .cacheControl(CacheControl.noStore()).header(HttpHeaders.PRAGMA, NO_CACHE)
                .header(HttpHeaders.RETRY_AFTER, Long.toString(seconds))
                .body(new ApiErrorResponse(clock.instant(), 429, "MFA_RATE_LIMITED",
                        "Demasiados intentos MFA; intente nuevamente más tarde", List.of()));
    }

    private ResponseEntity<SessionResponse> session(PlatformRefreshSessionService.Emission emission,
                                                     HttpServletResponse response) {
        Duration maxAge = Duration.between(clock.instant(), emission.refreshExpiresAt());
        response.addHeader(HttpHeaders.SET_COOKIE, cookie(emission.refreshToken(), maxAge).toString());
        return ResponseEntity.ok().cacheControl(CacheControl.noStore())
                .header(HttpHeaders.PRAGMA, NO_CACHE).body(new SessionResponse(
                emission.accessToken(), emission.refreshExpiresAt(),
                profile(emission.userId(), emission.username())));
    }

    private ProfileResponse profile(long userId, String username) {
        return new ProfileResponse(userId, username, List.of(PlatformPrincipal.AUTHORITY), true, "PLATFORM");
    }

    private ResponseCookie cookie(String value, Duration maxAge) {
        var configured = properties.refreshCookie();
        ResponseCookie.ResponseCookieBuilder builder = ResponseCookie.from(configured.name(), value)
                .httpOnly(true).secure(configured.secure()).sameSite(configured.sameSite())
                .path(configured.path()).maxAge(maxAge);
        if (configured.domain() != null && !configured.domain().isBlank()) {
            builder.domain(configured.domain());
        }
        return builder.build();
    }

    private String refreshCookie(HttpServletRequest request) {
        String value = refreshCookieOrNull(request);
        if (value == null) throw new gestudio.infra.seguridad.InvalidTokenException();
        return value;
    }

    private String refreshCookieOrNull(HttpServletRequest request) {
        return request.getCookies() == null ? null : Arrays.stream(request.getCookies())
                .filter(cookie -> properties.refreshCookie().name().equals(cookie.getName()))
                .map(Cookie::getValue).findFirst().orElse(null);
    }

    private void validateOrigin(HttpServletRequest request) {
        String origin = request.getHeader(HttpHeaders.ORIGIN);
        if (origin == null || !app.corsAllowedOrigins().contains(origin)) {
            throw new AccessDeniedException("Origin no permitido");
        }
    }

    public record LoginRequest(
            @NotBlank @Size(max = 100) String nombreUsuario,
            @NotBlank @Size(max = 72) String contrasena,
            @NotNull PlatformAuthenticationService.MfaMethod metodo,
            @NotBlank @Size(max = 80) String codigo
    ) {
    }

    public record SessionResponse(String accessToken, Instant refreshExpiresAt, ProfileResponse profile) {
    }

    public record ProfileResponse(long id, String nombreUsuario, List<String> authorities,
                                  boolean mfaEnabled, String scope) {
    }
}
