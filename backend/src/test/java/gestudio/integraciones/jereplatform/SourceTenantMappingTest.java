package gestudio.integraciones.jereplatform;

import gestudio.integraciones.jereplatform.application.SourceTenantMapping;
import gestudio.integraciones.jereplatform.application.StudentSourceExportException;
import gestudio.integraciones.jereplatform.infrastructure.StudentSourceExportProperties;
import org.junit.jupiter.api.Test;

import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class SourceTenantMappingTest {
    @Test
    void resuelveUnicamenteElMappingExplicito() {
        var mapping = new SourceTenantMapping(properties(
                true, "academy-a", "00000000-0000-0000-0000-00000000000a")).require();

        assertThat(mapping.organizationId()).isEqualTo("academy-a");
        assertThat(mapping.tenantId()).isEqualTo(
                UUID.fromString("00000000-0000-0000-0000-00000000000a"));
    }

    @Test
    void fallaCerradoCuandoEstaDeshabilitadoAusenteOEsInvalido() {
        assertCode(properties(false, "academy-a", "00000000-0000-0000-0000-00000000000a"),
                StudentSourceExportException.Code.TENANT_MAPPING_DISABLED);
        assertCode(properties(true, "", "00000000-0000-0000-0000-00000000000a"),
                StudentSourceExportException.Code.TENANT_MAPPING_MISSING);
        assertCode(properties(true, "academy-a", "not-a-uuid"),
                StudentSourceExportException.Code.TENANT_MAPPING_INVALID);
        assertCode(properties(true, "academy a", "00000000-0000-0000-0000-00000000000a"),
                StudentSourceExportException.Code.TENANT_MAPPING_INVALID);
    }

    private static void assertCode(
            StudentSourceExportProperties properties,
            StudentSourceExportException.Code code
    ) {
        assertThatThrownBy(() -> new SourceTenantMapping(properties).require())
                .isInstanceOf(StudentSourceExportException.class)
                .extracting(error -> ((StudentSourceExportException) error).code())
                .isEqualTo(code);
    }

    private static StudentSourceExportProperties properties(
            boolean enabled,
            String organization,
            String tenant
    ) {
        return new StudentSourceExportProperties(
                enabled,
                organization,
                tenant,
                "",
                1_000
        );
    }
}
