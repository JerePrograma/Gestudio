package gestudio.platform.control;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import gestudio.platform.security.PlatformPrincipal;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;

import java.sql.Timestamp;
import java.time.Clock;
import java.util.Map;
import java.util.UUID;

@Service
public class PlatformAuditService {
    private final JdbcTemplate jdbc;
    private final ObjectMapper objectMapper;
    private final Clock clock;
    private final TransactionTemplate isolatedTransactions;

    public PlatformAuditService(@Qualifier("platformJdbcTemplate") JdbcTemplate jdbc,
                                ObjectMapper objectMapper, Clock clock,
                                @Qualifier("platformTransactionManager")
                                PlatformTransactionManager manager) {
        this.jdbc = jdbc;
        this.objectMapper = objectMapper;
        this.clock = clock;
        this.isolatedTransactions = new TransactionTemplate(manager);
        this.isolatedTransactions.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
    }

    public void success(PlatformPrincipal actor, String action, String targetType, String targetId,
                        UUID tenantId, UUID correlationId, String idempotencyKey,
                        boolean stepUp, Map<String, ?> metadata) {
        record(actor, "PLATFORM", action, targetType, targetId, tenantId, correlationId,
                idempotencyKey, "SUCCESS", stepUp, metadata);
    }

    public void denied(PlatformPrincipal actor, String action, String targetType, String targetId,
                       UUID tenantId, UUID correlationId, String idempotencyKey,
                       Map<String, ?> metadata) {
        isolated("DENIED", actor, action, targetType, targetId, tenantId,
                correlationId, idempotencyKey, metadata);
    }

    public void failed(PlatformPrincipal actor, String action, String targetType, String targetId,
                       UUID tenantId, UUID correlationId, String idempotencyKey,
                       Map<String, ?> metadata) {
        isolated("FAILED", actor, action, targetType, targetId, tenantId,
                correlationId, idempotencyKey, metadata);
    }

    public void bootstrap(long userId, String username, UUID correlationId) {
        jdbc.update("""
                INSERT INTO platform_audit_events(
                    actor_usuario_id, actor_username_snapshot, actor_type, session_scope,
                    mfa_method, step_up, action, target_type, target_id, occurred_at,
                    correlation_id, result, metadata)
                VALUES (?, ?, 'BOOTSTRAP', NULL, 'TOTP', TRUE, 'PLATFORM_SUPERADMIN_BOOTSTRAP',
                        'PLATFORM_ADMIN', ?, ?, ?, 'SUCCESS', '{}'::jsonb)
                """, userId, username, Long.toString(userId),
                Timestamp.from(clock.instant()), correlationId);
    }

    public void system(long userId, String username, String action, String targetType,
                       String targetId, UUID correlationId) {
        jdbc.update("""
                INSERT INTO platform_audit_events(
                    actor_usuario_id, actor_username_snapshot, actor_type, session_scope,
                    step_up, action, target_type, target_id, occurred_at,
                    correlation_id, result, metadata)
                VALUES (?, ?, 'SYSTEM', NULL, FALSE, ?, ?, ?, ?, ?, 'SUCCESS', '{}'::jsonb)
                """, userId, username, action, targetType, targetId,
                Timestamp.from(clock.instant()), correlationId);
    }

    private void record(PlatformPrincipal actor, String actorType, String action,
                        String targetType, String targetId, UUID tenantId, UUID correlationId,
                        String idempotencyKey, String result, boolean stepUp,
                        Map<String, ?> metadata) {
        if (actor == null || correlationId == null) {
            throw new IllegalArgumentException("Actor y correlation ID son obligatorios para auditoría");
        }
        jdbc.update("""
                INSERT INTO platform_audit_events(
                    actor_usuario_id, actor_username_snapshot, actor_type, session_scope,
                    mfa_method, step_up, action, target_type, target_id, target_tenant_id,
                    occurred_at, correlation_id, idempotency_key, result, metadata)
                VALUES (?, ?, ?, 'PLATFORM', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CAST(? AS jsonb))
                """, actor.userId(), actor.username(), actorType, stepUp ? "TOTP" : null,
                stepUp, action, targetType,
                targetId, tenantId, Timestamp.from(clock.instant()), correlationId,
                idempotencyKey, result,
                json(metadata));
    }

    private void isolated(String result, PlatformPrincipal actor, String action,
                          String targetType, String targetId, UUID tenantId,
                          UUID correlationId, String idempotencyKey, Map<String, ?> metadata) {
        isolatedTransactions.executeWithoutResult(status -> record(
                actor, "PLATFORM", action, targetType, targetId, existingTenant(tenantId),
                correlationId, idempotencyKey, result, false, metadata));
    }

    private UUID existingTenant(UUID tenantId) {
        if (tenantId == null) return null;
        return jdbc.query("SELECT id FROM tenants WHERE id = ?",
                (result, row) -> (UUID) result.getObject(1), tenantId)
                .stream().findFirst().orElse(null);
    }

    private String json(Map<String, ?> metadata) {
        try {
            return objectMapper.writeValueAsString(metadata == null ? Map.of() : metadata);
        } catch (JsonProcessingException exception) {
            throw new IllegalArgumentException("Metadata de auditoría inválida", exception);
        }
    }
}
