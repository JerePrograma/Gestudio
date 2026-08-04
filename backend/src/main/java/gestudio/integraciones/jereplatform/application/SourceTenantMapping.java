package gestudio.integraciones.jereplatform.application;

import gestudio.integraciones.jereplatform.infrastructure.StudentSourceExportProperties;
import gestudio.tenancy.TenantContext;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Timestamp;
import java.time.Clock;
import java.util.Optional;
import java.util.UUID;

import static gestudio.integraciones.jereplatform.application.StudentSourceExportException.Code.TENANT_MAPPING_DISABLED;
import static gestudio.integraciones.jereplatform.application.StudentSourceExportException.Code.TENANT_MAPPING_INVALID;
import static gestudio.integraciones.jereplatform.application.StudentSourceExportException.Code.TENANT_MAPPING_MISSING;

@Component
public class SourceTenantMapping {
    public static final String SOURCE_TYPE = "GESTUDIO_STUDENT";
    public static final String SIGNING_KEY_REF = "APP_JERE_PLATFORM_STUDENT_EXPORT_CURRENT_SECRET";

    private final StudentSourceExportProperties properties;
    private final JdbcTemplate jdbc;
    private final Clock clock;

    public SourceTenantMapping(StudentSourceExportProperties properties, JdbcTemplate jdbc, Clock clock) {
        this.properties = properties;
        this.jdbc = jdbc;
        this.clock = clock;
    }

    public Mapping require() {
        if (!properties.enabled()) {
            throw new StudentSourceExportException(TENANT_MAPPING_DISABLED);
        }
        return current().orElseThrow(() -> new StudentSourceExportException(TENANT_MAPPING_MISSING));
    }

    public Optional<Mapping> current() {
        UUID internalTenantId = TenantContext.requireTenantId();
        return jdbc.query("""
                SELECT id, internal_tenant_id, external_organization_id, external_tenant_id,
                       source_type, config_version, signing_key_ref
                  FROM jere_platform_tenant_mappings
                 WHERE internal_tenant_id = ? AND source_type = ? AND active
                """, (resultSet, rowNumber) -> new Mapping(
                        resultSet.getObject("id", UUID.class),
                        resultSet.getObject("internal_tenant_id", UUID.class),
                        resultSet.getString("external_organization_id"),
                        resultSet.getObject("external_tenant_id", UUID.class),
                        resultSet.getString("source_type"),
                        resultSet.getLong("config_version"),
                        resultSet.getString("signing_key_ref")),
                internalTenantId, SOURCE_TYPE).stream().findFirst();
    }

    @Transactional
    public Mapping configure(String organizationId, UUID externalTenantId, Long actorId) {
        String organization = validateOrganization(organizationId);
        if (externalTenantId == null || actorId == null) {
            throw new StudentSourceExportException(TENANT_MAPPING_INVALID);
        }
        UUID internalTenantId = TenantContext.requireTenantId();
        jdbc.queryForObject("SELECT id FROM tenants WHERE id = ? FOR UPDATE", UUID.class, internalTenantId);
        Long nextVersion = jdbc.queryForObject("""
                SELECT COALESCE(max(config_version), 0) + 1
                  FROM jere_platform_tenant_mappings
                 WHERE internal_tenant_id = ? AND source_type = ?
                """, Long.class, internalTenantId, SOURCE_TYPE);
        jdbc.update("""
                UPDATE jere_platform_tenant_mappings
                   SET active = false, deactivated_at = ?
                 WHERE internal_tenant_id = ? AND source_type = ? AND active
                """, Timestamp.from(clock.instant()), internalTenantId, SOURCE_TYPE);
        UUID mappingId = UUID.randomUUID();
        jdbc.update("""
                INSERT INTO jere_platform_tenant_mappings(
                    id, internal_tenant_id, external_organization_id, external_tenant_id,
                    source_type, config_version, signing_key_ref, active, created_by_usuario_id)
                VALUES (?, ?, ?, ?, ?, ?, ?, true, ?)
                """, mappingId, internalTenantId, organization, externalTenantId,
                SOURCE_TYPE, nextVersion, SIGNING_KEY_REF, actorId);
        return current().orElseThrow(() -> new StudentSourceExportException(TENANT_MAPPING_MISSING));
    }

    private static String validateOrganization(String value) {
        if (value == null || value.isBlank() || !value.equals(value.trim())
                || value.length() > 100 || !value.matches("[A-Za-z0-9][A-Za-z0-9._-]*")) {
            throw new StudentSourceExportException(TENANT_MAPPING_INVALID);
        }
        return value;
    }

    public record Mapping(
            UUID id,
            UUID internalTenantId,
            String organizationId,
            UUID externalTenantId,
            String sourceType,
            long configVersion,
            String signingKeyRef
    ) {
    }
}
