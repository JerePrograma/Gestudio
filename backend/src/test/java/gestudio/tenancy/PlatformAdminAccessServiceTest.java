package gestudio.tenancy;

import gestudio.auditoria.application.AuditFailureService;
import gestudio.entidades.Usuario;
import org.junit.jupiter.api.Test;
import org.springframework.security.access.AccessDeniedException;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class PlatformAdminAccessServiceTest {
    private final PlatformAdminRepository admins = mock(PlatformAdminRepository.class);
    private final AuditFailureService audit = mock(AuditFailureService.class);
    private final PlatformAdminAccessService access = new PlatformAdminAccessService(admins, audit);

    @Test
    void superadminLocalNoReemplazaCapacidadGlobalExplicita() {
        Usuario user = activeUser();
        when(admins.existsByUsuarioIdAndActiveTrue(user.getId())).thenReturn(false);

        assertThatThrownBy(() -> access.requireProvisioningCapability(user, "TENANT_CREATE"))
                .isInstanceOf(AccessDeniedException.class);
        verify(audit).registrarEscalamiento(user, "TENANT_CREATE");
    }

    @Test
    void platformAdminActivoPuedeEntrarSoloAlPlanoDeProvisioning() {
        Usuario user = activeUser();
        when(admins.existsByUsuarioIdAndActiveTrue(user.getId())).thenReturn(true);

        assertThatCode(() -> access.requireProvisioningCapability(user, "TENANT_CREATE"))
                .doesNotThrowAnyException();
    }

    @Test
    void actorNuloSinIdOInactivoEsRechazadoYAuditadoAntesDeConsultarCapacidad() {
        Usuario withoutId = new Usuario();
        Usuario disabled = activeUser();
        disabled.setActivo(false);

        for (Usuario actor : new Usuario[]{null, withoutId, disabled}) {
            assertThatThrownBy(() -> access.requireProvisioningCapability(actor, "TENANT_CREATE"))
                    .isInstanceOf(AccessDeniedException.class)
                    .hasMessage("Platform provisioning capability required");
            verify(audit).registrarEscalamiento(actor, "TENANT_CREATE");
        }
        verify(admins, never()).existsByUsuarioIdAndActiveTrue(org.mockito.ArgumentMatchers.anyLong());
    }

    private Usuario activeUser() {
        Usuario user = new Usuario();
        user.setId(10L);
        user.setNombreUsuario("platform-admin");
        user.setActivo(true);
        return user;
    }
}
