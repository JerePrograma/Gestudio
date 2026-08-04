package gestudio.integraciones.jereplatform;

import gestudio.integraciones.jereplatform.application.SourceTenantMapping;
import gestudio.integraciones.jereplatform.application.StudentSourceExportException;
import gestudio.integraciones.jereplatform.infrastructure.StudentSourceExportProperties;
import gestudio.tenancy.TenantContext;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;

import java.time.Clock;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verifyNoInteractions;

class SourceTenantMappingTest {

    @Test
    void distingueTenantInternoDeOrganizacionYTenantExternos() {
        var mapping = new SourceTenantMapping.Mapping(
                UUID.randomUUID(),
                UUID.fromString("00000000-0000-0000-0000-000000000001"),
                "academy-a",
                UUID.fromString("00000000-0000-0000-0000-00000000000a"),
                SourceTenantMapping.SOURCE_TYPE,
                3,
                SourceTenantMapping.SIGNING_KEY_REF);

        assertThat(mapping.internalTenantId()).isNotEqualTo(mapping.externalTenantId());
        assertThat(mapping.organizationId()).isEqualTo("academy-a");
        assertThat(mapping.configVersion()).isEqualTo(3);
    }

    @Test
    void exportacionDeshabilitadaFallaAntesDeConsultarLaBase() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        SourceTenantMapping mappings = new SourceTenantMapping(
                new StudentSourceExportProperties(false, "", 1_000), jdbc, Clock.systemUTC());

        assertThatThrownBy(mappings::require)
                .isInstanceOf(StudentSourceExportException.class)
                .extracting(error -> ((StudentSourceExportException) error).code())
                .isEqualTo(StudentSourceExportException.Code.TENANT_MAPPING_DISABLED);
        verifyNoInteractions(jdbc);
    }

    @Test
    void configuracionInvalidaFallaSinConfiarEnIdsExternos() {
        SourceTenantMapping mappings = new SourceTenantMapping(
                new StudentSourceExportProperties(true, "", 1_000),
                mock(JdbcTemplate.class), Clock.systemUTC());
        try (TenantContext.Scope ignored = TenantContext.open(UUID.randomUUID(), null)) {
            assertThatThrownBy(() -> mappings.configure("academy a", UUID.randomUUID(), 1L))
                    .isInstanceOf(StudentSourceExportException.class)
                    .extracting(error -> ((StudentSourceExportException) error).code())
                    .isEqualTo(StudentSourceExportException.Code.TENANT_MAPPING_INVALID);
        }
    }
}
