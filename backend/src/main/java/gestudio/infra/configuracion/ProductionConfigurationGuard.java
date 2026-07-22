package gestudio.infra.configuracion;

import gestudio.infra.seguridad.SecurityProperties;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

import java.net.URI;
import java.nio.charset.StandardCharsets;

@Component
@Profile({"prod", "remote-demo"})
public class ProductionConfigurationGuard {

    public ProductionConfigurationGuard(
            AppProperties app,
            SecurityProperties security,
            @Value("${app.observability.metrics-token:}") String metricsToken) {
        if (app.corsAllowedOrigins().stream().anyMatch(origin -> !isSecureOrigin(origin))) {
            throw new IllegalStateException(
                    "Los perfiles públicos exigen orígenes CORS HTTPS explícitos, sin wildcard, path ni credenciales");
        }
        if (security.refreshCookie() == null || !security.refreshCookie().secure()) {
            throw new IllegalStateException("Los perfiles públicos exigen la cookie de refresh Secure");
        }
        if (metricsToken == null || metricsToken.getBytes(StandardCharsets.UTF_8).length < 32) {
            throw new IllegalStateException(
                    "Los perfiles públicos exigen un token de métricas independiente de al menos 32 bytes UTF-8");
        }
    }

    private static boolean isSecureOrigin(String value) {
        if (value == null || value.isBlank() || value.contains("*")) return false;
        try {
            URI origin = URI.create(value);
            return "https".equalsIgnoreCase(origin.getScheme())
                    && origin.getHost() != null
                    && !origin.getHost().isBlank()
                    && (origin.getRawPath() == null || origin.getRawPath().isEmpty())
                    && origin.getRawQuery() == null
                    && origin.getRawFragment() == null
                    && origin.getUserInfo() == null;
        } catch (IllegalArgumentException exception) {
            return false;
        }
    }
}
