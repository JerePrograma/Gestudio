package gestudio.platform.control;

import com.fasterxml.jackson.databind.ObjectMapper;
import gestudio.infra.errores.TratadorDeErrores.OperacionNoPermitidaException;
import gestudio.infra.errores.TratadorDeErrores.RecursoNoEncontradoException;
import gestudio.infra.observabilidad.RequestCorrelationFilter;
import gestudio.infra.persistencia.PostgreSqlIntegrationTest;
import gestudio.platform.security.PlatformPreconditionRequiredException;
import gestudio.platform.security.PlatformPrincipal;
import gestudio.platform.security.PlatformStepUpService;
import gestudio.platform.security.PlatformTokenService;
import gestudio.tenancy.TenantAwareDataSource;
import gestudio.tenancy.TenantContext;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.Timeout;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.dao.DataAccessException;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.SingleConnectionDataSource;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.sql.Timestamp;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.catchThrowableOfType;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
class PlatformControlPlanePostgreSqlTest extends PostgreSqlIntegrationTest {
    private static final String MFA_KEY = Base64.getEncoder().encodeToString(
            "12345678901234567890123456789012".getBytes(StandardCharsets.US_ASCII));
    private static final byte[] TOTP_SECRET =
            "12345678901234567890".getBytes(StandardCharsets.US_ASCII);
    private static final String TOTP_SECRET_BASE32 =
            "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ";

    @DynamicPropertySource
    static void platformProperties(DynamicPropertyRegistry registry) {
        registry.add("app.platform-security.mfa-encryption-key", () -> MFA_KEY);
        registry.add("app.platform-security.refresh-cookie.secure", () -> false);
    }

    @Autowired private PlatformControlPlaneService controlPlane;
    @Autowired private PlatformAuditService platformAudit;
    @Autowired private PlatformIdentityActivationService identityActivation;
    @Autowired private PlatformStepUpService stepUp;
    @Autowired private PlatformTokenService platformTokens;
    @Autowired private PasswordEncoder passwordEncoder;
    @Autowired private Clock clock;
    @Autowired private ObjectMapper objectMapper;
    @Autowired private MockMvc mockMvc;
    @Autowired @Qualifier("platformJdbcTemplate") private JdbcTemplate jdbc;

    private long actorId;
    private PlatformPrincipal actor;

    @BeforeEach
    void createPlatformActorAndSession() {
        actor = platformActor("cp-actor");
        actorId = actor.userId();
    }

    @Test
    void provisioningIsAtomicMaterializesExactRoleMatrixAndSupportsExistingAndNewIdentity() {
        long existingUser = insertUser(unique("cp-existing-admin"), true);
        String existingCode = tenantCode("existing");
        String existingKey = key("existing");
        UUID correlationId = UUID.randomUUID();

        PlatformControlPlaneService.ProvisionedTenant existing = controlPlane.createTenant(
                new PlatformControlPlaneService.CreateTenant(existingCode, "Academia existente",
                        existingIdentity(existingUser)), actor, existingKey,
                proof(PlatformControlPlaneService.TENANT_CREATE, "TENANT", existingCode, existingKey).raw(),
                correlationId);

        assertThat(existing.replayed()).isFalse();
        assertThat(existing.activation()).isNull();
        assertThat(existing.tenant().status()).isEqualTo("ACTIVE");
        assertThat(existing.tenant().roleCount()).isEqualTo(6);
        assertThat(existing.initialAdmin().userId()).isEqualTo(existingUser);
        assertThat(existing.initialAdmin().status()).isEqualTo("ACTIVE");
        assertThat(existing.initialAdmin().roles()).containsExactly("ADMINISTRADOR");
        assertExactBaseRoleMatrix(existing.tenant().id());
        assertSuccessfulAudit(PlatformControlPlaneService.TENANT_CREATE,
                existing.tenant().id(), correlationId, existingKey);

        PlatformControlPlaneRepository.PageData<PlatformControlPlaneRepository.TenantView> listing =
                controlPlane.tenants(existingCode, "ACTIVE", 0, 10);
        assertThat(listing.content()).singleElement()
                .satisfies(tenant -> assertThat(tenant.roleCount()).isEqualTo(6));
        assertThat(controlPlane.tenants(null, null, 0, 25).content())
                .extracting(PlatformControlPlaneRepository.TenantView::id)
                .contains(existing.tenant().id());

        String newCode = tenantCode("new");
        String newKey = key("new");
        String newUsername = unique("cp-new-admin");
        PlatformControlPlaneService.ProvisionedTenant created = controlPlane.createTenant(
                new PlatformControlPlaneService.CreateTenant(newCode, "Academia nueva",
                        new PlatformControlPlaneService.IdentityRequest("NEW", null, newUsername)),
                actor, newKey,
                proof(PlatformControlPlaneService.TENANT_CREATE, "TENANT", newCode, newKey).raw(),
                UUID.randomUUID());

        assertThat(created.activation()).isNotNull();
        assertThat(created.activation().token()).matches("[A-Za-z0-9_-]{43}");
        long newUserId = created.initialAdmin().userId();
        assertThat(jdbc.queryForObject(
                "SELECT activo FROM usuarios WHERE id=?", Boolean.class, newUserId)).isFalse();
        assertThat(jdbc.queryForObject(
                "SELECT rol_id FROM usuarios WHERE id=?", Long.class, newUserId)).isNull();
        assertThat(jdbc.queryForObject(
                "SELECT count(*) FROM platform_admins WHERE usuario_id=?", Long.class, newUserId)).isZero();
        assertThat(jdbc.queryForObject("""
                SELECT token_hash FROM platform_identity_activations
                WHERE usuario_id=? AND purpose='IDENTITY_ACTIVATION' AND consumed_at IS NULL
                """, String.class, newUserId))
                .isEqualTo(PlatformStepUpService.hash(created.activation().token()))
                .isNotEqualTo(created.activation().token());

        PlatformIdentityActivationService.ActivationResult activation = identityActivation.activate(
                created.activation().token(), "tenant-activation-password", null, null,
                UUID.randomUUID());
        assertThat(activation.recoveryCodes()).isEmpty();
        assertThat(jdbc.queryForObject(
                "SELECT activo FROM usuarios WHERE id=?", Boolean.class, newUserId)).isTrue();
        assertThat(passwordEncoder.matches("tenant-activation-password", jdbc.queryForObject(
                "SELECT contrasena FROM usuarios WHERE id=?", String.class, newUserId))).isTrue();
        assertThat(jdbc.queryForObject("""
                SELECT consumed_at IS NOT NULL FROM platform_identity_activations
                WHERE usuario_id=? AND purpose='IDENTITY_ACTIVATION'
                """, Boolean.class, newUserId)).isTrue();

        Long auditId = jdbc.queryForObject("""
                SELECT id FROM platform_audit_events
                WHERE action=? AND target_tenant_id=? AND correlation_id=?
                """, Long.class, PlatformControlPlaneService.TENANT_CREATE,
                existing.tenant().id(), correlationId);
        assertThatThrownBy(() -> jdbc.update(
                "UPDATE platform_audit_events SET metadata='{}'::jsonb WHERE id=?", auditId))
                .isInstanceOf(DataAccessException.class)
                .hasMessageContaining("append-only");
    }

    @Test
    @Timeout(40)
    void idempotencyRejectsDifferentPayloadAndSerializesConcurrentSamePayload() throws Exception {
        long userId = insertUser(unique("cp-idem-admin"), true);
        String code = tenantCode("idem");
        String requestKey = key("idem");
        PlatformControlPlaneService.CreateTenant command = new PlatformControlPlaneService.CreateTenant(
                code, "Academia idempotente", existingIdentity(userId));
        PreparedProof firstProof = proof(PlatformControlPlaneService.TENANT_CREATE,
                "TENANT", code, requestKey);

        PlatformControlPlaneService.ProvisionedTenant first = controlPlane.createTenant(
                command, actor, requestKey, firstProof.raw(), UUID.randomUUID());
        PlatformControlPlaneService.ProvisionedTenant replay = controlPlane.createTenant(
                command, actor, requestKey, null, UUID.randomUUID());

        assertThat(first.replayed()).isFalse();
        assertThat(replay.replayed()).isTrue();
        assertThat(replay.tenant().id()).isEqualTo(first.tenant().id());
        assertThat(replay.initialAdmin().id()).isEqualTo(first.initialAdmin().id());
        assertThat(jdbc.queryForObject(
                "SELECT count(*) FROM tenants WHERE code=?", Long.class, code)).isOne();
        assertThat(jdbc.queryForObject("""
                SELECT count(*) FROM platform_audit_events
                WHERE action=? AND idempotency_key=?
                """, Long.class, PlatformControlPlaneService.TENANT_CREATE, requestKey)).isOne();

        UUID conflictCorrelation = UUID.randomUUID();
        assertThatThrownBy(() -> controlPlane.createTenant(
                new PlatformControlPlaneService.CreateTenant(code, "Contenido diferente",
                        existingIdentity(userId)), actor, requestKey, null, conflictCorrelation))
                .isInstanceOf(OperacionNoPermitidaException.class)
                .hasMessageContaining("otro contenido");
        assertThat(jdbc.queryForObject("""
                SELECT count(*) FROM platform_audit_events
                WHERE action=? AND idempotency_key=? AND correlation_id=?
                  AND result='DENIED' AND target_tenant_id=?
                  AND metadata='{"reasonCode":"OPERATION_NOT_ALLOWED"}'::jsonb
                """, Long.class, PlatformControlPlaneService.TENANT_CREATE, requestKey,
                conflictCorrelation, first.tenant().id())).isOne();

        long concurrentUser = insertUser(unique("cp-concurrent-admin"), true);
        String concurrentCode = tenantCode("concurrent");
        String concurrentKey = key("concurrent");
        PlatformControlPlaneService.CreateTenant concurrentCommand =
                new PlatformControlPlaneService.CreateTenant(concurrentCode, "Academia concurrente",
                        existingIdentity(concurrentUser));
        String concurrentProof = proof(PlatformControlPlaneService.TENANT_CREATE,
                "TENANT", concurrentCode, concurrentKey).raw();
        CountDownLatch start = new CountDownLatch(1);
        ExecutorService executor = Executors.newFixedThreadPool(2);
        Future<PlatformControlPlaneService.ProvisionedTenant> left = executor.submit(() -> {
            start.await(10, TimeUnit.SECONDS);
            return controlPlane.createTenant(concurrentCommand, actor, concurrentKey,
                    concurrentProof, UUID.randomUUID());
        });
        Future<PlatformControlPlaneService.ProvisionedTenant> right = executor.submit(() -> {
            start.await(10, TimeUnit.SECONDS);
            return controlPlane.createTenant(concurrentCommand, actor, concurrentKey,
                    concurrentProof, UUID.randomUUID());
        });
        PlatformControlPlaneService.ProvisionedTenant leftResult;
        PlatformControlPlaneService.ProvisionedTenant rightResult;
        try {
            start.countDown();
            leftResult = left.get(25, TimeUnit.SECONDS);
            rightResult = right.get(25, TimeUnit.SECONDS);
        } finally {
            executor.shutdownNow();
            assertThat(executor.awaitTermination(5, TimeUnit.SECONDS)).isTrue();
        }

        assertThat(List.of(leftResult.replayed(), rightResult.replayed()))
                .containsExactlyInAnyOrder(false, true);
        assertThat(leftResult.tenant().id()).isEqualTo(rightResult.tenant().id());
        assertThat(jdbc.queryForObject(
                "SELECT count(*) FROM tenants WHERE code=?", Long.class, concurrentCode)).isOne();
        assertThat(jdbc.queryForObject("""
                SELECT count(*) FROM platform_idempotency_keys
                WHERE operation=? AND idempotency_key=? AND status='SUCCEEDED'
                """, Long.class, PlatformControlPlaneService.TENANT_CREATE, concurrentKey)).isOne();
        assertThat(jdbc.queryForObject("""
                SELECT count(*) FROM platform_audit_events
                WHERE action=? AND idempotency_key=?
                """, Long.class, PlatformControlPlaneService.TENANT_CREATE, concurrentKey)).isOne();
    }

    @Test
    void downstreamIdentityFailureRollsBackIdempotencyStepUpTenantRolesMembershipAndAudit() {
        String duplicateUsername = unique("cp-rollback-duplicate");
        long duplicateUser = insertUser(duplicateUsername, true);
        String code = tenantCode("rollback");
        String duplicateKey = key("rollback-duplicate");
        PreparedProof duplicateProof = proof(PlatformControlPlaneService.TENANT_CREATE,
                "TENANT", code, duplicateKey);
        UUID deterministicId = UUID.nameUUIDFromBytes(
                ("gestudio-tenant:" + duplicateKey).getBytes(StandardCharsets.UTF_8));

        UUID failureCorrelation = UUID.randomUUID();
        assertThatThrownBy(() -> controlPlane.createTenant(
                new PlatformControlPlaneService.CreateTenant(code, "Academia duplicada",
                        new PlatformControlPlaneService.IdentityRequest(
                                "NEW", null, duplicateUsername)),
                actor, duplicateKey, duplicateProof.raw(),
                failureCorrelation))
                .isInstanceOf(DataIntegrityViolationException.class);

        assertThat(jdbc.queryForObject(
                "SELECT count(*) FROM tenants WHERE code=?", Long.class, code)).isZero();
        assertThat(jdbc.queryForObject(
                "SELECT count(*) FROM tenants WHERE id=?", Long.class, deterministicId)).isZero();
        assertThat(jdbc.queryForObject(
                "SELECT count(*) FROM roles WHERE tenant_id=?", Long.class, deterministicId)).isZero();
        assertThat(jdbc.queryForObject(
                "SELECT count(*) FROM tenant_memberships WHERE tenant_id=?", Long.class, deterministicId)).isZero();
        assertThat(jdbc.queryForObject("""
                SELECT count(*) FROM platform_idempotency_keys
                WHERE operation=? AND idempotency_key=?
                """, Long.class, PlatformControlPlaneService.TENANT_CREATE, duplicateKey)).isZero();
        assertThat(jdbc.queryForObject(
                "SELECT consumed_at IS NULL FROM platform_step_up_challenges WHERE id=?",
                Boolean.class, duplicateProof.id())).isTrue();
        assertThat(jdbc.queryForObject("""
                SELECT count(*) FROM platform_audit_events
                WHERE action=? AND idempotency_key=? AND correlation_id=?
                  AND result='FAILED' AND target_tenant_id IS NULL
                  AND target_id=?
                  AND metadata='{"reasonCode":"DATABASE_FAILURE"}'::jsonb
                """, Long.class, PlatformControlPlaneService.TENANT_CREATE, duplicateKey,
                failureCorrelation, deterministicId.toString())).isOne();
        assertThat(jdbc.update("DELETE FROM usuarios WHERE id=?", duplicateUser)).isOne();
        assertThat(jdbc.queryForObject(
                "SELECT gestudio_multitenancy_health()", String.class)).isEqualTo("GREEN");
    }

    @Test
    void rejectedStepUpPurposeRollsBackClaimAndPersistsCorrelatedDeniedAudit() {
        String code = tenantCode("denied-step-up");
        String requestKey = key("denied-step-up");
        UUID correlationId = UUID.randomUUID();
        UUID deterministicId = UUID.nameUUIDFromBytes(
                ("gestudio-tenant:" + requestKey).getBytes(StandardCharsets.UTF_8));
        PreparedProof wrongPurpose = proof(PlatformControlPlaneService.TENANT_UPDATE,
                "TENANT", code, requestKey);

        assertThatThrownBy(() -> controlPlane.createTenant(
                new PlatformControlPlaneService.CreateTenant(code, "Academia denegada",
                        existingIdentity(actorId)), actor, requestKey, wrongPurpose.raw(),
                correlationId))
                .isInstanceOf(PlatformPreconditionRequiredException.class);

        assertThat(jdbc.queryForObject(
                "SELECT count(*) FROM tenants WHERE id=?", Long.class, deterministicId)).isZero();
        assertThat(jdbc.queryForObject("""
                SELECT count(*) FROM platform_idempotency_keys
                WHERE operation=? AND idempotency_key=?
                """, Long.class, PlatformControlPlaneService.TENANT_CREATE, requestKey)).isZero();
        assertThat(jdbc.queryForObject(
                "SELECT consumed_at IS NULL FROM platform_step_up_challenges WHERE id=?",
                Boolean.class, wrongPurpose.id())).isTrue();
        assertThat(jdbc.queryForObject("""
                SELECT count(*) FROM platform_audit_events
                WHERE action=? AND idempotency_key=? AND correlation_id=?
                  AND result='DENIED' AND target_tenant_id IS NULL
                  AND target_id=?
                  AND metadata='{"reasonCode":"STEP_UP_REQUIRED"}'::jsonb
                """, Long.class, PlatformControlPlaneService.TENANT_CREATE, requestKey,
                correlationId, deterministicId.toString())).isOne();
    }

    @Test
    void tenantSuspendAndReactivatePreserveFunctionalDataMembershipsRolesAndMatrix() {
        PlatformControlPlaneService.ProvisionedTenant provisioned = provisionTenant("lifecycle");
        UUID tenantId = provisioned.tenant().id();
        String document = "CP-" + UUID.randomUUID().toString().substring(0, 12);
        jdbc.update("""
                INSERT INTO alumnos(
                    tenant_id, nombre, fecha_incorporacion, documento, activo, version)
                VALUES (?, 'Alumno persistente', ?, ?, TRUE, 0)
                """, tenantId, LocalDate.now(), document);
        long roleCount = count("roles", tenantId);
        long permissionCount = jdbc.queryForObject(
                "SELECT count(*) FROM rol_permisos WHERE tenant_id=?", Long.class, tenantId);
        long membershipCount = count("tenant_memberships", tenantId);

        String suspendKey = key("tenant-suspend");
        PlatformControlPlaneRepository.TenantView suspended = controlPlane.changeTenantStatus(
                tenantId, "SUSPENDED", provisioned.tenant().version(), "Mantenimiento programado",
                actor, suspendKey,
                proof(PlatformControlPlaneService.TENANT_STATUS, "TENANT",
                        tenantId.toString(), suspendKey).raw(), UUID.randomUUID());
        assertThat(suspended.status()).isEqualTo("SUSPENDED");

        String reactivateKey = key("tenant-reactivate");
        PlatformControlPlaneRepository.TenantView reactivated = controlPlane.changeTenantStatus(
                tenantId, "ACTIVE", suspended.version(), "Mantenimiento finalizado", actor,
                reactivateKey,
                proof(PlatformControlPlaneService.TENANT_STATUS, "TENANT",
                        tenantId.toString(), reactivateKey).raw(), UUID.randomUUID());

        assertThat(reactivated.status()).isEqualTo("ACTIVE");
        assertThat(reactivated.version()).isEqualTo(provisioned.tenant().version() + 2);
        assertThat(count("roles", tenantId)).isEqualTo(roleCount);
        assertThat(jdbc.queryForObject(
                "SELECT count(*) FROM rol_permisos WHERE tenant_id=?", Long.class, tenantId))
                .isEqualTo(permissionCount);
        assertThat(count("tenant_memberships", tenantId)).isEqualTo(membershipCount);
        assertThat(jdbc.queryForObject("""
                SELECT count(*) FROM alumnos WHERE tenant_id=? AND documento=?
                """, Long.class, tenantId, document)).isOne();
        assertThat(controlPlane.memberships(tenantId, null, "ACTIVE", 0, 20).content())
                .extracting(PlatformControlPlaneRepository.MembershipView::id)
                .contains(provisioned.initialAdmin().id());
    }

    @Test
    void optimisticVersionIsRequiredAndAStaleWriteReturnsConflict() throws Exception {
        PlatformControlPlaneService.ProvisionedTenant provisioned = provisionTenant("optimistic");
        UUID tenantId = provisioned.tenant().id();
        long initialVersion = provisioned.tenant().version();
        String accessToken = platformTokens.issueAccess(actor);

        mockMvc.perform(patch("/api/platform/tenants/{tenantId}", tenantId)
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsBytes(Map.of(
                                "name", "Versión ausente"))))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"))
                .andExpect(jsonPath("$.fieldErrors[0].field").value("expectedVersion"));

        String firstKey = key("optimistic-first");
        PlatformControlPlaneRepository.TenantView firstUpdate = controlPlane.updateTenant(
                tenantId, "Versión vigente", initialVersion, actor, firstKey,
                proof(PlatformControlPlaneService.TENANT_UPDATE, "TENANT",
                        tenantId.toString(), firstKey).raw(), UUID.randomUUID());
        assertThat(firstUpdate.version()).isEqualTo(initialVersion + 1);

        String staleKey = key("optimistic-stale");
        PreparedProof staleProof = proof(PlatformControlPlaneService.TENANT_UPDATE,
                "TENANT", tenantId.toString(), staleKey);
        mockMvc.perform(patch("/api/platform/tenants/{tenantId}", tenantId)
                        .header("Authorization", "Bearer " + accessToken)
                        .header("Idempotency-Key", staleKey)
                        .header("X-Step-Up-Token", staleProof.raw())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsBytes(Map.of(
                                "name", "Escritura obsoleta",
                                "expectedVersion", initialVersion))))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("BUSINESS_CONFLICT"));

        PlatformControlPlaneRepository.TenantView current = controlPlane.tenant(tenantId);
        assertThat(current.name()).isEqualTo("Versión vigente");
        assertThat(current.version()).isEqualTo(initialVersion + 1);
    }

    @Test
    void membershipCreateRolesAndStatusAreVersionedAndLastTenantAdminIsProtected() {
        PlatformControlPlaneService.ProvisionedTenant provisioned = provisionTenant("memberships");
        UUID tenantId = provisioned.tenant().id();
        long memberUser = insertUser(unique("cp-member"), true);
        String createKey = key("membership-create");

        PlatformControlPlaneService.ProvisionedMembership provisionedMembership =
                controlPlane.createMembership(
                tenantId, new PlatformControlPlaneService.CreateMembership(
                        existingIdentity(memberUser), List.of("CAJA"), clock.instant().plusSeconds(3600)),
                actor, createKey,
                proof(PlatformControlPlaneService.MEMBERSHIP_CREATE, "TENANT",
                        tenantId.toString(), createKey).raw(), UUID.randomUUID());
        PlatformControlPlaneRepository.MembershipView created = provisionedMembership.membership();
        assertThat(provisionedMembership.activation()).isNull();
        assertThat(provisionedMembership.replayed()).isFalse();
        assertThat(created.roles()).containsExactly("CAJA");
        assertThat(created.status()).isEqualTo("ACTIVE");
        assertThat(created.version()).isZero();

        String rolesKey = key("membership-roles");
        PlatformControlPlaneRepository.MembershipView rolesUpdated = controlPlane.updateMembershipRoles(
                tenantId, created.id(), List.of("SECRETARIA", "CAJA", "SECRETARIA"),
                created.version(), actor, rolesKey,
                proof(PlatformControlPlaneService.MEMBERSHIP_ROLES, "TENANT_MEMBERSHIP",
                        created.id().toString(), rolesKey).raw(), UUID.randomUUID());
        assertThat(rolesUpdated.roles()).containsExactly("CAJA", "SECRETARIA");
        assertThat(rolesUpdated.version()).isEqualTo(1);

        String suspendKey = key("membership-suspend");
        PlatformControlPlaneRepository.MembershipView suspended = controlPlane.changeMembershipStatus(
                tenantId, created.id(), "SUSPENDED", rolesUpdated.version(), "Licencia temporal",
                actor, suspendKey,
                proof(PlatformControlPlaneService.MEMBERSHIP_STATUS, "TENANT_MEMBERSHIP",
                        created.id().toString(), suspendKey).raw(), UUID.randomUUID());
        assertThat(suspended.status()).isEqualTo("SUSPENDED");
        assertThat(suspended.version()).isEqualTo(2);

        String activeKey = key("membership-active");
        PlatformControlPlaneRepository.MembershipView active = controlPlane.changeMembershipStatus(
                tenantId, created.id(), "ACTIVE", suspended.version(), "Licencia finalizada",
                actor, activeKey,
                proof(PlatformControlPlaneService.MEMBERSHIP_STATUS, "TENANT_MEMBERSHIP",
                        created.id().toString(), activeKey).raw(), UUID.randomUUID());
        assertThat(active.status()).isEqualTo("ACTIVE");
        assertThat(active.version()).isEqualTo(3);

        String revokeKey = key("membership-revoke");
        PlatformControlPlaneRepository.MembershipView revoked = controlPlane.changeMembershipStatus(
                tenantId, created.id(), "REVOKED", active.version(), "Acceso finalizado",
                actor, revokeKey,
                proof(PlatformControlPlaneService.MEMBERSHIP_STATUS, "TENANT_MEMBERSHIP",
                        created.id().toString(), revokeKey).raw(), UUID.randomUUID());
        assertThat(revoked.status()).isEqualTo("REVOKED");
        assertThat(revoked.validUntil()).isNotNull();
        assertThat(revoked.roles()).containsExactly("CAJA", "SECRETARIA");

        String removeLastAdminKey = key("last-tenant-admin");
        PreparedProof removeLastAdminProof = proof(PlatformControlPlaneService.MEMBERSHIP_ROLES,
                "TENANT_MEMBERSHIP", provisioned.initialAdmin().id().toString(), removeLastAdminKey);
        assertThatThrownBy(() -> controlPlane.updateMembershipRoles(
                tenantId, provisioned.initialAdmin().id(), List.of("CAJA"),
                provisioned.initialAdmin().version(), actor, removeLastAdminKey,
                removeLastAdminProof.raw(), UUID.randomUUID()))
                .isInstanceOf(OperacionNoPermitidaException.class)
                .hasMessageContaining("último ADMINISTRADOR");
        assertThat(controlPlane.memberships(tenantId, null, null, 0, 20).content())
                .filteredOn(item -> item.id().equals(provisioned.initialAdmin().id()))
                .singleElement().satisfies(item -> assertThat(item.roles())
                        .containsExactly("ADMINISTRADOR"));
        assertThat(jdbc.queryForObject(
                "SELECT consumed_at IS NULL FROM platform_step_up_challenges WHERE id=?",
                Boolean.class, removeLastAdminProof.id())).isTrue();
    }

    @Test
    @Timeout(40)
    void concurrentDifferentMembershipMutationsLeaveExactlyOneTenantAdministrator()
            throws Exception {
        PlatformControlPlaneService.ProvisionedTenant provisioned =
                provisionTenant("tenant-admin-race");
        UUID tenantId = provisioned.tenant().id();
        PlatformPrincipal secondActor = platformActor("cp-tenant-race-actor");
        long secondAdminUser = insertUser(unique("cp-tenant-race-admin"), true);
        String createKey = key("tenant-race-create");
        PlatformControlPlaneRepository.MembershipView secondAdmin =
                controlPlane.createMembership(tenantId,
                        new PlatformControlPlaneService.CreateMembership(
                                existingIdentity(secondAdminUser),
                                List.of("ADMINISTRADOR"), null),
                        actor, createKey,
                        proof(actor, PlatformControlPlaneService.MEMBERSHIP_CREATE,
                                "TENANT", tenantId.toString(), createKey).raw(),
                        UUID.randomUUID()).membership();

        String removeRolesKey = key("tenant-race-roles");
        String revokeStatusKey = key("tenant-race-status");
        PreparedProof removeRolesProof = proof(actor,
                PlatformControlPlaneService.MEMBERSHIP_ROLES, "TENANT_MEMBERSHIP",
                provisioned.initialAdmin().id().toString(), removeRolesKey);
        PreparedProof revokeStatusProof = proof(secondActor,
                PlatformControlPlaneService.MEMBERSHIP_STATUS, "TENANT_MEMBERSHIP",
                secondAdmin.id().toString(), revokeStatusKey);
        CountDownLatch start = new CountDownLatch(1);
        ExecutorService executor = Executors.newFixedThreadPool(2);
        Future<Boolean> rolesMutation = executor.submit(() -> {
            if (!start.await(10, TimeUnit.SECONDS)) {
                throw new IllegalStateException("No se liberó el inicio concurrente");
            }
            try {
                controlPlane.updateMembershipRoles(tenantId, provisioned.initialAdmin().id(),
                        List.of("CAJA"), provisioned.initialAdmin().version(), actor,
                        removeRolesKey, removeRolesProof.raw(), UUID.randomUUID());
                return true;
            } catch (OperacionNoPermitidaException expected) {
                assertThat(expected).hasMessageContaining("último ADMINISTRADOR");
                return false;
            }
        });
        Future<Boolean> statusMutation = executor.submit(() -> {
            if (!start.await(10, TimeUnit.SECONDS)) {
                throw new IllegalStateException("No se liberó el inicio concurrente");
            }
            try {
                controlPlane.changeMembershipStatus(tenantId, secondAdmin.id(), "REVOKED",
                        secondAdmin.version(), "Prueba concurrente", secondActor,
                        revokeStatusKey, revokeStatusProof.raw(), UUID.randomUUID());
                return true;
            } catch (OperacionNoPermitidaException expected) {
                assertThat(expected).hasMessageContaining("último ADMINISTRADOR");
                return false;
            }
        });

        List<Boolean> outcomes;
        try {
            start.countDown();
            outcomes = List.of(rolesMutation.get(25, TimeUnit.SECONDS),
                    statusMutation.get(25, TimeUnit.SECONDS));
        } finally {
            executor.shutdownNow();
            assertThat(executor.awaitTermination(5, TimeUnit.SECONDS)).isTrue();
        }

        assertThat(outcomes).containsExactlyInAnyOrder(true, false);
        assertThat(activeTenantAdministratorCount(tenantId)).isOne();
        assertConcurrentAudit(removeRolesKey, revokeStatusKey);
    }

    @Test
    void adminGrantActivationRevokeReactivateResetAndLastAdminProtectionsAreAtomic() {
        Instant now = clock.instant();
        jdbc.update("UPDATE platform_admins SET active=FALSE, revoked_at=?", Timestamp.from(now));
        jdbc.update("UPDATE platform_admins SET active=TRUE, revoked_at=NULL WHERE usuario_id=?", actorId);
        long targetUser = insertUser(unique("cp-admin-target"), true);

        String grantKey = key("admin-grant");
        PlatformControlPlaneService.GrantedAdmin granted = controlPlane.grantAdmin(
                targetUser, actor, grantKey,
                proof(PlatformControlPlaneService.PLATFORM_ADMIN_GRANT, "PLATFORM_ADMIN",
                        Long.toString(targetUser), grantKey).raw(), UUID.randomUUID());
        assertThat(granted.admin().status()).isEqualTo("REVOKED");
        assertThat(granted.admin().mfaEnabled()).isFalse();
        assertThat(granted.activation()).isNotNull();
        assertThat(jdbc.queryForObject("""
                SELECT purpose FROM platform_identity_activations
                WHERE usuario_id=? AND consumed_at IS NULL
                """, String.class, targetUser)).isEqualTo("PLATFORM_MFA_ENROLLMENT");

        PlatformIdentityActivationService.ActivationResult enrolled = identityActivation.activate(
                granted.activation().token(), null, TOTP_SECRET_BASE32, currentTotp(), UUID.randomUUID());
        assertThat(enrolled.recoveryCodes()).hasSize(10).doesNotHaveDuplicates();
        assertThat(jdbc.queryForObject("""
                SELECT count(*) FROM platform_mfa_credentials
                WHERE usuario_id=? AND verified_at=created_at AND last_used_at=created_at
                """, Long.class, targetUser)).isOne();
        assertThat(jdbc.queryForObject(
                "SELECT active FROM platform_admins WHERE usuario_id=?", Boolean.class, targetUser)).isTrue();
        long enrolledVersion = jdbc.queryForObject(
                "SELECT security_version FROM platform_admins WHERE usuario_id=?", Long.class, targetUser);

        String revokeKey = key("admin-revoke");
        PlatformControlPlaneRepository.AdminView revoked = controlPlane.changeAdminStatus(
                targetUser, "REVOKED", enrolledVersion, "Revocación operativa", actor,
                revokeKey, proof(PlatformControlPlaneService.PLATFORM_ADMIN_STATUS,
                        "PLATFORM_ADMIN", Long.toString(targetUser), revokeKey).raw(), UUID.randomUUID());
        assertThat(revoked.status()).isEqualTo("REVOKED");

        String reactivateKey = key("admin-reactivate");
        PlatformControlPlaneRepository.AdminView active = controlPlane.changeAdminStatus(
                targetUser, "ACTIVE", revoked.version(), "Reactivación autorizada", actor,
                reactivateKey, proof(PlatformControlPlaneService.PLATFORM_ADMIN_STATUS,
                        "PLATFORM_ADMIN", Long.toString(targetUser), reactivateKey).raw(), UUID.randomUUID());
        assertThat(active.status()).isEqualTo("ACTIVE");
        assertThat(active.mfaEnabled()).isTrue();

        String resetKey = key("admin-reset");
        PlatformControlPlaneService.Activation reset = controlPlane.resetAdminMfa(
                targetUser, actor, resetKey,
                proof(PlatformControlPlaneService.PLATFORM_MFA_RESET, "PLATFORM_ADMIN",
                        Long.toString(targetUser), resetKey).raw(), UUID.randomUUID());
        assertThat(reset.token()).matches("[A-Za-z0-9_-]{43}");
        assertThat(jdbc.queryForObject("""
                SELECT purpose FROM platform_identity_activations
                WHERE usuario_id=? AND consumed_at IS NULL
                """, String.class, targetUser)).isEqualTo("PLATFORM_MFA_RESET");
        assertThat(jdbc.queryForObject(
                "SELECT active FROM platform_admins WHERE usuario_id=?", Boolean.class, targetUser)).isFalse();
        assertThat(jdbc.queryForObject("""
                SELECT count(*) FROM platform_mfa_credentials
                WHERE usuario_id=? AND revoked_at IS NULL
                """, Long.class, targetUser)).isZero();
        assertThat(jdbc.queryForObject(
                "SELECT count(*) FROM platform_admins WHERE active", Long.class)).isOne();

        String lastStatusKey = key("last-platform-admin-status");
        assertThatThrownBy(() -> controlPlane.changeAdminStatus(
                actorId, "REVOKED", 0L, "Intento de último administrador", actor,
                lastStatusKey, proof(PlatformControlPlaneService.PLATFORM_ADMIN_STATUS,
                        "PLATFORM_ADMIN", Long.toString(actorId), lastStatusKey).raw(), UUID.randomUUID()))
                .isInstanceOf(OperacionNoPermitidaException.class)
                .hasMessageContaining("último PLATFORM_SUPERADMIN");

        String lastResetKey = key("last-platform-admin-reset");
        assertThatThrownBy(() -> controlPlane.resetAdminMfa(
                actorId, actor, lastResetKey,
                proof(PlatformControlPlaneService.PLATFORM_MFA_RESET, "PLATFORM_ADMIN",
                        Long.toString(actorId), lastResetKey).raw(), UUID.randomUUID()))
                .isInstanceOf(OperacionNoPermitidaException.class)
                .hasMessageContaining("propio MFA");

        PlatformIdentityActivationService.ActivationResult resetActivated = identityActivation.activate(
                reset.token(), null, TOTP_SECRET_BASE32, currentTotp(), UUID.randomUUID());
        assertThat(resetActivated.recoveryCodes()).hasSize(10);
        assertThat(jdbc.queryForObject(
                "SELECT active FROM platform_admins WHERE usuario_id=?", Boolean.class, targetUser)).isTrue();
    }

    @Test
    @Timeout(40)
    void concurrentDifferentMfaResetsLeaveExactlyOnePlatformSuperadmin() throws Exception {
        Instant now = clock.instant();
        jdbc.update("UPDATE platform_admins SET active=FALSE, revoked_at=?", Timestamp.from(now));
        jdbc.update("UPDATE platform_admins SET active=TRUE, revoked_at=NULL WHERE usuario_id=?", actorId);
        PlatformPrincipal secondActor = platformActor("cp-platform-race-actor");

        String resetSecondKey = key("platform-race-reset-second");
        String resetFirstKey = key("platform-race-reset-first");
        PreparedProof resetSecondProof = proof(actor,
                PlatformControlPlaneService.PLATFORM_MFA_RESET, "PLATFORM_ADMIN",
                secondActor.userId().toString(), resetSecondKey);
        PreparedProof resetFirstProof = proof(secondActor,
                PlatformControlPlaneService.PLATFORM_MFA_RESET, "PLATFORM_ADMIN",
                actor.userId().toString(), resetFirstKey);
        CountDownLatch start = new CountDownLatch(1);
        ExecutorService executor = Executors.newFixedThreadPool(2);
        Future<Boolean> resetSecond = executor.submit(() -> {
            if (!start.await(10, TimeUnit.SECONDS)) {
                throw new IllegalStateException("No se liberó el inicio concurrente");
            }
            try {
                controlPlane.resetAdminMfa(secondActor.userId(), actor, resetSecondKey,
                        resetSecondProof.raw(), UUID.randomUUID());
                return true;
            } catch (OperacionNoPermitidaException expected) {
                assertThat(expected).hasMessageContaining("último PLATFORM_SUPERADMIN");
                return false;
            }
        });
        Future<Boolean> resetFirst = executor.submit(() -> {
            if (!start.await(10, TimeUnit.SECONDS)) {
                throw new IllegalStateException("No se liberó el inicio concurrente");
            }
            try {
                controlPlane.resetAdminMfa(actor.userId(), secondActor, resetFirstKey,
                        resetFirstProof.raw(), UUID.randomUUID());
                return true;
            } catch (OperacionNoPermitidaException expected) {
                assertThat(expected).hasMessageContaining("último PLATFORM_SUPERADMIN");
                return false;
            }
        });

        List<Boolean> outcomes;
        try {
            start.countDown();
            outcomes = List.of(resetSecond.get(25, TimeUnit.SECONDS),
                    resetFirst.get(25, TimeUnit.SECONDS));
        } finally {
            executor.shutdownNow();
            assertThat(executor.awaitTermination(5, TimeUnit.SECONDS)).isTrue();
        }

        assertThat(outcomes).containsExactlyInAnyOrder(true, false);
        assertThat(jdbc.queryForObject(
                "SELECT count(*) FROM platform_admins WHERE active", Long.class)).isOne();
        assertConcurrentAudit(resetSecondKey, resetFirstKey);
    }

    @Test
    void selfMfaResetIsDeniedAndAuditedEvenWhenAnotherAdminIsActive() {
        Instant now = clock.instant();
        jdbc.update("UPDATE platform_admins SET active=FALSE, revoked_at=?", Timestamp.from(now));
        jdbc.update("UPDATE platform_admins SET active=TRUE, revoked_at=NULL WHERE usuario_id=?", actorId);
        platformActor("cp-self-reset-backup");
        String requestKey = key("self-mfa-reset");
        UUID correlationId = UUID.randomUUID();
        PreparedProof prepared = proof(actor, PlatformControlPlaneService.PLATFORM_MFA_RESET,
                "PLATFORM_ADMIN", actor.userId().toString(), requestKey);

        assertThatThrownBy(() -> controlPlane.resetAdminMfa(actor.userId(), actor,
                requestKey, prepared.raw(), correlationId))
                .isInstanceOf(OperacionNoPermitidaException.class)
                .hasMessageContaining("propio MFA");

        assertThat(jdbc.queryForObject(
                "SELECT count(*) FROM platform_admins WHERE active", Long.class)).isEqualTo(2);
        assertThat(jdbc.queryForObject("""
                SELECT count(*) FROM platform_audit_events
                WHERE action=? AND target_id=? AND idempotency_key=? AND correlation_id=?
                  AND result='DENIED' AND NOT step_up AND mfa_method IS NULL
                """, Long.class, PlatformControlPlaneService.PLATFORM_MFA_RESET,
                actor.userId().toString(), requestKey, correlationId)).isOne();
        assertThat(jdbc.queryForObject(
                "SELECT consumed_at IS NULL FROM platform_step_up_challenges WHERE id=?",
                Boolean.class, prepared.id())).isTrue();
    }

    @Test
    void verifiedStepUpProofIsBoundToActorSessionPurposeTargetAndIdempotencyAndIsOneShot() {
        String key = key("step-up-binding");
        PreparedProof prepared = proof(PlatformControlPlaneService.TENANT_STATUS,
                "TENANT", "tenant-42", key);

        assertThatThrownBy(() -> stepUp.requireAndConsume(actor, prepared.raw(),
                PlatformControlPlaneService.TENANT_UPDATE, "TENANT", "tenant-42", key))
                .isInstanceOf(PlatformPreconditionRequiredException.class);
        assertThatThrownBy(() -> stepUp.requireAndConsume(actor, prepared.raw(),
                PlatformControlPlaneService.TENANT_STATUS, "TENANT", "other-tenant", key))
                .isInstanceOf(PlatformPreconditionRequiredException.class);
        PlatformPrincipal otherSession = new PlatformPrincipal(actor.userId(), actor.username(),
                actor.authVersion(), actor.platformSecurityVersion(), UUID.randomUUID(), actor.mfaVerifiedAt());
        assertThatThrownBy(() -> stepUp.requireAndConsume(otherSession, prepared.raw(),
                PlatformControlPlaneService.TENANT_STATUS, "TENANT", "tenant-42", key))
                .isInstanceOf(PlatformPreconditionRequiredException.class);
        assertThat(jdbc.queryForObject(
                "SELECT consumed_at IS NULL FROM platform_step_up_challenges WHERE id=?",
                Boolean.class, prepared.id())).isTrue();

        stepUp.requireAndConsume(actor, prepared.raw(), PlatformControlPlaneService.TENANT_STATUS,
                "TENANT", "tenant-42", key);
        assertThat(jdbc.queryForObject(
                "SELECT consumed_at IS NOT NULL FROM platform_step_up_challenges WHERE id=?",
                Boolean.class, prepared.id())).isTrue();
        assertThat(jdbc.queryForObject(
                "SELECT proof_hash FROM platform_step_up_challenges WHERE id=?",
                String.class, prepared.id()))
                .isEqualTo(PlatformStepUpService.hash(prepared.raw()))
                .isNotEqualTo(prepared.raw());
        assertThatThrownBy(() -> stepUp.requireAndConsume(actor, prepared.raw(),
                PlatformControlPlaneService.TENANT_STATUS, "TENANT", "tenant-42", key))
                .isInstanceOf(PlatformPreconditionRequiredException.class);
    }

    @Test
    void adversarialInputsAreRejectedAndLiteralXssIsStoredAsDataThroughPreparedSql() throws Exception {
        long userId = insertUser(unique("cp-adversarial-admin"), true);
        assertThatThrownBy(() -> controlPlane.createTenant(
                new PlatformControlPlaneService.CreateTenant("x';drop-table-tenants--", "Ataque",
                        existingIdentity(userId)), actor, key("sql-code"), null, UUID.randomUUID()))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("Código de tenant inválido");
        assertThatThrownBy(() -> controlPlane.createTenant(
                new PlatformControlPlaneService.CreateTenant(tenantCode("oversize-name"),
                        "x".repeat(151), existingIdentity(userId)), actor,
                key("oversize-name"), null, UUID.randomUUID()))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("Nombre de tenant inválido");
        assertThatThrownBy(() -> controlPlane.createTenant(
                new PlatformControlPlaneService.CreateTenant(tenantCode("oversize-key"), "Válido",
                        existingIdentity(userId)), actor, "k".repeat(151), null, UUID.randomUUID()))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("Idempotency-Key");
        assertThatThrownBy(() -> controlPlane.tenants(null, null, 0, 101))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("Paginación");
        assertThat(controlPlane.admins(null, null, 0, 100).content())
                .extracting(PlatformControlPlaneRepository.AdminView::userId)
                .contains(actor.userId());
        assertThatThrownBy(() -> controlPlane.tenant(UUID.randomUUID()))
                .isInstanceOf(RecursoNoEncontradoException.class);

        String xssCode = tenantCode("xss");
        String xssName = "<script>alert('xss')</script>";
        String xssKey = key("xss");
        PlatformControlPlaneService.ProvisionedTenant xss = controlPlane.createTenant(
                new PlatformControlPlaneService.CreateTenant(xssCode, xssName,
                        existingIdentity(userId)), actor, xssKey,
                proof(PlatformControlPlaneService.TENANT_CREATE, "TENANT", xssCode, xssKey).raw(),
                UUID.randomUUID());
        assertThat(xss.tenant().name()).isEqualTo(xssName);
        assertThat(jdbc.queryForObject(
                "SELECT name FROM tenants WHERE id=?", String.class, xss.tenant().id()))
                .isEqualTo(xssName);
        assertThat(controlPlane.tenants("' OR 1=1 -- " + UUID.randomUUID(), null, 0, 100).content())
                .isEmpty();
        assertThat(jdbc.queryForObject(
                "SELECT count(*) FROM tenants WHERE code=?", Long.class, xssCode)).isOne();

        String accessToken = platformTokens.issueAccess(actor);
        mockMvc.perform(get("/api/platform/tenants/not-a-uuid")
                        .header("Authorization", "Bearer " + accessToken))
                .andExpect(status().isBadRequest());
        Map<String, Object> invalidBody = Map.of(
                "code", tenantCode("http-oversize"),
                "name", "x".repeat(151),
                "initialAdmin", Map.of("mode", "EXISTING", "usuarioId", userId));
        mockMvc.perform(post("/api/platform/tenants")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsBytes(invalidBody)))
                .andExpect(status().isBadRequest());
    }

    @Test
    void membershipActivationIsDeliveredOnceWithNoStoreAndAuditUsesCanonicalDenied() throws Exception {
        PlatformControlPlaneService.ProvisionedTenant tenant = provisionTenant("http-membership");
        String username = unique("cp-http-new-member");
        String requestKey = key("http-membership");
        PreparedProof prepared = proof(PlatformControlPlaneService.MEMBERSHIP_CREATE,
                "TENANT", tenant.tenant().id().toString(), requestKey);
        String accessToken = platformTokens.issueAccess(actor);
        String suppliedRequestId = "platform-membership-request";
        UUID canonicalRequestId = UUID.nameUUIDFromBytes(
                suppliedRequestId.getBytes(StandardCharsets.UTF_8));
        Map<String, Object> request = Map.of(
                "identity", Map.of("mode", "NEW", "nombreUsuario", username),
                "roles", List.of("CAJA"));

        var first = mockMvc.perform(post("/api/platform/tenants/{tenantId}/memberships",
                                tenant.tenant().id())
                        .header("Authorization", "Bearer " + accessToken)
                        .header("Idempotency-Key", requestKey)
                        .header("X-Step-Up-Token", prepared.raw())
                        .header(RequestCorrelationFilter.HEADER_NAME, suppliedRequestId)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsBytes(request)))
                .andExpect(status().isCreated())
                .andReturn().getResponse();
        assertThat(first.getHeader("Cache-Control")).isEqualTo("no-store");
        assertThat(first.getHeader("Pragma")).isEqualTo("no-cache");
        assertThat(first.getHeader(RequestCorrelationFilter.HEADER_NAME))
                .isEqualTo(canonicalRequestId.toString());
        var firstJson = objectMapper.readTree(first.getContentAsByteArray());
        assertThat(firstJson.path("membership").path("nombreUsuario").asText()).isEqualTo(username);
        assertThat(firstJson.path("activation").path("token").asText())
                .matches("[A-Za-z0-9_-]{43}");
        assertThat(firstJson.path("replayed").asBoolean()).isFalse();
        String oneTimeToken = firstJson.path("activation").path("token").asText();
        assertThat(jdbc.queryForObject("""
                SELECT count(*) FROM platform_audit_events
                WHERE action=? AND idempotency_key=? AND correlation_id=?
                  AND result='SUCCESS' AND step_up AND mfa_method='TOTP'
                """, Long.class, PlatformControlPlaneService.MEMBERSHIP_CREATE,
                requestKey, canonicalRequestId)).isOne();

        var replay = mockMvc.perform(post("/api/platform/tenants/{tenantId}/memberships",
                                tenant.tenant().id())
                        .header("Authorization", "Bearer " + accessToken)
                        .header("Idempotency-Key", requestKey)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsBytes(request)))
                .andExpect(status().isOk())
                .andReturn().getResponse();
        assertThat(replay.getHeader("Cache-Control")).isEqualTo("no-store");
        assertThat(replay.getHeader("Pragma")).isEqualTo("no-cache");
        var replayJson = objectMapper.readTree(replay.getContentAsByteArray());
        assertThat(replayJson.path("membership").path("id").asText())
                .isEqualTo(firstJson.path("membership").path("id").asText());
        assertThat(replayJson.path("activation").isNull()).isTrue();
        assertThat(replayJson.path("replayed").asBoolean()).isTrue();
        assertThat(replay.getContentAsString()).doesNotContain(oneTimeToken);

        UUID deniedCorrelation = UUID.randomUUID();
        platformAudit.denied(actor, "ADVERSARIAL_DENIAL", "TENANT",
                tenant.tenant().id().toString(), tenant.tenant().id(), deniedCorrelation,
                null, Map.of("reason", "test"));
        assertThat(jdbc.queryForObject("""
                SELECT count(*) FROM platform_audit_events
                WHERE action='ADVERSARIAL_DENIAL' AND correlation_id=?
                  AND result='DENIED' AND NOT step_up AND mfa_method IS NULL
                """, Long.class, deniedCorrelation)).isOne();
        var audit = mockMvc.perform(get("/api/platform/audit")
                        .header("Authorization", "Bearer " + accessToken)
                        .param("result", "DENIED")
                        .param("correlationId", deniedCorrelation.toString())
                        .param("page", "0").param("size", "20"))
                .andExpect(status().isOk())
                .andReturn().getResponse();
        var auditJson = objectMapper.readTree(audit.getContentAsByteArray());
        assertThat(auditJson.path("content").size()).isOne();
        assertThat(auditJson.path("content").get(0).path("result").asText()).isEqualTo("DENIED");
    }

    @Test
    void applicationAndPlatformRolesEnforceCommandSpecificMembershipRlsAndLeastPrivilege()
            throws Exception {
        PlatformControlPlaneService.ProvisionedTenant tenantA = provisionTenant("rls-a");
        PlatformControlPlaneService.ProvisionedTenant tenantB = provisionTenant("rls-b");
        long roleA = roleId(tenantA.tenant().id(), "CAJA");
        long roleB = roleId(tenantB.tenant().id(), "CAJA");

        try (Connection connection = ownerConnection()) {
            setRole(connection, "gestudio_app");
            setTenant(connection, null);
            assertThat(scalar(connection, "SELECT count(*) FROM tenant_memberships"))
                    .isGreaterThanOrEqualTo(2);
            assertSqlState("42501", () -> scalar(
                    connection, "SELECT count(*) FROM tenant_membership_roles"));
            assertSqlState("42501", () -> update(connection, """
                    UPDATE tenant_memberships SET updated_at=updated_at WHERE id=?
                    """, tenantA.initialAdmin().id()));
            assertSqlState("42501", () -> update(connection, """
                    INSERT INTO tenant_membership_roles(membership_id, tenant_id, role_id)
                    VALUES (?, ?, ?)
                    """, tenantA.initialAdmin().id(), tenantA.tenant().id(), roleA));

            setTenant(connection, tenantA.tenant().id());
            assertThat(update(connection,
                    "UPDATE tenant_memberships SET updated_at=updated_at WHERE id=?",
                    tenantA.initialAdmin().id())).isOne();
            assertThat(update(connection,
                    "UPDATE tenant_memberships SET updated_at=updated_at WHERE id=?",
                    tenantB.initialAdmin().id())).isZero();
            assertThat(scalar(connection, """
                    SELECT count(*) FROM tenant_membership_roles WHERE tenant_id <> ?
                    """, tenantA.tenant().id())).isZero();
            assertThat(update(connection, """
                    INSERT INTO tenant_membership_roles(
                        membership_id, tenant_id, role_id, assigned_by_usuario_id)
                    VALUES (?, ?, ?, ?)
                    """, tenantA.initialAdmin().id(), tenantA.tenant().id(), roleA, actorId)).isOne();
            assertThat(update(connection, """
                    DELETE FROM tenant_membership_roles
                    WHERE membership_id=? AND tenant_id=? AND role_id=?
                    """, tenantA.initialAdmin().id(), tenantA.tenant().id(), roleA)).isOne();
            assertSqlState("42501", () -> update(connection, """
                    INSERT INTO tenant_membership_roles(membership_id, tenant_id, role_id)
                    VALUES (?, ?, ?)
                    """, tenantB.initialAdmin().id(), tenantB.tenant().id(), roleB));
            assertThat(update(connection, """
                    DELETE FROM tenant_membership_roles WHERE membership_id=? AND tenant_id=?
                    """, tenantB.initialAdmin().id(), tenantB.tenant().id())).isZero();

            resetRole(connection);
            setRole(connection, "gestudio_platform");
            setTenant(connection, null);
            assertThat(scalar(connection, "SELECT count(*) FROM tenant_memberships"))
                    .isGreaterThanOrEqualTo(2);
            assertSqlState("42501", () -> scalar(connection, "SELECT count(*) FROM roles"));
            assertSqlState("42501", () -> scalar(connection, "SELECT count(*) FROM alumnos"));

            PlatformControlPlaneRepository runtimeRepository = new PlatformControlPlaneRepository(
                    new JdbcTemplate(new TenantAwareDataSource(
                            new SingleConnectionDataSource(connection, true))));
            TenantContext.clear();
            try {
                var runtimeListing = runtimeRepository.tenants(null, null, 0, 100);
                assertThat(runtimeListing.content().stream()
                        .filter(tenant -> tenant.id().equals(tenantA.tenant().id()))
                        .findFirst().orElseThrow().roleCount()).isEqualTo(6);
                assertThat(runtimeListing.content().stream()
                        .filter(tenant -> tenant.id().equals(tenantB.tenant().id()))
                        .findFirst().orElseThrow().roleCount()).isEqualTo(6);
                assertThat(TenantContext.currentTenantId()).isEmpty();
            } finally {
                selectMembership(null);
            }

            setTenant(connection, tenantA.tenant().id());
            assertThat(scalar(connection, "SELECT count(*) FROM roles")).isEqualTo(6);
            assertThat(scalar(connection,
                    "SELECT count(*) FROM roles WHERE tenant_id <> ?", tenantA.tenant().id())).isZero();
            assertThat(update(connection,
                    "UPDATE roles SET nombre=nombre WHERE tenant_id=?", tenantA.tenant().id()))
                    .isEqualTo(6);
            assertThat(update(connection,
                    "UPDATE roles SET nombre=nombre WHERE tenant_id=?", tenantB.tenant().id()))
                    .isZero();
            resetRole(connection);

            assertThat(bool(connection, """
                    SELECT NOT rolsuper AND NOT rolcanlogin AND NOT rolcreatedb
                           AND NOT rolcreaterole AND NOT rolinherit
                           AND NOT rolreplication AND NOT rolbypassrls
                    FROM pg_roles WHERE rolname='gestudio_platform'
                    """)).isTrue();
            assertThat(bool(connection,
                    "SELECT has_table_privilege('gestudio_app','tenant_membership_roles','SELECT')"))
                    .isTrue();
            assertThat(bool(connection,
                    "SELECT has_table_privilege('gestudio_app','tenant_membership_roles','INSERT')"))
                    .isTrue();
            assertThat(bool(connection,
                    "SELECT has_table_privilege('gestudio_app','tenant_membership_roles','UPDATE')"))
                    .isTrue();
            assertThat(bool(connection,
                    "SELECT has_table_privilege('gestudio_app','tenant_membership_roles','DELETE')"))
                    .isTrue();
            assertThat(bool(connection,
                    "SELECT has_table_privilege('gestudio_app','platform_admins','INSERT')"))
                    .isFalse();
            assertThat(bool(connection,
                    "SELECT has_table_privilege('gestudio_platform','alumnos','SELECT')"))
                    .isFalse();
            assertThat(scalar(connection, """
                    SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
                    WHERE n.nspname='public'
                      AND c.relname IN ('tenant_memberships','tenant_membership_roles')
                      AND c.relrowsecurity AND c.relforcerowsecurity
                    """)).isEqualTo(2);
            assertThat(scalar(connection, """
                    SELECT count(*)
                    FROM pg_policy p
                    JOIN pg_class c ON c.oid=p.polrelid
                    JOIN pg_namespace n ON n.oid=c.relnamespace
                    WHERE n.nspname='public'
                      AND ((c.relname='tenant_memberships' AND p.polcmd IN ('r','a','w'))
                        OR (c.relname='tenant_membership_roles' AND p.polcmd IN ('r','a','w','d')))
                    """)).isEqualTo(7);
        }
    }

    private PlatformControlPlaneService.ProvisionedTenant provisionTenant(String prefix) {
        long userId = insertUser(unique("cp-" + prefix + "-admin"), true);
        String code = tenantCode(prefix);
        String requestKey = key(prefix);
        return controlPlane.createTenant(new PlatformControlPlaneService.CreateTenant(
                        code, "Academia " + prefix, existingIdentity(userId)), actor, requestKey,
                proof(PlatformControlPlaneService.TENANT_CREATE, "TENANT", code, requestKey).raw(),
                UUID.randomUUID());
    }

    private PlatformControlPlaneService.IdentityRequest existingIdentity(long userId) {
        return new PlatformControlPlaneService.IdentityRequest("EXISTING", userId, null);
    }

    private PreparedProof proof(String action, String targetType, String targetId,
                                String idempotencyKey) {
        return proof(actor, action, targetType, targetId, idempotencyKey);
    }

    private PreparedProof proof(PlatformPrincipal proofActor, String action,
                                String targetType, String targetId,
                                String idempotencyKey) {
        String raw = "proof-" + UUID.randomUUID();
        UUID id = UUID.randomUUID();
        Instant now = clock.instant();
        jdbc.update("""
                INSERT INTO platform_step_up_challenges(
                    id, usuario_id, session_id, action, target_type, target_id,
                    idempotency_key, correlation_id, mfa_method, proof_hash,
                    issued_at, expires_at, verified_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'TOTP', ?, ?, ?, ?)
                """, id, proofActor.userId(), proofActor.sessionId(), action, targetType, targetId,
                idempotencyKey, UUID.randomUUID(), PlatformStepUpService.hash(raw),
                Timestamp.from(now.minusSeconds(2)), Timestamp.from(now.plusSeconds(300)),
                Timestamp.from(now.minusSeconds(1)));
        return new PreparedProof(id, raw);
    }

    private PlatformPrincipal platformActor(String prefix) {
        long userId = insertUser(unique(prefix), true);
        Instant now = clock.instant();
        jdbc.update("""
                INSERT INTO platform_admins(
                    usuario_id, active, granted_at, security_version, mfa_required, updated_at)
                VALUES (?, TRUE, ?, 0, TRUE, ?)
                """, userId, Timestamp.from(now), Timestamp.from(now));

        UUID sessionId = UUID.randomUUID();
        Instant issuedAt = now.minusSeconds(10);
        Instant mfaVerifiedAt = now.minusSeconds(20);
        jdbc.update("""
                INSERT INTO platform_refresh_sessions(
                    id, family_id, usuario_id, session_scope, token_hash,
                    auth_version, platform_security_version, mfa_verified_at,
                    issued_at, expires_at, family_expires_at)
                VALUES (?, ?, ?, 'PLATFORM', ?, 0, 0, ?, ?, ?, ?)
                """, sessionId, UUID.randomUUID(), userId,
                PlatformStepUpService.hash("refresh-" + UUID.randomUUID()),
                Timestamp.from(mfaVerifiedAt), Timestamp.from(issuedAt),
                Timestamp.from(now.plusSeconds(3600)), Timestamp.from(now.plusSeconds(7200)));
        return new PlatformPrincipal(userId, username(userId), 0, 0,
                sessionId, mfaVerifiedAt);
    }

    private long activeTenantAdministratorCount(UUID tenantId) {
        return jdbc.queryForObject("""
                SELECT count(DISTINCT m.id)
                FROM tenant_memberships m
                JOIN tenant_membership_roles mr
                  ON mr.membership_id=m.id AND mr.tenant_id=m.tenant_id
                JOIN roles r ON r.id=mr.role_id AND r.tenant_id=m.tenant_id
                WHERE m.tenant_id=? AND m.status='ACTIVE' AND r.codigo='ADMINISTRADOR'
                """, Long.class, tenantId);
    }

    private void assertConcurrentAudit(String firstKey, String secondKey) {
        assertThat(jdbc.queryForObject("""
                SELECT count(*) FROM platform_audit_events
                WHERE idempotency_key IN (?, ?) AND result='SUCCESS'
                  AND step_up AND mfa_method='TOTP'
                """, Long.class, firstKey, secondKey)).isOne();
        assertThat(jdbc.queryForObject("""
                SELECT count(*) FROM platform_audit_events
                WHERE idempotency_key IN (?, ?) AND result='DENIED'
                  AND NOT step_up AND mfa_method IS NULL
                """, Long.class, firstKey, secondKey)).isOne();
    }

    private long insertUser(String username, boolean active) {
        Long id = jdbc.queryForObject("""
                INSERT INTO usuarios(
                    nombre_usuario, contrasena, rol_id, activo, auth_version, version)
                VALUES (?, ?, NULL, ?, 0, 0)
                RETURNING id
                """, Long.class, username, passwordEncoder.encode("test-password-value"), active);
        if (id == null) throw new IllegalStateException("Usuario de prueba sin id");
        return id;
    }

    private String username(long userId) {
        return jdbc.queryForObject(
                "SELECT nombre_usuario FROM usuarios WHERE id=?", String.class, userId);
    }

    private void assertExactBaseRoleMatrix(UUID tenantId) {
        Map<String, Long> matrix = jdbc.query("""
                SELECT r.codigo, count(rp.permiso_id) permission_count
                FROM roles r
                LEFT JOIN rol_permisos rp ON rp.tenant_id=r.tenant_id AND rp.rol_id=r.id
                WHERE r.tenant_id=?
                GROUP BY r.codigo
                """, (result, row) -> Map.entry(result.getString("codigo"),
                result.getLong("permission_count")), tenantId).stream()
                .collect(java.util.stream.Collectors.toMap(Map.Entry::getKey, Map.Entry::getValue));
        assertThat(matrix).containsExactlyInAnyOrderEntriesOf(Map.of(
                "SUPERADMIN", 32L,
                "DIRECCION", 31L,
                "ADMINISTRADOR", 31L,
                "SECRETARIA", 17L,
                "CAJA", 8L,
                "PROFESOR", 0L));
        assertThat(jdbc.queryForObject("""
                SELECT count(*) FROM roles WHERE tenant_id=? AND codigo='PROFESOR' AND NOT activo
                """, Long.class, tenantId)).isOne();
    }

    private void assertSuccessfulAudit(String action, UUID tenantId, UUID correlationId, String key) {
        assertThat(jdbc.queryForObject("""
                SELECT count(*) FROM platform_audit_events
                WHERE actor_usuario_id=? AND action=? AND target_tenant_id=?
                  AND correlation_id=? AND idempotency_key=?
                  AND result='SUCCESS' AND step_up
                """, Long.class, actorId, action, tenantId, correlationId, key)).isOne();
    }

    private long count(String table, UUID tenantId) {
        if (!List.of("roles", "tenant_memberships").contains(table)) {
            throw new IllegalArgumentException("Tabla de test no permitida");
        }
        return jdbc.queryForObject(
                "SELECT count(*) FROM " + table + " WHERE tenant_id=?", Long.class, tenantId);
    }

    private long roleId(UUID tenantId, String code) {
        Long value = jdbc.queryForObject(
                "SELECT id FROM roles WHERE tenant_id=? AND codigo=?", Long.class, tenantId, code);
        if (value == null) throw new IllegalStateException("Rol de prueba ausente");
        return value;
    }

    private String currentTotp() {
        long counter = Math.floorDiv(clock.instant().getEpochSecond(), 30);
        try {
            Mac mac = Mac.getInstance("HmacSHA1");
            mac.init(new SecretKeySpec(TOTP_SECRET, "HmacSHA1"));
            byte[] digest = mac.doFinal(ByteBuffer.allocate(Long.BYTES).putLong(counter).array());
            int offset = digest[digest.length - 1] & 0x0f;
            int binary = ((digest[offset] & 0x7f) << 24)
                    | ((digest[offset + 1] & 0xff) << 16)
                    | ((digest[offset + 2] & 0xff) << 8)
                    | (digest[offset + 3] & 0xff);
            return "%06d".formatted(binary % 1_000_000);
        } catch (java.security.GeneralSecurityException exception) {
            throw new IllegalStateException(exception);
        }
    }

    private static String unique(String prefix) {
        return prefix + "-" + UUID.randomUUID();
    }

    private static String tenantCode(String prefix) {
        String safePrefix = prefix.toLowerCase().replaceAll("[^a-z0-9-]", "-");
        return (safePrefix + "-" + UUID.randomUUID().toString().substring(0, 12))
                .substring(0, Math.min(50, safePrefix.length() + 13));
    }

    private static String key(String prefix) {
        return prefix + "-" + UUID.randomUUID();
    }

    private static Connection ownerConnection() throws SQLException {
        return DriverManager.getConnection(
                POSTGRESQL.getJdbcUrl(), POSTGRESQL.getUsername(), POSTGRESQL.getPassword());
    }

    private static void setRole(Connection connection, String role) throws SQLException {
        if (!List.of("gestudio_app", "gestudio_platform").contains(role)) {
            throw new IllegalArgumentException("Rol de test no permitido");
        }
        try (Statement statement = connection.createStatement()) {
            statement.execute("SET ROLE " + role);
        }
    }

    private static void resetRole(Connection connection) throws SQLException {
        try (Statement statement = connection.createStatement()) {
            statement.execute("RESET ROLE");
        }
        setTenant(connection, null);
    }

    private static void setTenant(Connection connection, UUID tenantId) throws SQLException {
        try (PreparedStatement statement = connection.prepareStatement(
                "SELECT set_config('app.current_tenant_id', ?, false)")) {
            statement.setString(1, tenantId == null ? "" : tenantId.toString());
            statement.execute();
        }
    }

    private static long scalar(Connection connection, String sql, Object... parameters)
            throws SQLException {
        try (PreparedStatement statement = connection.prepareStatement(sql)) {
            bind(statement, parameters);
            try (ResultSet result = statement.executeQuery()) {
                if (!result.next()) throw new SQLException("Consulta escalar sin fila");
                return result.getLong(1);
            }
        }
    }

    private static boolean bool(Connection connection, String sql, Object... parameters)
            throws SQLException {
        try (PreparedStatement statement = connection.prepareStatement(sql)) {
            bind(statement, parameters);
            try (ResultSet result = statement.executeQuery()) {
                if (!result.next()) throw new SQLException("Consulta booleana sin fila");
                return result.getBoolean(1);
            }
        }
    }

    private static int update(Connection connection, String sql, Object... parameters)
            throws SQLException {
        try (PreparedStatement statement = connection.prepareStatement(sql)) {
            bind(statement, parameters);
            return statement.executeUpdate();
        }
    }

    private static void bind(PreparedStatement statement, Object... parameters) throws SQLException {
        for (int index = 0; index < parameters.length; index++) {
            statement.setObject(index + 1, parameters[index]);
        }
    }

    private static void assertSqlState(String expected, org.assertj.core.api.ThrowableAssert.ThrowingCallable action) {
        SQLException failure = catchThrowableOfType(action, SQLException.class);
        org.assertj.core.api.Assertions.assertThatObject(failure).isNotNull();
        assertThat(failure.getSQLState()).isEqualTo(expected);
    }

    private record PreparedProof(UUID id, String raw) {
    }
}
