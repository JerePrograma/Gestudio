package gestudio.integraciones.jereplatform.infrastructure;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "app.jere-platform-student-export")
public record StudentSourceExportProperties(
        boolean enabled,
        String organizationId,
        String tenantId,
        String currentSecret,
        int pageSize
) {
}
