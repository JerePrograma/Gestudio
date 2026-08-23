package gestudio.tenancy;

import gestudio.entidades.Usuario;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.access.AccessDeniedException;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.reset;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class TenantAccessServiceTest {
    private static final Instant NOW = Instant.parse("2026-08-21T12:00:00Z");
    private static final long USER_ID = 17L;
    private static final UUID TENANT_A = UUID.fromString("11111111-1111-1111-1111-111111111111");
    private static final UUID TENANT_B = UUID.fromString("22222222-2222-2222-2222-222222222222");
    private static final UUID MEMBERSHIP_ID = UUID.fromString("33333333-3333-3333-3333-333333333333");

    @Mock private TenantMembershipRepository memberships;

    private TenantAccessService service;

    @BeforeEach
    void setUp() {
        service = new TenantAccessService(memberships, Clock.fixed(NOW, ZoneOffset.UTC));
    }

    @AfterEach
    void clearTenantContext() {
        TenantContext.clear();
    }

    @Test
    void activeSelectionsExposeOnlyMembershipsWithAnActiveRole() {
        TenantSelection allowed = selection(TENANT_A);
        TenantSelection withoutRole = selection(TENANT_B);
        TenantMembership allowedMembership = membership(TENANT_A, 3, 5, true);
        TenantMembership membershipWithoutRole = membership(TENANT_B, 3, 5, false);
        when(memberships.findActiveSelections(USER_ID, NOW)).thenReturn(List.of(allowed, withoutRole));
        when(memberships.findActiveAccess(USER_ID, TENANT_A, NOW))
                .thenReturn(Optional.of(allowedMembership));
        when(memberships.findActiveAccess(USER_ID, TENANT_B, NOW))
                .thenReturn(Optional.of(membershipWithoutRole));

        assertThat(service.activeSelections(USER_ID)).containsExactly(allowed);
        assertThat(TenantContext.currentTenantId()).isEmpty();
    }

    @Test
    void revalidateRejectsMissingRolesAndEitherSecurityVersionMismatch() {
        TenantMembership withoutRoles = membership(TENANT_A, 3, 5, false);
        TenantMembership staleTenant = membership(TENANT_A, 2, 5, true);
        TenantMembership staleMembership = membership(TENANT_A, 3, 4, true);
        TenantMembership valid = membership(TENANT_A, 3, 5, true);
        when(memberships.findActiveAccess(USER_ID, MEMBERSHIP_ID, TENANT_A, NOW))
                .thenReturn(Optional.of(withoutRoles), Optional.of(staleTenant),
                        Optional.of(staleMembership), Optional.of(valid));

        assertThat(service.revalidate(USER_ID, MEMBERSHIP_ID, TENANT_A, 3, 5)).isEmpty();
        assertThat(service.revalidate(USER_ID, MEMBERSHIP_ID, TENANT_A, 3, 5)).isEmpty();
        assertThat(service.revalidate(USER_ID, MEMBERSHIP_ID, TENANT_A, 3, 5)).isEmpty();
        assertThat(service.revalidate(USER_ID, MEMBERSHIP_ID, TENANT_A, 3, 5))
                .get().extracting(TenantAccess::membership).isSameAs(valid);
        assertThat(TenantContext.currentTenantId()).isEmpty();
    }

    @Test
    void currentAccessRequiresActorMembershipContextActiveMembershipAndRoles() {
        assertThatThrownBy(() -> service.currentAccess(null))
                .isInstanceOf(AccessDeniedException.class).hasMessage("Actor requerido");
        assertThatThrownBy(() -> service.currentAccess(new Usuario()))
                .isInstanceOf(AccessDeniedException.class).hasMessage("Actor requerido");

        Usuario actor = user();
        try (TenantContext.Scope ignored = TenantContext.open(TENANT_A, null)) {
            assertThatThrownBy(() -> service.currentAccess(actor))
                    .isInstanceOf(AccessDeniedException.class).hasMessage("Membership requerida");
        }

        TenantMembership withoutRoles = membership(TENANT_A, 3, 5, false);
        TenantMembership valid = membership(TENANT_A, 3, 5, true);
        when(memberships.findActiveAccess(USER_ID, MEMBERSHIP_ID, TENANT_A, NOW))
                .thenReturn(Optional.empty(), Optional.of(withoutRoles), Optional.of(valid));
        try (TenantContext.Scope ignored = TenantContext.open(TENANT_A, MEMBERSHIP_ID)) {
            assertThatThrownBy(() -> service.currentAccess(actor))
                    .isInstanceOf(AccessDeniedException.class)
                    .hasMessage("Membership inactiva o revocada");
            assertThatThrownBy(() -> service.currentAccess(actor))
                    .isInstanceOf(AccessDeniedException.class)
                    .hasMessage("Membership inactiva o revocada");
            assertThat(service.currentAccess(actor).membership()).isSameAs(valid);
        }
    }

    @Test
    void requireSelectedAutoSelectsOneTenantAndRejectsAmbiguityOrUnauthorizedTenant() {
        TenantSelection first = selection(TENANT_A);
        TenantSelection second = selection(TENANT_B);
        TenantMembership firstMembership = membership(TENANT_A, 3, 5, true);
        TenantMembership secondMembership = membership(TENANT_B, 3, 5, true);

        when(memberships.findActiveSelections(USER_ID, NOW)).thenReturn(List.of(first));
        when(memberships.findActiveAccess(USER_ID, TENANT_A, NOW))
                .thenReturn(Optional.of(firstMembership));
        assertThat(service.requireSelected(USER_ID, null).tenantId()).isEqualTo(TENANT_A);

        reset(memberships);
        when(memberships.findActiveSelections(USER_ID, NOW)).thenReturn(List.of(first, second));
        when(memberships.findActiveAccess(USER_ID, TENANT_A, NOW))
                .thenReturn(Optional.of(firstMembership));
        when(memberships.findActiveAccess(USER_ID, TENANT_B, NOW))
                .thenReturn(Optional.of(secondMembership));
        assertThatThrownBy(() -> service.requireSelected(USER_ID, null))
                .isInstanceOf(AccessDeniedException.class).hasMessage("Tenant no autorizado");

        reset(memberships);
        when(memberships.findActiveSelections(USER_ID, NOW)).thenReturn(List.of(first));
        when(memberships.findActiveAccess(USER_ID, TENANT_A, NOW))
                .thenReturn(Optional.of(firstMembership));
        assertThatThrownBy(() -> service.requireSelected(USER_ID, TENANT_B))
                .isInstanceOf(AccessDeniedException.class).hasMessage("Tenant no autorizado");

        reset(memberships);
        when(memberships.findActiveSelections(USER_ID, NOW)).thenReturn(List.of(first));
        when(memberships.findActiveAccess(USER_ID, TENANT_A, NOW))
                .thenReturn(Optional.of(firstMembership), Optional.empty());
        assertThatThrownBy(() -> service.requireSelected(USER_ID, TENANT_A))
                .isInstanceOf(AccessDeniedException.class).hasMessage("Tenant no autorizado");
    }

    private static TenantSelection selection(UUID tenantId) {
        return new TenantSelection(tenantId, tenantId.toString(), "Tenant " + tenantId, TenantStatus.ACTIVE);
    }

    private static Usuario user() {
        Usuario actor = new Usuario();
        actor.setId(USER_ID);
        actor.setNombreUsuario("operator");
        actor.setActivo(true);
        return actor;
    }

    private static TenantMembership membership(UUID tenantId, long tenantVersion,
                                                long membershipVersion, boolean withRoles) {
        Tenant tenant = new Tenant();
        tenant.setId(tenantId);
        tenant.setSecurityVersion(tenantVersion);
        tenant.setStatus(TenantStatus.ACTIVE);
        TenantMembership membership = new TenantMembership();
        membership.setTenant(tenant);
        membership.setId(MEMBERSHIP_ID);
        membership.setSecurityVersion(membershipVersion);
        if (withRoles) {
            var role = new gestudio.entidades.Rol(7L, "OPERADOR", true);
            membership.getRoleAssignments().add(new TenantMembershipRole(membership, tenant, role));
        }
        return membership;
    }
}
