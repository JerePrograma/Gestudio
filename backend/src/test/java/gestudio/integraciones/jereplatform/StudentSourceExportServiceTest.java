package gestudio.integraciones.jereplatform;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import gestudio.auditoria.application.AuditService;
import gestudio.entidades.Usuario;
import gestudio.infra.seguridad.RbacService;
import gestudio.integraciones.jereplatform.application.SourceTenantMapping;
import gestudio.integraciones.jereplatform.application.StudentSourceExport;
import gestudio.integraciones.jereplatform.application.StudentSourceExportException;
import gestudio.integraciones.jereplatform.application.StudentSourceExportService;
import gestudio.integraciones.jereplatform.infrastructure.GestudioStudentReferenceReader;
import gestudio.integraciones.jereplatform.infrastructure.StudentSourceExportProperties;
import gestudio.integraciones.jereplatform.infrastructure.StudentSourceExportSerializer;
import gestudio.integraciones.jereplatform.infrastructure.StudentSourceExportSigner;
import gestudio.integraciones.jereplatform.infrastructure.StudentSourceExportStore;
import java.security.SecureRandom;
import java.time.Clock;
import java.util.Base64;
import java.util.List;
import org.junit.jupiter.api.Test;

class StudentSourceExportServiceTest {

    @Test
    void rechazaPageSizeMayorA1000AntesDeLeerEstudiantes() {
        var fixture = fixture(1_001);

        assertThatThrownBy(() -> fixture.service().createSnapshot(fixture.actor()))
                .isInstanceOf(StudentSourceExportException.class)
                .extracting(error -> ((StudentSourceExportException) error).code())
                .isEqualTo(StudentSourceExportException.Code.PAGE_TOO_LARGE);
        verifyNoInteractions(fixture.students(), fixture.store());
    }

    @Test
    void rechazaPayloadMayorAUnMegabyteSinPersistirLaPagina() {
        var fixture = fixture(1);
        when(fixture.students().readAll()).thenReturn(List.of(
                new StudentSourceExport.StudentReference("1", "Synthetic Student", true)));
        when(fixture.serializer().serialize(any(StudentSourceExport.class)))
                .thenReturn(new byte[StudentSourceExportService.MAX_PAYLOAD_BYTES + 1]);

        assertThatThrownBy(() -> fixture.service().createSnapshot(fixture.actor()))
                .isInstanceOf(StudentSourceExportException.class)
                .extracting(error -> ((StudentSourceExportException) error).code())
                .isEqualTo(StudentSourceExportException.Code.PAYLOAD_TOO_LARGE);
    }

    private static Fixture fixture(int pageSize) {
        var properties = new StudentSourceExportProperties(
                true,
                "synthetic-academy",
                "00000000-0000-0000-0000-0000000000a1",
                runtimeSecret(),
                pageSize
        );
        var students = mock(GestudioStudentReferenceReader.class);
        var serializer = mock(StudentSourceExportSerializer.class);
        var store = mock(StudentSourceExportStore.class);
        var rbac = mock(RbacService.class);
        var actor = new Usuario();
        actor.setId(1L);
        when(rbac.exigirPermiso(any(Usuario.class), anyString(), anyString()))
                .thenReturn(actor);
        var service = new StudentSourceExportService(
                new SourceTenantMapping(properties),
                properties,
                students,
                serializer,
                new StudentSourceExportSigner(properties),
                store,
                rbac,
                mock(AuditService.class),
                Clock.systemUTC()
        );
        return new Fixture(service, actor, students, serializer, store);
    }

    private static String runtimeSecret() {
        byte[] bytes = new byte[32];
        new SecureRandom().nextBytes(bytes);
        return Base64.getEncoder().encodeToString(bytes);
    }

    private record Fixture(
            StudentSourceExportService service,
            Usuario actor,
            GestudioStudentReferenceReader students,
            StudentSourceExportSerializer serializer,
            StudentSourceExportStore store
    ) {
    }
}
