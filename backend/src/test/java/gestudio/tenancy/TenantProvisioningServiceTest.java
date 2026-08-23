package gestudio.tenancy;

import gestudio.auditoria.application.AuditService;
import gestudio.entidades.Permiso;
import gestudio.entidades.Rol;
import gestudio.entidades.Usuario;
import gestudio.repositorios.PermisoRepositorio;
import gestudio.repositorios.RolRepositorio;
import gestudio.repositorios.UsuarioRepositorio;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.TransactionStatus;

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
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class TenantProvisioningServiceTest {
    private static final Instant NOW = Instant.parse("2026-08-21T12:00:00Z");
    private static final UUID TENANT_ID = UUID.fromString("11111111-1111-1111-1111-111111111111");
    private static final UUID MEMBERSHIP_ID = UUID.fromString("22222222-2222-2222-2222-222222222222");

    @Mock private PlatformAdminAccessService platformAccess;
    @Mock private TenantRepository tenants;
    @Mock private TenantMembershipRepository memberships;
    @Mock private TenantMembershipRoleRepository membershipRoles;
    @Mock private UsuarioRepositorio users;
    @Mock private RolRepositorio roles;
    @Mock private PermisoRepositorio permissions;
    @Mock private AuditService audit;

    private TenantProvisioningService service;
    private Usuario actor;

    @BeforeEach
    void setUp() {
        PlatformTransactionManager manager = mock(PlatformTransactionManager.class);
        when(manager.getTransaction(any(TransactionDefinition.class)))
                .thenReturn(mock(TransactionStatus.class));
        service = new TenantProvisioningService(platformAccess, tenants, memberships,
                membershipRoles, users, roles, permissions, audit,
                Clock.fixed(NOW, ZoneOffset.UTC), manager);
        actor = user(1L, true);
    }

    @AfterEach
    void clearTenantContext() {
        TenantContext.clear();
    }

    @Test
    void createTenantNormalizesInputMaterializesOnlyActivePermissionsAndInitialAdmin() {
        Usuario initialAdmin = user(10L, true);
        Permiso active = permission(1L, "TENANT_READ", true);
        Permiso inactive = permission(2L, "TENANT_DELETE", false);
        when(tenants.findByCodeIgnoreCase("academy-one")).thenReturn(Optional.empty());
        when(users.findById(10L)).thenReturn(Optional.of(initialAdmin));
        when(permissions.findAll()).thenReturn(List.of(active, inactive));
        when(roles.saveAndFlush(any(Rol.class))).thenAnswer(invocation -> invocation.getArgument(0));
        when(memberships.save(any(TenantMembership.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        TenantProvisioningService.ProvisionedTenant provisioned =
                service.createTenant("  Academy-One  ", "  Academy One  ", 10L, actor);

        assertThat(provisioned.tenant().getCode()).isEqualTo("academy-one");
        assertThat(provisioned.tenant().getName()).isEqualTo("Academy One");
        assertThat(provisioned.tenant().getStatus()).isEqualTo(TenantStatus.ACTIVE);
        assertThat(provisioned.tenant().getSecurityVersion()).isZero();
        assertThat(provisioned.initialAdminMembership().getUsuario()).isSameAs(initialAdmin);
        assertThat(provisioned.initialAdminMembership().getStatus())
                .isEqualTo(TenantMembershipStatus.ACTIVE);
        assertThat(provisioned.initialAdminMembership().getValidFrom()).isEqualTo(NOW);

        ArgumentCaptor<Rol> role = ArgumentCaptor.forClass(Rol.class);
        verify(roles).saveAndFlush(role.capture());
        assertThat(role.getValue().getCodigo()).isEqualTo("SUPERADMIN");
        assertThat(role.getValue().getPermisos()).containsExactly(active);
        verify(membershipRoles).saveAll(any());
        verify(audit).registrar(eq("SEGURIDAD"), eq("PLATFORM_TENANT_CREATED"),
                eq("TENANT"), eq(provisioned.tenant().getId().toString()), eq(actor),
                eq(null), any());
        assertThat(TenantContext.currentTenantId()).isEmpty();
    }

    @Test
    void createTenantRejectsDuplicateCodeAndMissingOrInactiveAdmin() {
        when(tenants.findByCodeIgnoreCase("duplicate"))
                .thenReturn(Optional.of(tenant(TenantStatus.ACTIVE)));
        assertThatThrownBy(() -> service.createTenant(" Duplicate ", "Tenant", 10L, actor))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessage("Tenant code already exists");

        when(tenants.findByCodeIgnoreCase("new-tenant")).thenReturn(Optional.empty());
        when(users.findById(10L)).thenReturn(Optional.empty(), Optional.of(user(10L, false)));
        for (int attempt = 0; attempt < 2; attempt++) {
            assertThatThrownBy(() -> service.createTenant("new-tenant", "Tenant", 10L, actor))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessage("Active user not found");
        }
        verify(tenants, never()).save(any());
    }

    @Test
    void tenantStatusNoOpIsIdempotentAndRealChangeIncrementsSecurityVersion() {
        Tenant unchanged = tenant(TenantStatus.ACTIVE);
        Tenant changed = tenant(TenantStatus.ACTIVE);
        when(tenants.findByIdForUpdate(TENANT_ID))
                .thenReturn(Optional.of(unchanged))
                .thenReturn(Optional.of(changed))
                .thenReturn(Optional.empty());

        assertThat(service.changeTenantStatus(TENANT_ID, TenantStatus.ACTIVE, actor))
                .isSameAs(unchanged);
        assertThat(service.changeTenantStatus(TENANT_ID, TenantStatus.SUSPENDED, actor))
                .isSameAs(changed);
        assertThat(changed.getStatus()).isEqualTo(TenantStatus.SUSPENDED);
        assertThat(changed.getSecurityVersion()).isEqualTo(4L);
        assertThat(changed.getUpdatedAt()).isEqualTo(NOW);
        verify(tenants).save(changed);

        assertThatThrownBy(() -> service.changeTenantStatus(
                TENANT_ID, TenantStatus.ACTIVE, actor))
                .isInstanceOf(IllegalArgumentException.class).hasMessage("Tenant not found");
    }

    @Test
    void grantMembershipRequiresActiveTenantFutureValidityAndAtLeastOneActiveRole() {
        Tenant inactive = tenant(TenantStatus.SUSPENDED);
        when(tenants.findByIdForUpdate(TENANT_ID))
                .thenReturn(Optional.empty())
                .thenReturn(Optional.of(inactive));
        for (int attempt = 0; attempt < 2; attempt++) {
            assertThatThrownBy(() -> service.grantMembership(
                    TENANT_ID, 10L, List.of("OPERADOR"), null, actor))
                    .isInstanceOf(AccessDeniedException.class)
                    .hasMessage("Active tenant required");
        }

        Tenant active = tenant(TenantStatus.ACTIVE);
        when(tenants.findByIdForUpdate(TENANT_ID)).thenReturn(Optional.of(active));
        when(users.findById(10L)).thenReturn(Optional.of(user(10L, true)));
        assertThatThrownBy(() -> service.grantMembership(
                TENANT_ID, 10L, List.of("OPERADOR"), NOW, actor))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessage("validUntil must be in the future");

        assertThatThrownBy(() -> service.grantMembership(
                TENANT_ID, 10L, null, null, actor))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessage("At least one role is required");
        assertThatThrownBy(() -> service.grantMembership(
                TENANT_ID, 10L, List.of(), null, actor))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessage("At least one role is required");
    }

    @Test
    void grantMembershipRejectsMissingAndInactiveRoles() {
        Tenant active = tenant(TenantStatus.ACTIVE);
        when(tenants.findByIdForUpdate(TENANT_ID)).thenReturn(Optional.of(active));
        when(users.findById(10L)).thenReturn(Optional.of(user(10L, true)));
        when(roles.findWithPermisosByCodigoIgnoreCase("MISSING")).thenReturn(Optional.empty());
        when(roles.findWithPermisosByCodigoIgnoreCase("INACTIVE"))
                .thenReturn(Optional.of(role(8L, "INACTIVE", false)));

        assertThatThrownBy(() -> service.grantMembership(
                TENANT_ID, 10L, List.of(" MISSING "), null, actor))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessage("Active role not found:  MISSING ");
        assertThatThrownBy(() -> service.grantMembership(
                TENANT_ID, 10L, List.of("INACTIVE"), null, actor))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessage("Active role not found: INACTIVE");
    }

    @Test
    void grantMembershipCreatesThenReactivatesExistingMembershipWithVersionBump() {
        Tenant tenant = tenant(TenantStatus.ACTIVE);
        Usuario target = user(10L, true);
        Rol operator = role(7L, "OPERADOR", true);
        when(tenants.findByIdForUpdate(TENANT_ID)).thenReturn(Optional.of(tenant));
        when(users.findById(10L)).thenReturn(Optional.of(target));
        when(roles.findWithPermisosByCodigoIgnoreCase("OPERADOR"))
                .thenReturn(Optional.of(operator));
        when(memberships.findByTenantAndUserForUpdate(TENANT_ID, 10L))
                .thenReturn(Optional.empty());

        TenantMembership created = service.grantMembership(
                TENANT_ID, 10L, List.of("OPERADOR"), null, actor);
        assertThat(created.getTenant()).isSameAs(tenant);
        assertThat(created.getUsuario()).isSameAs(target);
        assertThat(created.getSecurityVersion()).isZero();
        verify(membershipRoles).deleteByMembershipId(created.getId());

        TenantMembership existing = membership(tenant, target, TenantMembershipStatus.SUSPENDED, 4L);
        when(memberships.findByTenantAndUserForUpdate(TENANT_ID, 10L))
                .thenReturn(Optional.of(existing));
        Instant future = NOW.plusSeconds(3600);
        assertThat(service.grantMembership(
                TENANT_ID, 10L, Set.of("OPERADOR"), future, actor)).isSameAs(existing);
        assertThat(existing.getStatus()).isEqualTo(TenantMembershipStatus.ACTIVE);
        assertThat(existing.getSecurityVersion()).isEqualTo(5L);
        assertThat(existing.getValidUntil()).isEqualTo(future);
    }

    @Test
    void membershipStatusNoOpAndRevokeOrReactivatePreserveAuditState() {
        Tenant tenant = tenant(TenantStatus.ACTIVE);
        Usuario target = user(10L, true);
        TenantMembership unchanged = membership(tenant, target, TenantMembershipStatus.ACTIVE, 2L);
        TenantMembership revoked = membership(tenant, target, TenantMembershipStatus.ACTIVE, 2L);
        TenantMembership reactivated = membership(tenant, target, TenantMembershipStatus.SUSPENDED, 5L);
        when(memberships.findByTenantAndIdForUpdate(TENANT_ID, MEMBERSHIP_ID))
                .thenReturn(Optional.of(unchanged))
                .thenReturn(Optional.of(revoked))
                .thenReturn(Optional.of(reactivated))
                .thenReturn(Optional.empty());

        assertThat(service.changeMembershipStatus(
                TENANT_ID, MEMBERSHIP_ID, TenantMembershipStatus.ACTIVE, actor)).isSameAs(unchanged);
        service.changeMembershipStatus(
                TENANT_ID, MEMBERSHIP_ID, TenantMembershipStatus.REVOKED, actor);
        assertThat(revoked.getValidUntil()).isEqualTo(NOW);
        assertThat(revoked.getSecurityVersion()).isEqualTo(3L);
        service.changeMembershipStatus(
                TENANT_ID, MEMBERSHIP_ID, TenantMembershipStatus.ACTIVE, actor);
        assertThat(reactivated.getValidUntil()).isNull();
        assertThat(reactivated.getSecurityVersion()).isEqualTo(6L);

        assertThatThrownBy(() -> service.changeMembershipStatus(
                TENANT_ID, MEMBERSHIP_ID, TenantMembershipStatus.ACTIVE, actor))
                .isInstanceOf(IllegalArgumentException.class).hasMessage("Membership not found");
    }

    private static Tenant tenant(TenantStatus status) {
        Tenant tenant = new Tenant();
        tenant.setId(TENANT_ID);
        tenant.setCode("tenant");
        tenant.setName("Tenant");
        tenant.setStatus(status);
        tenant.setSecurityVersion(3L);
        tenant.setCreatedAt(NOW.minusSeconds(3600));
        tenant.setUpdatedAt(NOW.minusSeconds(60));
        return tenant;
    }

    private static TenantMembership membership(Tenant tenant, Usuario user,
                                               TenantMembershipStatus status, long version) {
        TenantMembership membership = new TenantMembership();
        membership.setId(MEMBERSHIP_ID);
        membership.setTenant(tenant);
        membership.setUsuario(user);
        membership.setStatus(status);
        membership.setSecurityVersion(version);
        membership.setValidFrom(NOW.minusSeconds(3600));
        membership.setCreatedAt(NOW.minusSeconds(3600));
        membership.setUpdatedAt(NOW.minusSeconds(60));
        return membership;
    }

    private static Usuario user(long id, boolean active) {
        Usuario user = new Usuario();
        user.setId(id);
        user.setNombreUsuario("user-" + id);
        user.setActivo(active);
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
