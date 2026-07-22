package gestudio.infra.seguridad;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "app.local-admin-password-reset")
public record LocalAdminPasswordResetProperties(
        String username,
        String password
) {
}
