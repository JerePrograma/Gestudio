package gestudio.platform.control;

import gestudio.infra.errores.TratadorDeErrores.OperacionNoPermitidaException;
import gestudio.infra.errores.TratadorDeErrores.RecursoNoEncontradoException;
import gestudio.platform.control.PlatformControlPlaneService.Activation;
import gestudio.platform.control.PlatformControlPlaneService.GrantedAdmin;
import gestudio.platform.security.PlatformPrincipal;
import gestudio.platform.security.PlatformStepUpService;
import org.springframework.transaction.support.TransactionTemplate;

import java.time.Clock;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static gestudio.platform.control.PlatformControlPlaneService.ACTIVE;
import static gestudio.platform.control.PlatformControlPlaneService.PLATFORM_ADMIN_GRANT;
import static gestudio.platform.control.PlatformControlPlaneService.PLATFORM_ADMIN_STATUS;
import static gestudio.platform.control.PlatformControlPlaneService.PLATFORM_ADMIN_TARGET;
import static gestudio.platform.control.PlatformControlPlaneService.PLATFORM_MFA_ENROLLMENT_PURPOSE;
import static gestudio.platform.control.PlatformControlPlaneService.PLATFORM_MFA_RESET;
import static gestudio.platform.control.PlatformControlPlaneService.REVOKED;

final class PlatformAdminMutationCoordinator {
    private final PlatformControlPlaneRepository repository;
    private final PlatformIdempotencyRepository idempotency;
    private final PlatformStepUpService stepUp;
    private final PlatformAuditService auditService;
    private final Clock clock;
    private final TransactionTemplate transactions;
    private final PlatformControlPlaneCommandSupport commands;
    private final PlatformMutationExecutor mutations;

    PlatformAdminMutationCoordinator(PlatformControlPlaneRepository repository,
                                     PlatformIdempotencyRepository idempotency,
                                     PlatformStepUpService stepUp,
                                     PlatformAuditService auditService,
                                     Clock clock,
                                     TransactionTemplate transactions,
                                     PlatformControlPlaneCommandSupport commands,
                                     PlatformMutationExecutor mutations) {
        this.repository = repository;
        this.idempotency = idempotency;
        this.stepUp = stepUp;
        this.auditService = auditService;
        this.clock = clock;
        this.transactions = transactions;
        this.commands = commands;
        this.mutations = mutations;
    }

    GrantedAdmin grantAdmin(long userId, PlatformPrincipal actor, String idempotencyKey,
                            String stepUpProof, UUID correlationId) {
        String key = commands.validateKey(idempotencyKey);
        String hash = PlatformRequestHash.sha256(
                PLATFORM_ADMIN_GRANT, Long.toString(userId));
        return mutations.auditedMutation(
                PLATFORM_ADMIN_GRANT, PLATFORM_ADMIN_TARGET,
                Long.toString(userId), null, actor, key, correlationId,
                () -> transactions.execute(status -> {
            PlatformIdempotencyRepository.Claim claim = idempotency.claim(
                    PLATFORM_ADMIN_GRANT, key, actor.userId(), hash);
            commands.verifyClaim(claim, actor, hash);
            if (claim.succeeded()) return new GrantedAdmin(requireAdmin(userId), null);
            stepUp.requireAndConsume(actor, stepUpProof, PLATFORM_ADMIN_GRANT,
                    PLATFORM_ADMIN_TARGET, Long.toString(userId), key);
            var identity = repository.identity(userId)
                    .filter(PlatformControlPlaneRepository.IdentityView::active)
                    .orElseThrow(() -> new IllegalArgumentException(
                            "Identidad activa no encontrada"));
            Instant now = clock.instant();
            repository.consumePendingActivation(userId, now);
            boolean mfaEnabled = repository.admin(userId)
                    .map(PlatformControlPlaneRepository.AdminView::mfaEnabled)
                    .orElse(false);
            repository.grantAdmin(identity.id(), actor.userId(), now, mfaEnabled);
            Activation activation = mfaEnabled ? null : commands.activation(
                    userId, PLATFORM_MFA_ENROLLMENT_PURPOSE, actor.userId(), now);
            idempotency.succeeded(PLATFORM_ADMIN_GRANT, key, PLATFORM_ADMIN_TARGET,
                    Long.toString(userId), 201, "{}");
            auditService.success(actor, PLATFORM_ADMIN_GRANT, PLATFORM_ADMIN_TARGET,
                    Long.toString(userId), null, correlationId, key, true, Map.of());
            return new GrantedAdmin(requireAdmin(userId), activation);
        }));
    }

    PlatformControlPlaneRepository.AdminView changeAdminStatus(
            long userId, String requestedStatus, long expectedVersion, String reason,
            PlatformPrincipal actor, String idempotencyKey, String stepUpProof,
            UUID correlationId) {
        String state = commands.requiredStatus(requestedStatus, List.of(ACTIVE, REVOKED));
        String validReason = commands.reason(reason);
        String key = commands.validateKey(idempotencyKey);
        String hash = PlatformRequestHash.sha256(PLATFORM_ADMIN_STATUS,
                Long.toString(userId), state, String.valueOf(expectedVersion), validReason);
        return mutations.auditedMutation(
                PLATFORM_ADMIN_STATUS, PLATFORM_ADMIN_TARGET,
                Long.toString(userId), null, actor, key, correlationId,
                () -> transactions.execute(status -> {
            PlatformIdempotencyRepository.Claim claim = idempotency.claim(
                    PLATFORM_ADMIN_STATUS, key, actor.userId(), hash);
            commands.verifyClaim(claim, actor, hash);
            if (claim.succeeded()) return requireAdmin(userId);
            stepUp.requireAndConsume(actor, stepUpProof, PLATFORM_ADMIN_STATUS,
                    PLATFORM_ADMIN_TARGET, Long.toString(userId), key);
            repository.lockPlatformAdministratorInvariant();
            var current = requireAdmin(userId);
            boolean active = state.equals(ACTIVE);
            validateAdminStatusChange(current, active);
            Instant now = clock.instant();
            if (!repository.changeAdminStatus(userId, active, expectedVersion, now)) {
                throw commands.concurrencyConflict();
            }
            revokeSessionsWhenInactive(userId, active, now);
            idempotency.succeeded(PLATFORM_ADMIN_STATUS, key, PLATFORM_ADMIN_TARGET,
                    Long.toString(userId), 200, "{}");
            auditService.success(actor, PLATFORM_ADMIN_STATUS, PLATFORM_ADMIN_TARGET,
                    Long.toString(userId), null, correlationId, key, true,
                    Map.of("status", state, "reason", validReason));
            return requireAdmin(userId);
        }));
    }

    Activation resetAdminMfa(long userId, PlatformPrincipal actor,
                             String idempotencyKey, String stepUpProof,
                             UUID correlationId) {
        String key = commands.validateKey(idempotencyKey);
        String hash = PlatformRequestHash.sha256(
                PLATFORM_MFA_RESET, Long.toString(userId));
        Activation result = mutations.auditedMutation(
                PLATFORM_MFA_RESET, PLATFORM_ADMIN_TARGET,
                Long.toString(userId), null, actor, key, correlationId,
                () -> transactions.execute(status -> {
            if (actor.userId() == userId) {
                throw new OperacionNoPermitidaException(
                        "El administrador no puede resetear su propio MFA");
            }
            PlatformIdempotencyRepository.Claim claim = idempotency.claim(
                    PLATFORM_MFA_RESET, key, actor.userId(), hash);
            commands.verifyClaim(claim, actor, hash);
            if (claim.succeeded()) return null;
            stepUp.requireAndConsume(actor, stepUpProof, PLATFORM_MFA_RESET,
                    PLATFORM_ADMIN_TARGET, Long.toString(userId), key);
            repository.lockPlatformAdministratorInvariant();
            var admin = requireAdmin(userId);
            validateMfaReset(admin);
            Instant now = clock.instant();
            repository.consumePendingActivation(userId, now);
            repository.resetMfa(userId, now);
            Activation activation = commands.activation(
                    userId, PLATFORM_MFA_RESET, actor.userId(), now);
            idempotency.succeeded(PLATFORM_MFA_RESET, key, PLATFORM_ADMIN_TARGET,
                    Long.toString(userId), 200, "{}");
            auditService.success(actor, PLATFORM_MFA_RESET, PLATFORM_ADMIN_TARGET,
                    Long.toString(userId), null, correlationId, key, true, Map.of());
            return activation;
        }));
        if (result == null) {
            throw new OperacionNoPermitidaException(
                    "El replay de reset MFA no vuelve a exponer el token de activación");
        }
        return result;
    }

    private PlatformControlPlaneRepository.AdminView requireAdmin(long userId) {
        return repository.admin(userId).orElseThrow(
                () -> new RecursoNoEncontradoException(
                        "Administrador de plataforma no encontrado"));
    }

    private void validateAdminStatusChange(
            PlatformControlPlaneRepository.AdminView current, boolean active) {
        if (active && !current.mfaEnabled()) {
            throw new OperacionNoPermitidaException(
                    "No se puede reactivar capacidad de plataforma sin MFA verificado");
        }
        if (!active && repository.activeAdminCount() <= 1) {
            throw new OperacionNoPermitidaException(
                    "No se puede revocar al último PLATFORM_SUPERADMIN activo");
        }
    }

    private void validateMfaReset(PlatformControlPlaneRepository.AdminView admin) {
        if (ACTIVE.equals(admin.status()) && repository.activeAdminCount() <= 1) {
            throw new OperacionNoPermitidaException(
                    "No se puede resetear MFA del último PLATFORM_SUPERADMIN activo");
        }
    }

    private void revokeSessionsWhenInactive(long userId, boolean active, Instant now) {
        if (!active) {
            repository.revokeAdminSessions(userId, now, "PLATFORM_ADMIN_REVOKED");
        }
    }
}
