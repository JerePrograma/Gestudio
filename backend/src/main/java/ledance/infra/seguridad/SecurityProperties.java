package ledance.infra.seguridad;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "app.security")
public record SecurityProperties(int bcryptStrength, RefreshCookie refreshCookie) {
    public record RefreshCookie(
            String name,
            boolean secure,
            String sameSite,
            String domain,
            String path
    ) {
    }
}
