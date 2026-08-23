package gestudio.tenancy;

import gestudio.entidades.Permiso;
import gestudio.entidades.Rol;
import gestudio.entidades.Usuario;
import gestudio.infra.errores.TratadorDeErrores.OperacionNoPermitidaException;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class TenantMembershipManagementServiceTest {
    private static final Instant NOW = Instant.parse("2026-08-21T12:00:00Z");
    private static final UUID TENANT_ID = UUID.fromString("11111111-1111-1111-1111-111111111111");
    private static final UUID MEMBERSHIP_ID = UUID.fromString("22222222-2222-2222-2222-222222222222");

    @Mock private TenantRepository tenants;
    @Mock private TenantMembershipRepository memberships;
    @Mock private TenantMembershipRoleRepository membershipRoles;

    private TenantMembershipManagementService service;
    private Tenant tenant;
    private Usuario actor;
    private Usuario target;
    private Rol superadmin;
    private Rol operator;

    @BeforeEach
    void setUp() {
        service = new TenantMembershipManagementService(tenants, memberships, membershipRoles,
                Clock.fixed(NOW, ZoneOffset.UTC));
        tenant = tenant(TenantStatus.ACTIVE);
        actor = user(1L, "actor");
        target = user(10L, "target");
        superadmin = role(1L, "SUPERADMIN", true);
        operator = role(2L, "OPERADOR", true);
        TenantContext.open(TENANT_ID, null);
    }

    @AfterEach
    void clearTenantContext() {
        TenantContext.clear();
    }

    @Test
    void createRequiresActiveTenantAndPersistsAssignmentsWithActor() {
        when(tenants.findById(TENANT_ID))
                .thenReturn(Optional.empty())
                .thenReturn(Optional.of(tenant(TenantStatus.SUSPENDED)))
                .thenReturn(Optional.of(tenant));

        for (int attempt = 0; attempt < 2; attempt++) {
            assertThatThrownBy(() -> service.create(target, List.of(operator), actor))
                    .isInstanceOf(IllegalStateException.class)
                    .hasMessage("Active tenant context required");
        }

        TenantMembership created = service.create(target, List.of(superadmin, operator), actor);
        assertThat(created.getTenant()).isSameAs(tenant);
        assertThat(created.getUsuario()).isSameAs(target);
        assertThat(created.getStatus()).isEqualTo(TenantMembershipStatus.ACTIVE);
        assertThat(created.getSecurityVersion()).isZero();
        assertThat(created.getRoleAssignments()).hasSize(2)
                .allSatisfy(assignment -> assertThat(assignment.getAssignedBy()).isSameAs(actor));
        verify(memberships).save(created);
        verify(membershipRoles).saveAll(any());
    }

    @Test
    void updateWithNullOrEmptyInputPreservesRolesAndStatusWithoutWrite() {
        TenantMembership membership = membership(TenantMembershipStatus.ACTIVE, 4L, operator);
        when(memberships.findByTenantAndUserForUpdate(TENANT_ID, target.getId()))
                .thenReturn(Optional.of(membership));

        assertThat(service.update(target.getId(), null, null, actor)).isSameAs(membership);
        assertThat(service.update(target.getId(), List.of(), null, actor)).isSameAs(membership);

        verify(membershipRoles, never()).deleteByMembershipId(any());
        verify(memberships, never()).save(any());
    }

    @Test
    void roleAndStatusChangesReplaceAssignmentsAndIncrementSecurityVersionOnce() {
        TenantMembership membership = membership(TenantMembershipStatus.ACTIVE, 4L, operator);
        when(memberships.findByTenantAndUserForUpdate(TENANT_ID, target.getId()))
                .thenReturn(Optional.of(membership));

        assertThat(service.update(target.getId(), List.of(superadmin), false, actor))
                .isSameAs(membership);

        assertThat(membership.getStatus()).isEqualTo(TenantMembershipStatus.SUSPENDED);
        assertThat(membership.getSecurityVersion()).isEqualTo(5L);
        assertThat(membership.getUpdatedAt()).isEqualTo(NOW);
        assertThat(membership.roleCodes()).containsExactly("SUPERADMIN");
        verify(membershipRoles).deleteByMembershipId(MEMBERSHIP_ID);
        verify(memberships).save(membership);
    }

    @Test
    void activeLastSuperadminCannotLoseRoleOrBeSuspended() {
        TenantMembership membership = membership(TenantMembershipStatus.ACTIVE, 4L, superadmin);
        when(memberships.findByTenantAndUserForUpdate(TENANT_ID, target.getId()))
                .thenReturn(Optional.of(membership));
        when(memberships.countActiveSuperadmins(TENANT_ID)).thenReturn(1L);

        assertThatThrownBy(() -> service.update(
                target.getId(), List.of(operator), true, actor))
                .isInstanceOf(OperacionNoPermitidaException.class)
                .hasMessageContaining("último SUPERADMIN");
        assertThatThrownBy(() -> service.update(
                target.getId(), List.of(superadmin), false, actor))
                .isInstanceOf(OperacionNoPermitidaException.class)
                .hasMessageContaining("último SUPERADMIN");
    }

    @Test
    void nonActiveNonSuperadminOrRedundantSuperadminChangeSkipsLastAdminGuard() {
        TenantMembership suspended = membership(TenantMembershipStatus.SUSPENDED, 2L, superadmin);
        TenantMembership operatorMembership = membership(TenantMembershipStatus.ACTIVE, 2L, operator);
        TenantMembership unchangedAdmin = membership(TenantMembershipStatus.ACTIVE, 2L, superadmin);
        when(memberships.findByTenantAndUserForUpdate(TENANT_ID, target.getId()))
                .thenReturn(Optional.of(suspended))
                .thenReturn(Optional.of(operatorMembership))
                .thenReturn(Optional.of(unchangedAdmin));

        service.update(target.getId(), List.of(operator), true, actor);
        service.update(target.getId(), List.of(operator), false, actor);
        service.update(target.getId(), List.of(superadmin), true, actor);

        verify(memberships, never()).countActiveSuperadmins(TENANT_ID);
    }

    @Test
    void anotherActiveSuperadminAllowsSuspension() {
        TenantMembership membership = membership(TenantMembershipStatus.ACTIVE, 4L, superadmin);
        when(memberships.findByTenantAndUserForUpdate(TENANT_ID, target.getId()))
                .thenReturn(Optional.of(membership));
        when(memberships.countActiveSuperadmins(TENANT_ID)).thenReturn(2L);

        service.update(target.getId(), List.of(superadmin), false, actor);

        assertThat(membership.getStatus()).isEqualTo(TenantMembershipStatus.SUSPENDED);
        verify(memberships).save(membership);
    }

    @Test
    void requireListAndResponseExposeOnlyCurrentTenantMembershipData() {
        Permiso read = permission(5L, "ALUMNOS_VER", true);
        operator.getPermisos().add(read);
        TenantMembership active = membership(TenantMembershipStatus.ACTIVE, 1L, operator);
        TenantMembership suspended = membership(TenantMembershipStatus.SUSPENDED, 2L, operator);
        when(memberships.findForTenantAndUser(TENANT_ID, target.getId()))
                .thenReturn(Optional.of(active))
                .thenReturn(Optional.empty());
        when(memberships.findAllForTenant(TENANT_ID)).thenReturn(List.of(active, suspended));

        assertThat(service.require(target.getId())).isSameAs(active);
        assertThatThrownBy(() -> service.require(target.getId()))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessage("Usuario no encontrado en el tenant");
        assertThat(service.list()).containsExactly(active, suspended);

        var activeResponse = service.response(active);
        var suspendedResponse = service.response(suspended);
        assertThat(activeResponse.roles()).containsExactly("OPERADOR");
        assertThat(activeResponse.permisos()).containsExactly("ALUMNOS_VER");
        assertThat(activeResponse.activo()).isTrue();
        assertThat(activeResponse.tenantActivo().id()).isEqualTo(TENANT_ID);
        assertThat(activeResponse.tenantsDisponibles()).containsExactly(activeResponse.tenantActivo());
        assertThat(suspendedResponse.activo()).isFalse();
    }

    private TenantMembership membership(TenantMembershipStatus status, long version, Rol... roles) {
        TenantMembership membership = new TenantMembership();
        membership.setId(MEMBERSHIP_ID);
        membership.setTenant(tenant);
        membership.setUsuario(target);
        membership.setStatus(status);
        membership.setSecurityVersion(version);
        membership.setValidFrom(NOW.minusSeconds(3600));
        membership.setCreatedAt(NOW.minusSeconds(3600));
        membership.setUpdatedAt(NOW.minusSeconds(60));
        for (Rol role : roles) {
            membership.getRoleAssignments().add(new TenantMembershipRole(membership, tenant, role, actor));
        }
        return membership;
    }

    private static Tenant tenant(TenantStatus status) {
        Tenant tenant = new Tenant();
        tenant.setId(TENANT_ID);
        tenant.setCode("tenant");
        tenant.setName("Tenant");
        tenant.setStatus(status);
        tenant.setSecurityVersion(1L);
        return tenant;
    }

    private static Usuario user(long id, String username) {
        Usuario user = new Usuario();
        user.setId(id);
        user.setNombreUsuario(username);
        user.setActivo(true);
        return user;
    }

    private static Rol role(long id, String code, boolean active) {
        Rol role = new Rol(id, code, active);
        role.setCodigo(code);
        return role;
    }

    private static Permiso permission(long id, String code, boolean active) {
        Permiso permission = new Permiso();
        permission.setId(id);
        permission.setCodigo(code);
        permission.setActivo(active);
        return permission;
    }
}
