package gestudio.platform.control;

import com.fasterxml.jackson.databind.ObjectMapper;
import gestudio.platform.PlatformMetrics;
import gestudio.platform.security.PlatformPrincipal;
import gestudio.platform.security.PlatformStepUpService;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

import java.time.Clock;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

@Service
public class PlatformControlPlaneService {
    public static final String TENANT_CREATE = "TENANT_CREATE";
    public static final String TENANT_UPDATE = "TENANT_UPDATE";
    public static final String TENANT_STATUS = "TENANT_STATUS";
    public static final String MEMBERSHIP_CREATE = "MEMBERSHIP_CREATE";
    public static final String MEMBERSHIP_ROLES = "MEMBERSHIP_ROLES";
    public static final String MEMBERSHIP_STATUS = "MEMBERSHIP_STATUS";
    public static final String PLATFORM_ADMIN_GRANT = "PLATFORM_ADMIN_GRANT";
    public static final String PLATFORM_ADMIN_STATUS = "PLATFORM_ADMIN_STATUS";
    public static final String PLATFORM_MFA_RESET = "PLATFORM_MFA_RESET";

    static final String ACTIVE = "ACTIVE";
    static final String SUSPENDED = "SUSPENDED";
    static final String ARCHIVED = "ARCHIVED";
    static final String REVOKED = "REVOKED";
    static final String TENANT_TARGET = "TENANT";
    static final String TENANT_MEMBERSHIP_TARGET = "TENANT_MEMBERSHIP";
    static final String PLATFORM_ADMIN_TARGET = "PLATFORM_ADMIN";
    static final String PLATFORM_MFA_ENROLLMENT_PURPOSE = "PLATFORM_MFA_ENROLLMENT";

    private final PlatformControlPlaneQueries queries;
    private final TenantMutationCoordinator tenantMutations;
    private final MembershipMutationCoordinator membershipMutations;
    private final PlatformAdminMutationCoordinator adminMutations;

    public PlatformControlPlaneService(PlatformControlPlaneRepository repository,
                                       PlatformIdempotencyRepository idempotency,
                                       PlatformStepUpService stepUp, PlatformAuditService audit,
                                       PlatformMetrics metrics,
                                       PasswordEncoder passwordEncoder, ObjectMapper objectMapper,
                                       Clock clock,
                                       @Qualifier("platformTransactionManager")
                                       PlatformTransactionManager manager) {
        PlatformControlPlaneCommandSupport commands = new PlatformControlPlaneCommandSupport(
                repository, passwordEncoder, objectMapper, clock);
        PlatformMutationExecutor mutations = new PlatformMutationExecutor(
                repository, audit, metrics);
        TransactionTemplate transactions = new TransactionTemplate(manager);
        this.queries = new PlatformControlPlaneQueries(repository, commands);
        this.tenantMutations = new TenantMutationCoordinator(repository, idempotency,
                stepUp, audit, metrics, objectMapper, clock, transactions, commands, mutations);
        this.membershipMutations = new MembershipMutationCoordinator(repository, idempotency,
                stepUp, audit, metrics, clock, transactions, commands, mutations);
        this.adminMutations = new PlatformAdminMutationCoordinator(repository, idempotency,
                stepUp, audit, clock, transactions, commands, mutations);
    }

    public PlatformControlPlaneRepository.PageData<PlatformControlPlaneRepository.TenantView> tenants(
            String query, String status, int page, int size) {
        return queries.tenants(query, status, page, size);
    }

    public PlatformControlPlaneRepository.TenantView tenant(UUID tenantId) {
        return queries.tenant(tenantId);
    }

    public ProvisionedTenant createTenant(CreateTenant command, PlatformPrincipal actor,
                                           String idempotencyKey, String stepUpProof,
                                           UUID correlationId) {
        return tenantMutations.createTenant(command, actor, idempotencyKey,
                stepUpProof, correlationId);
    }

    public PlatformControlPlaneRepository.TenantView updateTenant(
            UUID tenantId, String name, long expectedVersion, PlatformPrincipal actor,
            String idempotencyKey, String stepUpProof, UUID correlationId) {
        return tenantMutations.updateTenant(tenantId, name, expectedVersion, actor,
                idempotencyKey, stepUpProof, correlationId);
    }

    public PlatformControlPlaneRepository.TenantView changeTenantStatus(
            UUID tenantId, String requestedStatus, long expectedVersion, String reason,
            PlatformPrincipal actor, String idempotencyKey, String stepUpProof,
            UUID correlationId) {
        return tenantMutations.changeTenantStatus(tenantId, requestedStatus, expectedVersion,
                reason, actor, idempotencyKey, stepUpProof, correlationId);
    }

    public PlatformControlPlaneRepository.PageData<PlatformControlPlaneRepository.MembershipView> memberships(
            UUID tenantId, String query, String status, int page, int size) {
        return queries.memberships(tenantId, query, status, page, size);
    }

    public ProvisionedMembership createMembership(
            UUID tenantId, CreateMembership command, PlatformPrincipal actor,
            String idempotencyKey, String stepUpProof, UUID correlationId) {
        return membershipMutations.createMembership(tenantId, command, actor,
                idempotencyKey, stepUpProof, correlationId);
    }

    public PlatformControlPlaneRepository.MembershipView updateMembershipRoles(
            UUID tenantId, UUID membershipId, List<String> requestedRoles, long expectedVersion,
            PlatformPrincipal actor, String idempotencyKey, String stepUpProof, UUID correlationId) {
        return membershipMutations.updateMembershipRoles(tenantId, membershipId,
                requestedRoles, expectedVersion, actor, idempotencyKey, stepUpProof,
                correlationId);
    }

    public PlatformControlPlaneRepository.MembershipView changeMembershipStatus(
            UUID tenantId, UUID membershipId, String requestedStatus, long expectedVersion,
            String reason, PlatformPrincipal actor, String idempotencyKey,
            String stepUpProof, UUID correlationId) {
        return membershipMutations.changeMembershipStatus(tenantId, membershipId,
                requestedStatus, expectedVersion, reason, actor, idempotencyKey,
                stepUpProof, correlationId);
    }

    public List<PlatformControlPlaneRepository.RoleView> roles(UUID tenantId) {
        return queries.roles(tenantId);
    }

    public List<PlatformControlPlaneRepository.IdentityView> identities(String query) {
        return queries.identities(query);
    }

    public PlatformControlPlaneRepository.PageData<PlatformControlPlaneRepository.AdminView> admins(
            String query, String status, int page, int size) {
        return queries.admins(query, status, page, size);
    }

    public GrantedAdmin grantAdmin(
            long userId, PlatformPrincipal actor, String idempotencyKey,
            String stepUpProof, UUID correlationId) {
        return adminMutations.grantAdmin(userId, actor, idempotencyKey,
                stepUpProof, correlationId);
    }

    public PlatformControlPlaneRepository.AdminView changeAdminStatus(
            long userId, String requestedStatus, long expectedVersion, String reason,
            PlatformPrincipal actor, String idempotencyKey, String stepUpProof,
            UUID correlationId) {
        return adminMutations.changeAdminStatus(userId, requestedStatus, expectedVersion,
                reason, actor, idempotencyKey, stepUpProof, correlationId);
    }

    public Activation resetAdminMfa(long userId, PlatformPrincipal actor, String idempotencyKey,
                                    String stepUpProof, UUID correlationId) {
        return adminMutations.resetAdminMfa(userId, actor, idempotencyKey,
                stepUpProof, correlationId);
    }

    public PlatformControlPlaneRepository.PageData<PlatformControlPlaneRepository.AuditView> audit(
            PlatformControlPlaneRepository.AuditFilter filter, int page, int size) {
        return queries.audit(filter, page, size);
    }

    public record IdentityRequest(String mode, Long userId, String username) {
    }

    public record CreateTenant(String code, String name, IdentityRequest initialAdmin) {
    }

    public record CreateMembership(IdentityRequest identity, List<String> roles, Instant validUntil) {
    }

    public record Activation(String token, Instant expiresAt) {
    }

    public record ProvisionedTenant(PlatformControlPlaneRepository.TenantView tenant,
                                    PlatformControlPlaneRepository.MembershipView initialAdmin,
                                    Activation activation, boolean replayed) {
    }

    public record ProvisionedMembership(PlatformControlPlaneRepository.MembershipView membership,
                                        Activation activation, boolean replayed) {
    }

    public record GrantedAdmin(PlatformControlPlaneRepository.AdminView admin,
                               Activation activation) {
    }

    record CreatedIdentity(long userId, Activation activation) {
    }

    record MutationOutcome<T>(T value, boolean replayed) {
    }
}
