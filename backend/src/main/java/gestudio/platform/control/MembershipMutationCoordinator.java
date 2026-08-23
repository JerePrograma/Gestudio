package gestudio.platform.control;

import gestudio.infra.errores.TratadorDeErrores.OperacionNoPermitidaException;
import gestudio.infra.errores.TratadorDeErrores.RecursoNoEncontradoException;
import gestudio.platform.PlatformMetrics;
import gestudio.platform.control.PlatformControlPlaneService.CreateMembership;
import gestudio.platform.control.PlatformControlPlaneService.CreatedIdentity;
import gestudio.platform.control.PlatformControlPlaneService.IdentityRequest;
import gestudio.platform.control.PlatformControlPlaneService.MutationOutcome;
import gestudio.platform.control.PlatformControlPlaneService.ProvisionedMembership;
import gestudio.platform.security.PlatformPrincipal;
import gestudio.platform.security.PlatformStepUpService;
import org.springframework.transaction.support.TransactionTemplate;

import java.time.Clock;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static gestudio.platform.control.PlatformControlPlaneService.ACTIVE;
import static gestudio.platform.control.PlatformControlPlaneService.MEMBERSHIP_CREATE;
import static gestudio.platform.control.PlatformControlPlaneService.MEMBERSHIP_ROLES;
import static gestudio.platform.control.PlatformControlPlaneService.MEMBERSHIP_STATUS;
import static gestudio.platform.control.PlatformControlPlaneService.REVOKED;
import static gestudio.platform.control.PlatformControlPlaneService.SUSPENDED;
import static gestudio.platform.control.PlatformControlPlaneService.TENANT_MEMBERSHIP_TARGET;
import static gestudio.platform.control.PlatformControlPlaneService.TENANT_TARGET;

final class MembershipMutationCoordinator {
    private final PlatformControlPlaneRepository repository;
    private final PlatformIdempotencyRepository idempotency;
    private final PlatformStepUpService stepUp;
    private final PlatformAuditService auditService;
    private final PlatformMetrics metrics;
    private final Clock clock;
    private final TransactionTemplate transactions;
    private final PlatformControlPlaneCommandSupport commands;
    private final PlatformMutationExecutor mutations;

    MembershipMutationCoordinator(PlatformControlPlaneRepository repository,
                                  PlatformIdempotencyRepository idempotency,
                                  PlatformStepUpService stepUp,
                                  PlatformAuditService auditService,
                                  PlatformMetrics metrics,
                                  Clock clock,
                                  TransactionTemplate transactions,
                                  PlatformControlPlaneCommandSupport commands,
                                  PlatformMutationExecutor mutations) {
        this.repository = repository;
        this.idempotency = idempotency;
        this.stepUp = stepUp;
        this.auditService = auditService;
        this.metrics = metrics;
        this.clock = clock;
        this.transactions = transactions;
        this.commands = commands;
        this.mutations = mutations;
    }

    ProvisionedMembership createMembership(
            UUID tenantId, CreateMembership command, PlatformPrincipal actor,
            String idempotencyKey, String stepUpProof, UUID correlationId) {
        IdentityRequest identity = commands.validateIdentity(command.identity());
        List<String> roles = commands.normalizedRoles(command.roles());
        Instant validUntil = commands.validateValidUntil(command.validUntil());
        String key = commands.validateKey(idempotencyKey);
        String hash = PlatformRequestHash.sha256(MEMBERSHIP_CREATE, tenantId.toString(),
                identity.mode(),
                identity.userId() == null ? null : identity.userId().toString(),
                identity.username(), String.join(",", roles), String.valueOf(validUntil));
        ProvisionedMembership provisioned = mutations.auditedMutation(
                MEMBERSHIP_CREATE, TENANT_TARGET, tenantId.toString(), tenantId,
                actor, key, correlationId,
                () -> mutations.inTenant(tenantId, () -> transactions.execute(status -> {
            mutations.requireTenant(tenantId);
            PlatformIdempotencyRepository.Claim claim = idempotency.claim(
                    MEMBERSHIP_CREATE, key, actor.userId(), hash);
            commands.verifyClaim(claim, actor, hash);
            if (claim.succeeded()) {
                UUID membershipId = UUID.fromString(claim.resourceId());
                return new ProvisionedMembership(
                        requireMembership(tenantId, membershipId), null, true);
            }
            stepUp.requireAndConsume(actor, stepUpProof, MEMBERSHIP_CREATE,
                    TENANT_TARGET, tenantId.toString(), key);
            Instant now = clock.instant();
            CreatedIdentity created = commands.resolveIdentity(identity, actor.userId(), now);
            if (repository.membershipByUser(tenantId, created.userId()).isPresent()) {
                throw new OperacionNoPermitidaException(
                        "La identidad ya posee membership en este tenant");
            }
            UUID membershipId = repository.insertMembership(
                    tenantId, created.userId(), validUntil, now);
            repository.assignRoles(tenantId, membershipId, roles, actor.userId());
            idempotency.succeeded(MEMBERSHIP_CREATE, key, TENANT_MEMBERSHIP_TARGET,
                    membershipId.toString(), 201,
                    commands.json(Map.of("tenantId", tenantId.toString(),
                            "membershipId", membershipId.toString(),
                            "userId", created.userId())));
            auditService.success(actor, MEMBERSHIP_CREATE, TENANT_MEMBERSHIP_TARGET,
                    membershipId.toString(), tenantId, correlationId, key, true,
                    Map.of("roles", roles, "identityMode", identity.mode()));
            return new ProvisionedMembership(
                    requireMembership(tenantId, membershipId), created.activation(), false);
        })));
        if (!provisioned.replayed()) {
            metrics.membershipEvent(PlatformMetrics.MembershipEvent.CREATED);
        }
        return provisioned;
    }

    PlatformControlPlaneRepository.MembershipView updateMembershipRoles(
            UUID tenantId, UUID membershipId, List<String> requestedRoles,
            long expectedVersion, PlatformPrincipal actor, String idempotencyKey,
            String stepUpProof, UUID correlationId) {
        List<String> roles = commands.normalizedRoles(requestedRoles);
        String key = commands.validateKey(idempotencyKey);
        String hash = PlatformRequestHash.sha256(MEMBERSHIP_ROLES, tenantId.toString(),
                membershipId.toString(), String.join(",", roles),
                String.valueOf(expectedVersion));
        MutationOutcome<PlatformControlPlaneRepository.MembershipView> outcome =
                mutations.auditedMutation(MEMBERSHIP_ROLES, TENANT_MEMBERSHIP_TARGET,
                        membershipId.toString(), tenantId, actor, key, correlationId,
                        () -> mutations.inTenant(
                                tenantId, () -> transactions.execute(status -> {
            PlatformIdempotencyRepository.Claim claim = idempotency.claim(
                    MEMBERSHIP_ROLES, key, actor.userId(), hash);
            commands.verifyClaim(claim, actor, hash);
            if (claim.succeeded()) {
                return new MutationOutcome<>(requireMembership(tenantId, membershipId), true);
            }
            requireMembership(tenantId, membershipId);
            stepUp.requireAndConsume(actor, stepUpProof, MEMBERSHIP_ROLES,
                    TENANT_MEMBERSHIP_TARGET, membershipId.toString(), key);
            repository.lockTenantAdministratorInvariant(tenantId);
            var current = requireMembership(tenantId, membershipId);
            protectLastTenantAdmin(tenantId, current,
                    current.status().equals(ACTIVE) && !roles.contains("ADMINISTRADOR"));
            if (!repository.bumpMembershipVersion(
                    tenantId, membershipId, expectedVersion, clock.instant())) {
                throw commands.concurrencyConflict();
            }
            repository.replaceMembershipRoles(
                    tenantId, membershipId, roles, actor.userId());
            idempotency.succeeded(MEMBERSHIP_ROLES, key, TENANT_MEMBERSHIP_TARGET,
                    membershipId.toString(), 200, "{}");
            auditService.success(actor, MEMBERSHIP_ROLES, TENANT_MEMBERSHIP_TARGET,
                    membershipId.toString(), tenantId, correlationId, key, true,
                    Map.of("roles", roles));
            return new MutationOutcome<>(requireMembership(tenantId, membershipId), false);
        })));
        if (!outcome.replayed()) {
            metrics.membershipEvent(PlatformMetrics.MembershipEvent.ROLES_CHANGED);
        }
        return outcome.value();
    }

    PlatformControlPlaneRepository.MembershipView changeMembershipStatus(
            UUID tenantId, UUID membershipId, String requestedStatus,
            long expectedVersion, String reason, PlatformPrincipal actor,
            String idempotencyKey, String stepUpProof, UUID correlationId) {
        String state = commands.requiredStatus(
                requestedStatus, List.of(ACTIVE, SUSPENDED, REVOKED));
        String validReason = commands.reason(reason);
        String key = commands.validateKey(idempotencyKey);
        String hash = PlatformRequestHash.sha256(MEMBERSHIP_STATUS, tenantId.toString(),
                membershipId.toString(), state, String.valueOf(expectedVersion), validReason);
        MutationOutcome<PlatformControlPlaneRepository.MembershipView> outcome =
                mutations.auditedMutation(MEMBERSHIP_STATUS, TENANT_MEMBERSHIP_TARGET,
                        membershipId.toString(), tenantId, actor, key, correlationId,
                        () -> mutations.inTenant(
                                tenantId, () -> transactions.execute(status -> {
            PlatformIdempotencyRepository.Claim claim = idempotency.claim(
                    MEMBERSHIP_STATUS, key, actor.userId(), hash);
            commands.verifyClaim(claim, actor, hash);
            if (claim.succeeded()) {
                return new MutationOutcome<>(requireMembership(tenantId, membershipId), true);
            }
            stepUp.requireAndConsume(actor, stepUpProof, MEMBERSHIP_STATUS,
                    TENANT_MEMBERSHIP_TARGET, membershipId.toString(), key);
            repository.lockTenantAdministratorInvariant(tenantId);
            var current = requireMembership(tenantId, membershipId);
            protectLastTenantAdmin(tenantId, current,
                    current.status().equals(ACTIVE) && !state.equals(ACTIVE));
            Instant now = clock.instant();
            Instant validUntil = state.equals(REVOKED) ? now : current.validUntil();
            if (!repository.updateMembershipStatus(tenantId, membershipId, state,
                    expectedVersion, validUntil, now)) {
                throw commands.concurrencyConflict();
            }
            idempotency.succeeded(MEMBERSHIP_STATUS, key, TENANT_MEMBERSHIP_TARGET,
                    membershipId.toString(), 200, "{}");
            auditService.success(actor, MEMBERSHIP_STATUS, TENANT_MEMBERSHIP_TARGET,
                    membershipId.toString(), tenantId, correlationId, key, true,
                    Map.of("status", state, "reason", validReason));
            return new MutationOutcome<>(requireMembership(tenantId, membershipId), false);
        })));
        if (!outcome.replayed()) metrics.membershipEvent(commands.membershipEvent(state));
        return outcome.value();
    }

    private PlatformControlPlaneRepository.MembershipView requireMembership(
            UUID tenantId, UUID membershipId) {
        return repository.membership(tenantId, membershipId).orElseThrow(
                () -> new RecursoNoEncontradoException("Membership no encontrada"));
    }

    private void protectLastTenantAdmin(
            UUID tenantId, PlatformControlPlaneRepository.MembershipView current,
            boolean removingAdmin) {
        if (removingAdmin && current.roles().contains("ADMINISTRADOR")
                && repository.activeAdministrators(tenantId, current.id()) == 0) {
            throw new OperacionNoPermitidaException(
                    "No se puede revocar al último ADMINISTRADOR activo del tenant");
        }
    }
}
