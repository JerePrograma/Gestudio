package gestudio.infra.seguridad;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "app.bootstrap-superadmin")
public record SuperadminBootstrapProperties(
        boolean enabled,
        String username,
        String password
) {
}
