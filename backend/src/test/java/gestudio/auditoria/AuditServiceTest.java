package gestudio.auditoria;

import com.fasterxml.jackson.databind.ObjectMapper;
import gestudio.auditoria.application.AuditService;
import gestudio.entidades.Usuario;
import gestudio.tenancy.TenantAccess;
import gestudio.tenancy.TenantAccessService;
import gestudio.tenancy.TenantContext;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.jdbc.core.JdbcTemplate;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

class AuditServiceTest {
    private final JdbcTemplate jdbc = mock(JdbcTemplate.class);
    private final TenantAccessService tenantAccess = mock(TenantAccessService.class);
    private final AuditService audit = new AuditService(
            jdbc,
            new ObjectMapper(),
            Clock.fixed(Instant.parse("2026-08-04T12:00:00Z"), ZoneOffset.UTC),
            tenantAccess
    );

    @AfterEach
    void clearTenant() {
        TenantContext.clear();
    }

    @Test
    void registraElRolDeLaMembershipActiva() {
        Usuario actor = actor();
        TenantAccess access = mock(TenantAccess.class);
        when(access.primaryRoleCode()).thenReturn("CAJA");
        when(tenantAccess.currentAccess(actor)).thenReturn(access);

        try (TenantContext.Scope ignored = TenantContext.open(UUID.randomUUID(), UUID.randomUUID())) {
            audit.registrar("SEGURIDAD", "PRUEBA", "USUARIO", "1", actor, null, Map.of());
        }

        assertThat(capturedValues()[7]).isEqualTo("CAJA");
    }

    @Test
    void noInventaRolSinMembershipEnContexto() {
        audit.registrar("PLATAFORMA", "PRUEBA", "TENANT", "1", actor(), null, Map.of());

        assertThat(capturedValues()[7]).isNull();
        verifyNoInteractions(tenantAccess);
    }

    private Object[] capturedValues() {
        ArgumentCaptor<Object[]> values = ArgumentCaptor.forClass(Object[].class);
        verify(jdbc).update(anyString(), values.capture());
        return values.getValue();
    }

    private static Usuario actor() {
        Usuario actor = new Usuario();
        actor.setId(1L);
        actor.setNombreUsuario("auditor");
        actor.setActivo(true);
        return actor;
    }
}
