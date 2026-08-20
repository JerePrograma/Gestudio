package gestudio.platform.control;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import gestudio.infra.errores.TratadorDeErrores.RecursoNoEncontradoException;
import gestudio.platform.PlatformMetrics;
import gestudio.platform.control.PlatformControlPlaneService.Activation;
import gestudio.platform.control.PlatformControlPlaneService.CreateTenant;
import gestudio.platform.control.PlatformControlPlaneService.CreatedIdentity;
import gestudio.platform.control.PlatformControlPlaneService.IdentityRequest;
import gestudio.platform.control.PlatformControlPlaneService.MutationOutcome;
import gestudio.platform.control.PlatformControlPlaneService.ProvisionedTenant;
import gestudio.platform.security.PlatformPrincipal;
import gestudio.platform.security.PlatformStepUpService;
import org.springframework.transaction.support.TransactionTemplate;

import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static gestudio.platform.control.PlatformControlPlaneService.ACTIVE;
import static gestudio.platform.control.PlatformControlPlaneService.ARCHIVED;
import static gestudio.platform.control.PlatformControlPlaneService.SUSPENDED;
import static gestudio.platform.control.PlatformControlPlaneService.TENANT_CREATE;
import static gestudio.platform.control.PlatformControlPlaneService.TENANT_STATUS;
import static gestudio.platform.control.PlatformControlPlaneService.TENANT_TARGET;
import static gestudio.platform.control.PlatformControlPlaneService.TENANT_UPDATE;

final class TenantMutationCoordinator {
    private final PlatformControlPlaneRepository repository;
    private final PlatformIdempotencyRepository idempotency;
    private final PlatformStepUpService stepUp;
    private final PlatformAuditService auditService;
    private final PlatformMetrics metrics;
    private final ObjectMapper objectMapper;
    private final Clock clock;
    private final TransactionTemplate transactions;
    private final PlatformControlPlaneCommandSupport commands;
    private final PlatformMutationExecutor mutations;

    TenantMutationCoordinator(PlatformControlPlaneRepository repository,
                              PlatformIdempotencyRepository idempotency,
                              PlatformStepUpService stepUp,
                              PlatformAuditService auditService,
                              PlatformMetrics metrics,
                              ObjectMapper objectMapper,
                              Clock clock,
                              TransactionTemplate transactions,
                              PlatformControlPlaneCommandSupport commands,
                              PlatformMutationExecutor mutations) {
        this.repository = repository;
        this.idempotency = idempotency;
        this.stepUp = stepUp;
        this.auditService = auditService;
        this.metrics = metrics;
        this.objectMapper = objectMapper;
        this.clock = clock;
        this.transactions = transactions;
        this.commands = commands;
        this.mutations = mutations;
    }

    ProvisionedTenant createTenant(CreateTenant command, PlatformPrincipal actor,
                                    String idempotencyKey, String stepUpProof,
                                    UUID correlationId) {
        String code = commands.normalizedCode(command.code());
        String name = commands.validatedName(command.name());
        IdentityRequest identity = commands.validateIdentity(command.initialAdmin());
        String key = commands.validateKey(idempotencyKey);
        String hash = PlatformRequestHash.sha256(TENANT_CREATE, code, name, identity.mode(),
                identity.userId() == null ? null : identity.userId().toString(),
                identity.username());
        UUID tenantId = UUID.nameUUIDFromBytes(
                ("gestudio-tenant:" + key).getBytes(StandardCharsets.UTF_8));
        ProvisionedTenant provisioned = mutations.auditedMutation(
                TENANT_CREATE, TENANT_TARGET, tenantId.toString(), tenantId,
                actor, key, correlationId,
                () -> mutations.inTenant(tenantId, () -> transactions.execute(status -> {
            PlatformIdempotencyRepository.Claim claim = idempotency.claim(
                    TENANT_CREATE, key, actor.userId(), hash);
            commands.verifyClaim(claim, actor, hash);
            if (claim.succeeded()) return replayTenant(claim);
            stepUp.requireAndConsume(actor, stepUpProof, TENANT_CREATE,
                    TENANT_TARGET, code, key);

            Instant now = clock.instant();
            repository.insertTenant(tenantId, code, name, now);
            repository.materializeBaseRoles(tenantId);
            CreatedIdentity created = commands.resolveIdentity(identity, actor.userId(), now);
            UUID membershipId = repository.insertMembership(
                    tenantId, created.userId(), null, now);
            repository.assignRoles(
                    tenantId, membershipId, List.of("ADMINISTRADOR"), actor.userId());
            String result = commands.json(Map.of(
                    "tenantId", tenantId.toString(),
                    "membershipId", membershipId.toString(),
                    "userId", created.userId()));
            idempotency.succeeded(
                    TENANT_CREATE, key, TENANT_TARGET, tenantId.toString(), 201, result);
            auditService.success(actor, TENANT_CREATE, TENANT_TARGET,
                    tenantId.toString(), tenantId, correlationId, key, true,
                    Map.of("tenantCode", code, "identityMode", identity.mode()));
            return provisioned(tenantId, membershipId, created.activation(), false);
        })));
        if (!provisioned.replayed()) {
            metrics.tenantEvent(PlatformMetrics.TenantEvent.CREATED);
            metrics.membershipEvent(PlatformMetrics.MembershipEvent.CREATED);
        }
        return provisioned;
    }

    PlatformControlPlaneRepository.TenantView updateTenant(
            UUID tenantId, String name, long expectedVersion, PlatformPrincipal actor,
            String idempotencyKey, String stepUpProof, UUID correlationId) {
        String validName = commands.validatedName(name);
        return mutateTenant(TENANT_UPDATE, tenantId, expectedVersion, validName,
                actor, idempotencyKey, stepUpProof, correlationId,
                () -> repository.updateTenantName(
                        tenantId, validName, expectedVersion, clock.instant())).value();
    }

    PlatformControlPlaneRepository.TenantView changeTenantStatus(
            UUID tenantId, String requestedStatus, long expectedVersion, String reason,
            PlatformPrincipal actor, String idempotencyKey, String stepUpProof,
            UUID correlationId) {
        String state = commands.requiredStatus(
                requestedStatus, List.of(ACTIVE, SUSPENDED, ARCHIVED));
        String validReason = commands.reason(reason);
        MutationOutcome<PlatformControlPlaneRepository.TenantView> outcome = mutateTenant(
                TENANT_STATUS, tenantId, expectedVersion, state + "\u0000" + validReason,
                actor, idempotencyKey, stepUpProof, correlationId,
                () -> repository.updateTenantStatus(
                        tenantId, state, expectedVersion, clock.instant()));
        if (!outcome.replayed()) metrics.tenantEvent(commands.tenantEvent(state));
        return outcome.value();
    }

    private MutationOutcome<PlatformControlPlaneRepository.TenantView> mutateTenant(
            String operation, UUID tenantId, long expectedVersion, String payload,
            PlatformPrincipal actor, String idempotencyKey, String stepUpProof,
            UUID correlationId, BooleanOperation mutation) {
        String key = commands.validateKey(idempotencyKey);
        String hash = PlatformRequestHash.sha256(
                operation, tenantId.toString(), String.valueOf(expectedVersion), payload);
        return mutations.auditedMutation(
                operation, TENANT_TARGET, tenantId.toString(), tenantId,
                actor, key, correlationId,
                () -> mutations.inTenant(tenantId, () -> transactions.execute(status -> {
            mutations.requireTenant(tenantId);
            PlatformIdempotencyRepository.Claim claim = idempotency.claim(
                    operation, key, actor.userId(), hash);
            commands.verifyClaim(claim, actor, hash);
            if (claim.succeeded()) {
                return new MutationOutcome<>(mutations.requireTenant(tenantId), true);
            }
            stepUp.requireAndConsume(actor, stepUpProof, operation,
                    TENANT_TARGET, tenantId.toString(), key);
            if (!mutation.run()) throw commands.concurrencyConflict();
            idempotency.succeeded(operation, key, TENANT_TARGET,
                    tenantId.toString(), 200, "{}");
            auditService.success(actor, operation, TENANT_TARGET, tenantId.toString(),
                    tenantId, correlationId, key, true, Map.of());
            return new MutationOutcome<>(mutations.requireTenant(tenantId), false);
        })));
    }

    private ProvisionedTenant replayTenant(PlatformIdempotencyRepository.Claim claim) {
        try {
            var node = objectMapper.readTree(claim.resultReferenceJson());
            UUID tenantId = UUID.fromString(node.path("tenantId").asText());
            UUID membershipId = UUID.fromString(node.path("membershipId").asText());
            return provisioned(tenantId, membershipId, null, true);
        } catch (JsonProcessingException | IllegalArgumentException failure) {
            throw new IllegalStateException("Resultado idempotente inválido", failure);
        }
    }

    private ProvisionedTenant provisioned(UUID tenantId, UUID membershipId,
                                          Activation activation, boolean replayed) {
        return new ProvisionedTenant(mutations.requireTenant(tenantId),
                requireMembership(tenantId, membershipId), activation, replayed);
    }

    private PlatformControlPlaneRepository.MembershipView requireMembership(
            UUID tenantId, UUID membershipId) {
        return repository.membership(tenantId, membershipId).orElseThrow(
                () -> new RecursoNoEncontradoException("Membership no encontrada"));
    }

    @FunctionalInterface
    private interface BooleanOperation {
        boolean run();
    }
}
