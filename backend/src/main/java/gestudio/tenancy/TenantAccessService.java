package gestudio.tenancy;

import gestudio.entidades.Usuario;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.stereotype.Service;

import java.time.Clock;
import java.time.Instant;
import java.util.List;
import java.util.Objects;
import java.util.Optional;
import java.util.UUID;

@Service
public class TenantAccessService {
    private final TenantMembershipRepository memberships;
    private final Clock clock;

    public TenantAccessService(TenantMembershipRepository memberships, Clock clock) {
        this.memberships = memberships;
        this.clock = clock;
    }

    public List<TenantSelection> activeSelections(Long userId) {
        Instant now = clock.instant();
        return memberships.findActiveSelections(userId, now).stream()
                .filter(selection -> findActiveAccess(userId, selection.id(), now).isPresent())
                .toList();
    }

    public Optional<TenantAccess> findActiveAccess(Long userId, UUID tenantId) {
        return findActiveAccess(userId, tenantId, clock.instant());
    }

    private Optional<TenantAccess> findActiveAccess(Long userId, UUID tenantId, Instant now) {
        try (TenantContext.Scope ignored = TenantContext.open(tenantId, null)) {
            return memberships.findActiveAccess(userId, tenantId, now)
                    .map(TenantAccess::new)
                    .filter(access -> !access.roleCodes().isEmpty());
        }
    }

    public Optional<TenantAccess> revalidate(Long userId, UUID membershipId, UUID tenantId,
                                             long tenantSecurityVersion, long membershipSecurityVersion) {
        try (TenantContext.Scope ignored = TenantContext.open(tenantId, membershipId)) {
            return memberships.findActiveAccess(userId, membershipId, tenantId, clock.instant())
                    .map(TenantAccess::new)
                    .filter(access -> !access.roleCodes().isEmpty())
                    .filter(access -> access.tenantSecurityVersion() == tenantSecurityVersion)
                    .filter(access -> access.membershipSecurityVersion() == membershipSecurityVersion);
        }
    }

    public TenantAccess currentAccess(Usuario actor) {
        if (actor == null || actor.getId() == null) {
            throw new AccessDeniedException("Actor requerido");
        }
        UUID tenantId = TenantContext.requireTenantId();
        UUID membershipId = TenantContext.currentMembershipId()
                .orElseThrow(() -> new AccessDeniedException("Membership requerida"));
        return memberships.findActiveAccess(actor.getId(), membershipId, tenantId, clock.instant())
                .map(TenantAccess::new)
                .filter(access -> !access.roleCodes().isEmpty())
                .orElseThrow(() -> new AccessDeniedException("Membership inactiva o revocada"));
    }

    public TenantAccess requireSelected(Long userId, UUID requestedTenantId) {
        List<TenantSelection> available = activeSelections(userId);
        UUID selected = requestedTenantId == null && available.size() == 1
                ? available.getFirst().id()
                : requestedTenantId;
        if (selected == null || available.stream().noneMatch(value -> Objects.equals(value.id(), selected))) {
            throw new AccessDeniedException("Tenant no autorizado");
        }
        return findActiveAccess(userId, selected)
                .orElseThrow(() -> new AccessDeniedException("Tenant no autorizado"));
    }
}
