package gestudio.tenancy;

import gestudio.dto.usuario.response.UsuarioResponse;
import gestudio.entidades.Rol;
import gestudio.entidades.Usuario;
import gestudio.infra.errores.TratadorDeErrores.OperacionNoPermitidaException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.Instant;
import java.util.Collection;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

@Service
public class TenantMembershipManagementService {
    private final TenantRepository tenants;
    private final TenantMembershipRepository memberships;
    private final TenantMembershipRoleRepository membershipRoles;
    private final Clock clock;

    public TenantMembershipManagementService(TenantRepository tenants,
                                             TenantMembershipRepository memberships,
                                             TenantMembershipRoleRepository membershipRoles,
                                             Clock clock) {
        this.tenants = tenants;
        this.memberships = memberships;
        this.membershipRoles = membershipRoles;
        this.clock = clock;
    }

    public TenantMembership create(Usuario user, Collection<Rol> roles, Usuario actor) {
        UUID tenantId = TenantContext.requireTenantId();
        Tenant tenant = tenants.findById(tenantId)
                .filter(value -> value.getStatus() == TenantStatus.ACTIVE)
                .orElseThrow(() -> new IllegalStateException("Active tenant context required"));
        Instant now = clock.instant();
        TenantMembership membership = new TenantMembership();
        membership.setId(UUID.randomUUID());
        membership.setTenant(tenant);
        membership.setUsuario(user);
        membership.setStatus(TenantMembershipStatus.ACTIVE);
        membership.setSecurityVersion(0L);
        membership.setValidFrom(now);
        membership.setCreatedAt(now);
        membership.setUpdatedAt(now);
        memberships.save(membership);
        List<TenantMembershipRole> assignments = assignments(membership, tenant, roles, actor);
        membershipRoles.saveAll(assignments);
        membership.setRoleAssignments(new LinkedHashSet<>(assignments));
        return membership;
    }

    @Transactional
    public TenantMembership update(Long userId, Collection<Rol> requestedRoles, Boolean active, Usuario actor) {
        UUID tenantId = TenantContext.requireTenantId();
        // Serialize tenant and platform mutations before taking membership
        // locks. The tenant DB role has SELECT-only access to tenants.
        lockCurrentTenant();
        TenantMembership membership = memberships.findByTenantAndUserForUpdate(tenantId, userId)
                .orElseThrow(() -> new IllegalArgumentException("Usuario no encontrado en el tenant"));
        Set<Rol> currentRoles = membership.roles();
        Set<Rol> nextRoles = requestedRoles == null || requestedRoles.isEmpty()
                ? currentRoles
                : new LinkedHashSet<>(requestedRoles);
        TenantMembershipStatus nextStatus = active == null
                ? membership.getStatus()
                : active ? TenantMembershipStatus.ACTIVE : TenantMembershipStatus.SUSPENDED;

        boolean rolesChanged = !roleIds(currentRoles).equals(roleIds(nextRoles));
        boolean statusChanged = membership.getStatus() != nextStatus;
        Instant now = clock.instant();
        boolean currentlyEffective = membership.getStatus() == TenantMembershipStatus.ACTIVE
                && membership.getUsuario().isEnabled()
                && !membership.getValidFrom().isAfter(now)
                && (membership.getValidUntil() == null || membership.getValidUntil().isAfter(now));
        if (currentlyEffective
                && membership.isSuperadmin()
                && (!containsSuperadmin(nextRoles) || nextStatus != TenantMembershipStatus.ACTIVE)
                && memberships.countActiveSuperadmins(tenantId, now) <= 1) {
            throw new OperacionNoPermitidaException(
                    "No se puede degradar o suspender al último SUPERADMIN activo del tenant");
        }
        if (currentlyEffective
                && hasAdministratorRole(currentRoles)
                && (!hasAdministratorRole(nextRoles) || nextStatus != TenantMembershipStatus.ACTIVE)
                && memberships.countActiveAdministrators(tenantId, now) <= 1) {
            throw new OperacionNoPermitidaException(
                    "No se puede degradar o suspender al último ADMINISTRADOR activo del tenant");
        }

        if (rolesChanged) {
            membershipRoles.deleteByMembershipId(membership.getId());
            List<TenantMembershipRole> assignments =
                    assignments(membership, membership.getTenant(), nextRoles, actor);
            membershipRoles.saveAll(assignments);
            membership.setRoleAssignments(new LinkedHashSet<>(assignments));
        }
        if (rolesChanged || statusChanged) {
            membership.setStatus(nextStatus);
            membership.setSecurityVersion(membership.getSecurityVersion() + 1);
            membership.setUpdatedAt(clock.instant());
            memberships.save(membership);
        }
        return membership;
    }

    /** Must run inside the calling use case transaction, before changing any identity. */
    public void lockCurrentTenant() {
        tenants.lockAdministratorMutations(TenantContext.requireTenantId());
    }

    public TenantMembership require(Long userId) {
        return memberships.findForTenantAndUser(TenantContext.requireTenantId(), userId)
                .orElseThrow(() -> new IllegalArgumentException("Usuario no encontrado en el tenant"));
    }

    public List<TenantMembership> list() {
        return memberships.findAllForTenant(TenantContext.requireTenantId());
    }

    public UsuarioResponse response(TenantMembership membership) {
        TenantSelection tenant = new TenantSelection(
                membership.getTenant().getId(),
                membership.getTenant().getCode(),
                membership.getTenant().getName(),
                membership.getTenant().getStatus()
        );
        TenantSummaryResponse summary = TenantSummaryResponse.from(tenant);
        return new UsuarioResponse(
                membership.getUsuario().getId(),
                membership.getUsuario().getNombreUsuario(),
                membership.roleCodes().stream().sorted().toList(),
                membership.permissionCodes().stream().sorted().toList(),
                membership.getStatus() == TenantMembershipStatus.ACTIVE,
                summary,
                List.of(summary)
        );
    }

    private static List<TenantMembershipRole> assignments(TenantMembership membership, Tenant tenant,
                                                           Collection<Rol> roles, Usuario actor) {
        return roles.stream()
                .map(role -> new TenantMembershipRole(membership, tenant, role, actor))
                .toList();
    }

    private static Set<Long> roleIds(Collection<Rol> roles) {
        Set<Long> result = new LinkedHashSet<>();
        roles.stream().map(Rol::getId).forEach(result::add);
        return result;
    }

    private static boolean containsSuperadmin(Collection<Rol> roles) {
        return roles.stream().anyMatch(Rol::esSuperadminSistema);
    }

    private static boolean hasAdministratorRole(Collection<Rol> roles) {
        return roles.stream().anyMatch(role -> role.estaActivo()
                && "ADMINISTRADOR".equalsIgnoreCase(role.getCodigo()));
    }
}
