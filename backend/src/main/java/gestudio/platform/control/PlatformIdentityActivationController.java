package gestudio.platform.control;

import gestudio.infra.configuracion.AppProperties;
import gestudio.infra.observabilidad.RequestCorrelationFilter;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import org.springframework.http.HttpHeaders;
import org.springframework.http.CacheControl;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestAttribute;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

@RestController
@RequestMapping("/api/platform/identity")
@Validated
public class PlatformIdentityActivationController {
    private final PlatformIdentityActivationService activation;
    private final AppProperties app;

    public PlatformIdentityActivationController(PlatformIdentityActivationService activation,
                                                AppProperties app) {
        this.activation = activation;
        this.app = app;
    }

    @PostMapping("/activate")
    public ResponseEntity<PlatformIdentityActivationService.ActivationResult> activate(
            @RequestBody @Valid ActivationRequest body,
            @RequestAttribute(name = RequestCorrelationFilter.ATTRIBUTE_NAME) UUID correlationId,
            HttpServletRequest request) {
        String origin = request.getHeader(HttpHeaders.ORIGIN);
        if (origin == null || !app.corsAllowedOrigins().contains(origin)) {
            throw new AccessDeniedException("Origin no permitido");
        }
        return ResponseEntity.ok().cacheControl(CacheControl.noStore())
                .header(HttpHeaders.PRAGMA, "no-cache")
                .body(activation.activate(body.token(), body.password(),
                        body.totpSecret(), body.totpCode(),
                        correlationId));
    }

    public record ActivationRequest(@NotBlank @Size(max = 256) String token,
                                    @Size(max = 72) String password,
                                    @Size(max = 128) String totpSecret,
                                    @Size(max = 8) String totpCode) {
    }
}
