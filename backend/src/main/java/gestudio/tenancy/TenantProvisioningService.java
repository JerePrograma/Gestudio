package gestudio.tenancy;

import gestudio.auditoria.application.AuditService;
import gestudio.entidades.Permiso;
import gestudio.entidades.Rol;
import gestudio.entidades.Usuario;
import gestudio.repositorios.PermisoRepositorio;
import gestudio.repositorios.RolRepositorio;
import gestudio.repositorios.UsuarioRepositorio;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

import java.time.Clock;
import java.time.Instant;
import java.util.Collection;
import java.util.LinkedHashSet;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.function.Supplier;

@Service
public class TenantProvisioningService {
    private final PlatformAdminAccessService platformAccess;
    private final TenantRepository tenants;
    private final TenantMembershipRepository memberships;
    private final TenantMembershipRoleRepository membershipRoles;
    private final UsuarioRepositorio users;
    private final RolRepositorio roles;
    private final PermisoRepositorio permissions;
    private final AuditService audit;
    private final Clock clock;
    private final TransactionTemplate transactions;

    public TenantProvisioningService(PlatformAdminAccessService platformAccess,
                                     TenantRepository tenants,
                                     TenantMembershipRepository memberships,
                                     TenantMembershipRoleRepository membershipRoles,
                                     UsuarioRepositorio users,
                                     RolRepositorio roles,
                                     PermisoRepositorio permissions,
                                     AuditService audit,
                                     Clock clock,
                                     PlatformTransactionManager transactionManager) {
        this.platformAccess = platformAccess;
        this.tenants = tenants;
        this.memberships = memberships;
        this.membershipRoles = membershipRoles;
        this.users = users;
        this.roles = roles;
        this.permissions = permissions;
        this.audit = audit;
        this.clock = clock;
        this.transactions = new TransactionTemplate(transactionManager);
    }

    public ProvisionedTenant createTenant(String code, String name, Long initialAdminUserId, Usuario actor) {
        platformAccess.requireProvisioningCapability(actor, "PLATFORM_TENANT_CREATE");
        UUID tenantId = UUID.randomUUID();
        return inTenantTransaction(tenantId, () -> {
            String normalizedCode = code.trim().toLowerCase(Locale.ROOT);
            if (tenants.findByCodeIgnoreCase(normalizedCode).isPresent()) {
                throw new IllegalArgumentException("Tenant code already exists");
            }
            Usuario initialAdmin = activeUser(initialAdminUserId);
            Instant now = clock.instant();

            Tenant tenant = new Tenant();
            tenant.setId(tenantId);
            tenant.setCode(normalizedCode);
            tenant.setName(name.trim());
            tenant.setStatus(TenantStatus.ACTIVE);
            tenant.setSecurityVersion(0L);
            tenant.setCreatedAt(now);
            tenant.setUpdatedAt(now);
            tenants.save(tenant);

            Rol superadmin = new Rol();
            superadmin.setDescripcion("SUPERADMIN");
            superadmin.setCodigo("SUPERADMIN");
            superadmin.setNombre("Superadministrador");
            superadmin.setDescripcionFuncional("Administración completa dentro del tenant");
            superadmin.setActivo(true);
            superadmin.setSistema(true);
            superadmin.setEditable(false);
            permissions.findAll().stream().filter(Permiso::estaActivo)
                    .forEach(superadmin.getPermisos()::add);
            superadmin = roles.saveAndFlush(superadmin);

            TenantMembership membership = newMembership(tenant, initialAdmin, null, now);
            memberships.save(membership);
            membershipRoles.saveAll(Set.of(new TenantMembershipRole(membership, tenant, superadmin)));

            audit.registrar("SEGURIDAD", "PLATFORM_TENANT_CREATED", "TENANT", tenantId.toString(),
                    actor, null, Map.of("code", normalizedCode, "initialAdminUserId", initialAdminUserId));
            return new ProvisionedTenant(tenant, membership);
        });
    }

    public Tenant changeTenantStatus(UUID tenantId, TenantStatus status, Usuario actor) {
        platformAccess.requireProvisioningCapability(actor, "PLATFORM_TENANT_STATUS");
        return inTenantTransaction(tenantId, () -> {
            Tenant tenant = tenants.findByIdForUpdate(tenantId)
                    .orElseThrow(() -> new IllegalArgumentException("Tenant not found"));
            TenantStatus previous = tenant.getStatus();
            if (previous == status) {
                return tenant;
            }
            tenant.setStatus(status);
            tenant.setSecurityVersion(tenant.getSecurityVersion() + 1);
            tenant.setUpdatedAt(clock.instant());
            tenants.save(tenant);
            audit.registrar("SEGURIDAD", "PLATFORM_TENANT_STATUS_CHANGED", "TENANT", tenantId.toString(),
                    actor, null, Map.of("previous", previous.name(), "current", status.name()));
            return tenant;
        });
    }

    public TenantMembership grantMembership(UUID tenantId, Long userId, Collection<String> roleCodes,
                                             Instant validUntil, Usuario actor) {
        platformAccess.requireProvisioningCapability(actor, "PLATFORM_MEMBERSHIP_GRANT");
        return inTenantTransaction(tenantId, () -> {
            Tenant tenant = tenants.findByIdForUpdate(tenantId)
                    .filter(value -> value.getStatus() == TenantStatus.ACTIVE)
                    .orElseThrow(() -> new AccessDeniedException("Active tenant required"));
            Usuario user = activeUser(userId);
            Instant now = clock.instant();
            if (validUntil != null && !validUntil.isAfter(now)) {
                throw new IllegalArgumentException("validUntil must be in the future");
            }
            Set<Rol> selectedRoles = activeRoles(roleCodes);

            var existing = memberships.findByTenantAndUserForUpdate(tenantId, userId);
            TenantMembership membership = existing.orElseGet(() -> newMembership(tenant, user, validUntil, now));
            membership.setStatus(TenantMembershipStatus.ACTIVE);
            membership.setValidFrom(now);
            membership.setValidUntil(validUntil);
            membership.setUpdatedAt(now);
            if (existing.isPresent()) {
                membership.setSecurityVersion(membership.getSecurityVersion() + 1);
            }
            memberships.save(membership);
            membershipRoles.deleteByMembershipId(membership.getId());
            membershipRoles.saveAll(selectedRoles.stream()
                    .map(role -> new TenantMembershipRole(membership, tenant, role))
                    .toList());

            audit.registrar("SEGURIDAD", "PLATFORM_MEMBERSHIP_GRANTED", "TENANT_MEMBERSHIP",
                    membership.getId().toString(), actor, null,
                    Map.of("targetUserId", userId, "roles", selectedRoles.stream().map(Rol::getCodigo).toList()));
            return membership;
        });
    }

    public TenantMembership changeMembershipStatus(UUID tenantId, UUID membershipId,
                                                    TenantMembershipStatus status, Usuario actor) {
        platformAccess.requireProvisioningCapability(actor, "PLATFORM_MEMBERSHIP_STATUS");
        return inTenantTransaction(tenantId, () -> {
            TenantMembership membership = memberships.findByTenantAndIdForUpdate(tenantId, membershipId)
                    .orElseThrow(() -> new IllegalArgumentException("Membership not found"));
            TenantMembershipStatus previous = membership.getStatus();
            if (previous == status) {
                return membership;
            }
            membership.setStatus(status);
            membership.setSecurityVersion(membership.getSecurityVersion() + 1);
            membership.setUpdatedAt(clock.instant());
            membership.setValidUntil(status == TenantMembershipStatus.REVOKED ? clock.instant() : null);
            memberships.save(membership);
            audit.registrar("SEGURIDAD", "PLATFORM_MEMBERSHIP_STATUS_CHANGED", "TENANT_MEMBERSHIP",
                    membershipId.toString(), actor, null,
                    Map.of("previous", previous.name(), "current", status.name()));
            return membership;
        });
    }

    private TenantMembership newMembership(Tenant tenant, Usuario user, Instant validUntil, Instant now) {
        TenantMembership membership = new TenantMembership();
        membership.setId(UUID.randomUUID());
        membership.setTenant(tenant);
        membership.setUsuario(user);
        membership.setStatus(TenantMembershipStatus.ACTIVE);
        membership.setSecurityVersion(0L);
        membership.setValidFrom(now);
        membership.setValidUntil(validUntil);
        membership.setCreatedAt(now);
        membership.setUpdatedAt(now);
        return membership;
    }

    private Usuario activeUser(Long userId) {
        return users.findById(userId).filter(Usuario::isEnabled)
                .orElseThrow(() -> new IllegalArgumentException("Active user not found"));
    }

    private Set<Rol> activeRoles(Collection<String> roleCodes) {
        if (roleCodes == null || roleCodes.isEmpty()) {
            throw new IllegalArgumentException("At least one role is required");
        }
        Set<Rol> result = new LinkedHashSet<>();
        for (String code : roleCodes) {
            Rol role = roles.findWithPermisosByCodigoIgnoreCase(code.trim())
                    .filter(Rol::estaActivo)
                    .orElseThrow(() -> new IllegalArgumentException("Active role not found: " + code));
            result.add(role);
        }
        return result;
    }

    private <T> T inTenantTransaction(UUID tenantId, Supplier<T> work) {
        try (TenantContext.Scope ignored = TenantContext.open(tenantId, null)) {
            return transactions.execute(status -> work.get());
        }
    }

    public record ProvisionedTenant(Tenant tenant, TenantMembership initialAdminMembership) {
    }
}
