package gestudio.integraciones.jereplatform.application;

import gestudio.integraciones.jereplatform.infrastructure.StudentSourceExportProperties;
import org.springframework.stereotype.Component;

import java.util.UUID;

import static gestudio.integraciones.jereplatform.application.StudentSourceExportException.Code.TENANT_MAPPING_DISABLED;
import static gestudio.integraciones.jereplatform.application.StudentSourceExportException.Code.TENANT_MAPPING_INVALID;
import static gestudio.integraciones.jereplatform.application.StudentSourceExportException.Code.TENANT_MAPPING_MISSING;

@Component
public class SourceTenantMapping {
    private final StudentSourceExportProperties properties;

    public SourceTenantMapping(StudentSourceExportProperties properties) {
        this.properties = properties;
    }

    public Mapping require() {
        if (!properties.enabled()) {
            throw new StudentSourceExportException(TENANT_MAPPING_DISABLED);
        }
        String organizationId = trim(properties.organizationId());
        String tenantId = trim(properties.tenantId());
        if (organizationId == null || tenantId == null) {
            throw new StudentSourceExportException(TENANT_MAPPING_MISSING);
        }
        if (organizationId.length() > 100 || !organizationId.matches("[A-Za-z0-9][A-Za-z0-9._-]*")) {
            throw new StudentSourceExportException(TENANT_MAPPING_INVALID);
        }
        try {
            return new Mapping(organizationId, UUID.fromString(tenantId));
        } catch (IllegalArgumentException invalidUuid) {
            throw new StudentSourceExportException(TENANT_MAPPING_INVALID);
        }
    }

    private static String trim(String value) {
        if (value == null || value.isBlank()) return null;
        String trimmed = value.trim();
        return trimmed.equals(value) ? trimmed : null;
    }

    public record Mapping(String organizationId, UUID tenantId) {
    }
}
