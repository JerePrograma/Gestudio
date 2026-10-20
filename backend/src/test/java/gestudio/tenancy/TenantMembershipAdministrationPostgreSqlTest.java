package gestudio.tenancy;

import gestudio.infra.errores.TratadorDeErrores.OperacionNoPermitidaException;
import gestudio.dto.usuario.request.UsuarioModificacionRequest;
import gestudio.infra.persistencia.PostgreSqlIntegrationTest;
import gestudio.platform.control.PlatformControlPlaneRepository;
import gestudio.repositorios.UsuarioRepositorio;
import gestudio.servicios.usuario.UsuarioServicio;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.Timeout;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

import java.sql.Timestamp;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

@SpringBootTest
class TenantMembershipAdministrationPostgreSqlTest extends PostgreSqlIntegrationTest {
    @Autowired private JdbcTemplate jdbc;
    @Autowired private TenantMembershipManagementService memberships;
    @Autowired private TenantMembershipRepository membershipRepository;
    @Autowired private PlatformControlPlaneRepository platformRepository;
    @Autowired private UsuarioServicio usuarios;
    @Autowired private UsuarioRepositorio usuarioRepository;
    @Autowired @Qualifier("platformTransactionManager") private PlatformTransactionManager platformTransactions;

    private UUID tenantId;
    private long roleId;
    private long firstUser;
    private long secondUser;
    private UUID firstMembership;

    @BeforeEach
    void createDedicatedTenantAndAdministrators() {
        tenantId = UUID.randomUUID();
        jdbc.update("INSERT INTO tenants(id, code, name, status) VALUES (?, ?, 'Admin regression', 'ACTIVE')",
                tenantId, "admin-test-" + tenantId);
        try (TenantContext.Scope ignored = TenantContext.open(tenantId, null)) {
            roleId = jdbc.queryForObject("""
                    INSERT INTO roles(tenant_id, descripcion, codigo, nombre, activo, sistema, editable)
                    VALUES (?, 'Admin regression', 'ADMINISTRADOR', 'Administrador', TRUE, TRUE, FALSE)
                    RETURNING id
                    """, Long.class, tenantId);
            jdbc.update("""
                    INSERT INTO rol_permisos(tenant_id, rol_id, permiso_id)
                    SELECT ?, ?, id FROM permisos WHERE codigo IN ('PERM_APP_ACCESO', 'PERM_USUARIOS_ADMIN')
                    """, tenantId, roleId);
            firstUser = insertUser();
            secondUser = insertUser();
            firstMembership = insertMembership(firstUser);
            insertMembership(secondUser);
        }
    }

    @AfterEach
    void removeOnlyDedicatedFixtures() {
        if (tenantId == null) return;
        try (TenantContext.Scope ignored = TenantContext.open(DEFAULT_TENANT_ID, null)) {
            jdbc.update("""
                    DELETE FROM tenant_membership_roles
                    WHERE tenant_id = ? AND membership_id IN (
                        SELECT id FROM tenant_memberships WHERE tenant_id = ? AND usuario_id IN (?, ?))
                    """, DEFAULT_TENANT_ID, DEFAULT_TENANT_ID, firstUser, secondUser);
            jdbc.update("DELETE FROM tenant_memberships WHERE tenant_id = ? AND usuario_id IN (?, ?)",
                    DEFAULT_TENANT_ID, firstUser, secondUser);
        }
        try (TenantContext.Scope ignored = TenantContext.open(tenantId, null)) {
            jdbc.update("DELETE FROM tenant_membership_roles WHERE tenant_id = ?", tenantId);
            jdbc.update("DELETE FROM tenant_memberships WHERE tenant_id = ?", tenantId);
            jdbc.update("DELETE FROM usuarios WHERE id IN (?, ?)", firstUser, secondUser);
            jdbc.update("DELETE FROM rol_permisos WHERE tenant_id = ?", tenantId);
            jdbc.update("DELETE FROM roles WHERE tenant_id = ?", tenantId);
            jdbc.update("DELETE FROM tenants WHERE id = ?", tenantId);
        }
    }

    @Test
    @Timeout(30)
    void attachingIdentityToAnotherTenantSerializesWithLocalCredentialChanges() throws Exception {
        CountDownLatch identityLocked = new CountDownLatch(1);
        CountDownLatch allowProvisionCommit = new CountDownLatch(1);
        CountDownLatch editorStarted = new CountDownLatch(1);
        try (var executor = Executors.newFixedThreadPool(2)) {
            var provisioning = executor.submit(() -> {
                try (TenantContext.Scope ignored = TenantContext.open(DEFAULT_TENANT_ID, null)) {
                    return new TransactionTemplate(platformTransactions).execute(status -> {
                        platformRepository.identityForUpdate(secondUser).orElseThrow();
                        identityLocked.countDown();
                        await(allowProvisionCommit);
                        UUID id = platformRepository.insertMembership(DEFAULT_TENANT_ID,
                                secondUser, null, Instant.now());
                        platformRepository.assignRoles(DEFAULT_TENANT_ID, id, List.of("CAJA"), firstUser);
                        return id;
                    });
                }
            });
            try {
                assertThat(identityLocked.await(10, TimeUnit.SECONDS)).isTrue();
                var editing = executor.submit(() -> {
                    try (TenantContext.Scope ignored = TenantContext.open(tenantId, firstMembership)) {
                        var actor = usuarioRepository.findById(firstUser).orElseThrow();
                        editorStarted.countDown();
                        return usuarios.editarUsuario(secondUser, new UsuarioModificacionRequest(
                                null, "synthetic-password-reset", null, null), actor);
                    }
                });
                assertThat(editorStarted.await(10, TimeUnit.SECONDS)).isTrue();
                assertThatThrownBy(() -> editing.get(300, TimeUnit.MILLISECONDS))
                        .isInstanceOf(TimeoutException.class);
                allowProvisionCommit.countDown();
                assertThat(provisioning.get(10, TimeUnit.SECONDS)).isNotNull();
                assertThatThrownBy(() -> editing.get(10, TimeUnit.SECONDS))
                        .hasCauseInstanceOf(OperacionNoPermitidaException.class);
                assertThat(jdbc.queryForObject("SELECT contrasena FROM usuarios WHERE id = ?",
                        String.class, secondUser)).isEqualTo("synthetic-test-hash");
            } finally {
                allowProvisionCommit.countDown();
            }
        }
    }

    private static void await(CountDownLatch latch) {
        try {
            if (!latch.await(10, TimeUnit.SECONDS)) throw new IllegalStateException("Regression barrier timed out");
        } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException(interrupted);
        }
    }

    @Test
    @Timeout(30)
    void concurrentSuspensionsCannotRemoveBothAdministrators() throws Exception {
        CountDownLatch start = new CountDownLatch(1);
        try (var executor = Executors.newFixedThreadPool(2)) {
            var first = executor.submit(() -> suspendAfter(start, firstUser));
            var second = executor.submit(() -> suspendAfter(start, secondUser));
            start.countDown();
            List<Object> results = List.of(first.get(20, TimeUnit.SECONDS), second.get(20, TimeUnit.SECONDS));
            assertThat(results.stream().filter(Boolean.TRUE::equals)).hasSize(1);
            assertThat(results.stream().filter(OperacionNoPermitidaException.class::isInstance)).hasSize(1);
        }
        assertThat(jdbc.queryForObject("""
                SELECT count(*) FROM tenant_memberships WHERE tenant_id = ? AND status = 'ACTIVE'
                """, Long.class, tenantId)).isOne();
    }

    @Test
    void expiredOrInactiveIdentityDoesNotCountAsRecoverableAdministratorInEitherScope() {
        Instant now = Instant.now();
        try (TenantContext.Scope ignored = TenantContext.open(tenantId, firstMembership)) {
            jdbc.update("""
                    UPDATE tenant_memberships SET valid_from = ?, valid_until = ?
                    WHERE tenant_id = ? AND usuario_id = ?
                    """, Timestamp.from(now.minusSeconds(3600)), Timestamp.from(now.minusSeconds(60)),
                    tenantId, secondUser);
            assertBothCountsExcludeSecondIdentity(now);
            assertThatThrownBy(() -> memberships.update(firstUser, null, false, null))
                    .isInstanceOf(OperacionNoPermitidaException.class);
            assertThat(memberships.update(secondUser, null, false, null).getStatus())
                    .isEqualTo(TenantMembershipStatus.SUSPENDED);

            jdbc.update("UPDATE tenant_memberships SET status = 'ACTIVE', valid_until = NULL WHERE tenant_id = ?",
                    tenantId);
            jdbc.update("UPDATE usuarios SET activo = FALSE WHERE id = ?", secondUser);
            assertBothCountsExcludeSecondIdentity(now);
            assertThatThrownBy(() -> memberships.update(firstUser, null, false, null))
                    .isInstanceOf(OperacionNoPermitidaException.class);
            assertThat(memberships.update(secondUser, null, false, null).getStatus())
                    .isEqualTo(TenantMembershipStatus.SUSPENDED);

            jdbc.update("UPDATE usuarios SET activo = TRUE WHERE id = ?", secondUser);
            jdbc.update("""
                    UPDATE tenant_memberships SET status = 'ACTIVE', valid_from = ?
                    WHERE tenant_id = ? AND usuario_id = ?
                    """, Timestamp.from(now.plusSeconds(3600)), tenantId, secondUser);
            assertBothCountsExcludeSecondIdentity(now);
            assertThatThrownBy(() -> memberships.update(firstUser, null, false, null))
                    .isInstanceOf(OperacionNoPermitidaException.class);
            assertThat(memberships.update(secondUser, null, false, null).getStatus())
                    .isEqualTo(TenantMembershipStatus.SUSPENDED);
        }
    }

    private void assertBothCountsExcludeSecondIdentity(Instant now) {
        assertThat(membershipRepository.countActiveAdministrators(tenantId, now)).isOne();
        assertThat(platformRepository.activeAdministrators(tenantId, firstMembership, now)).isZero();
    }

    private Object suspendAfter(CountDownLatch start, long userId) throws Exception {
        if (!start.await(10, TimeUnit.SECONDS)) throw new IllegalStateException("Regression barrier timed out");
        try (TenantContext.Scope ignored = TenantContext.open(tenantId, null)) {
            try {
                memberships.update(userId, null, false, null);
                return true;
            } catch (OperacionNoPermitidaException denied) {
                return denied;
            }
        }
    }

    private long insertUser() {
        return jdbc.queryForObject("""
                INSERT INTO usuarios(nombre_usuario, contrasena, activo, auth_version, version)
                VALUES (?, 'synthetic-test-hash', TRUE, 0, 0) RETURNING id
                """, Long.class, "admin-regression-" + UUID.randomUUID());
    }

    private UUID insertMembership(long userId) {
        UUID id = UUID.randomUUID();
        jdbc.update("""
                INSERT INTO tenant_memberships(id, tenant_id, usuario_id, status, security_version)
                VALUES (?, ?, ?, 'ACTIVE', 0)
                """, id, tenantId, userId);
        jdbc.update("""
                INSERT INTO tenant_membership_roles(membership_id, tenant_id, role_id)
                VALUES (?, ?, ?)
                """, id, tenantId, roleId);
        return id;
    }
}
