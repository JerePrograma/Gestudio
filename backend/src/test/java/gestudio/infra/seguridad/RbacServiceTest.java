package gestudio.infra.seguridad;

import gestudio.auditoria.application.AuditFailureService;
import gestudio.entidades.Usuario;
import gestudio.tenancy.TenantAccess;
import gestudio.tenancy.TenantAccessService;
import gestudio.tenancy.TenantMembership;
import org.junit.jupiter.api.Test;
import org.springframework.security.access.AccessDeniedException;

import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class RbacServiceTest {
    private final TenantAccessService tenantAccess = mock(TenantAccessService.class);
    private final AuditFailureService auditFailures = mock(AuditFailureService.class);
    private final RbacService rbac = new RbacService(tenantAccess, auditFailures);

    @Test
    void permisoRequiresIdentifiedActorAndAuditsBothAnonymousShapes() {
        Usuario withoutId = new Usuario();

        assertThatThrownBy(() -> rbac.exigirPermiso(null, "PAGOS_VER", "LISTAR_PAGOS"))
                .isInstanceOf(AccessDeniedException.class).hasMessage("Actor requerido");
        assertThatThrownBy(() -> rbac.exigirPermiso(withoutId, "PAGOS_VER", "LISTAR_PAGOS"))
                .isInstanceOf(AccessDeniedException.class).hasMessage("Actor requerido");

        verify(auditFailures).registrarEscalamiento(null, "LISTAR_PAGOS");
        verify(auditFailures).registrarEscalamiento(withoutId, "LISTAR_PAGOS");
    }

    @Test
    void permisoIsCheckedAgainstCurrentMembershipAndReturnsPersistedUser() {
        Usuario actor = user(10L);
        Usuario persisted = user(10L);
        TenantMembership membership = mock(TenantMembership.class);
        when(membership.permissionCodes())
                .thenReturn(Set.of())
                .thenReturn(Set.of("PAGOS_VER"));
        when(membership.getUsuario()).thenReturn(persisted);
        when(tenantAccess.currentAccess(actor)).thenReturn(new TenantAccess(membership));

        assertThatThrownBy(() -> rbac.exigirPermiso(actor, "PAGOS_VER", "LISTAR_PAGOS"))
                .isInstanceOf(AccessDeniedException.class)
                .hasMessage("Permiso requerido: PAGOS_VER");
        assertThat(rbac.exigirPermiso(actor, "PAGOS_VER", "LISTAR_PAGOS")).isSameAs(persisted);
        verify(auditFailures).registrarEscalamiento(actor, "LISTAR_PAGOS");
    }

    @Test
    void superadminRequiresIdentifiedActorAndActiveTenantRole() {
        Usuario withoutId = new Usuario();
        assertThatThrownBy(() -> rbac.exigirSuperadminSistema(null, "CAMBIAR_ROL"))
                .isInstanceOf(AccessDeniedException.class)
                .hasMessage("SUPERADMIN autenticado requerido");
        assertThatThrownBy(() -> rbac.exigirSuperadminSistema(withoutId, "CAMBIAR_ROL"))
                .isInstanceOf(AccessDeniedException.class)
                .hasMessage("SUPERADMIN autenticado requerido");

        Usuario actor = user(11L);
        Usuario persisted = user(11L);
        TenantMembership membership = mock(TenantMembership.class);
        when(membership.isSuperadmin()).thenReturn(false, true);
        when(membership.getUsuario()).thenReturn(persisted);
        TenantAccess access = new TenantAccess(membership);
        when(tenantAccess.currentAccess(actor)).thenReturn(access);

        assertThatThrownBy(() -> rbac.exigirSuperadminSistema(actor, "CAMBIAR_ROL"))
                .isInstanceOf(AccessDeniedException.class)
                .hasMessage("La operaci\u00f3n requiere SUPERADMIN del tenant");
        assertThat(rbac.exigirSuperadminSistema(actor, "CAMBIAR_ROL")).isSameAs(persisted);
        assertThat(rbac.accesoActual(actor)).isSameAs(access);
        verify(auditFailures).registrarEscalamiento(actor, "CAMBIAR_ROL");
    }

    private static Usuario user(long id) {
        Usuario user = new Usuario();
        user.setId(id);
        user.setActivo(true);
        return user;
    }
}
