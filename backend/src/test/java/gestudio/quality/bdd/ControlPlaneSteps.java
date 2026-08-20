package gestudio.quality.bdd;

import gestudio.dto.request.LoginRequest;
import gestudio.infra.errores.TratadorDeErrores.RecursoNoEncontradoException;
import gestudio.infra.seguridad.AutenticacionService;
import gestudio.platform.control.PlatformControlPlaneService;
import gestudio.platform.control.PlatformIdentityActivationService;
import gestudio.platform.security.PlatformPrincipal;
import gestudio.platform.security.PlatformStepUpRepository;
import gestudio.platform.security.PlatformStepUpService;
import gestudio.tenancy.TenantAccessService;
import io.cucumber.java.Before;
import io.cucumber.java.en.Given;
import io.cucumber.java.en.Then;
import io.cucumber.java.en.When;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.test.web.servlet.MockMvc;

import java.time.Clock;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import static gestudio.platform.control.PlatformControlPlaneService.TENANT_CREATE;
import static gestudio.platform.control.PlatformControlPlaneService.TENANT_STATUS;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.catchThrowable;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

public class ControlPlaneSteps {
    private static final String SCHOOL_NAME = "Escuela Danza Marcos Paz";
    private static final String ADMIN_PASSWORD = "Synthetic-Admin-2026!";

    @Autowired private PlatformControlPlaneService controlPlane;
    @Autowired private PlatformStepUpRepository stepUps;
    @Autowired private PlatformIdentityActivationService activations;
    @Autowired private TenantAccessService tenantAccess;
    @Autowired private AutenticacionService authentication;
    @Autowired private MockMvc mockMvc;
    @Autowired private Clock clock;
    @Autowired @Qualifier("platformJdbcTemplate") private JdbcTemplate jdbc;

    private String suffix;
    private String tenantCode;
    private String adminUsername;
    private PlatformPrincipal actor;
    private PlatformControlPlaneService.ProvisionedTenant provisioned;
    private PlatformControlPlaneService.ProvisionedTenant alpha;
    private PlatformControlPlaneService.ProvisionedTenant beta;
    private Throwable failure;
    private long rowsBeforeSuspension;
    private List<PlatformControlPlaneService.ProvisionedTenant> concurrentResults;

    @Before
    public void prepareScenario() {
        suffix = UUID.randomUUID().toString().substring(0, 8);
        tenantCode = "escuela-marcos-paz-" + suffix;
        adminUsername = "admin." + suffix;
        String actorUsername = "platform.bdd." + suffix;
        Long actorId = jdbc.queryForObject("""
                INSERT INTO usuarios(nombre_usuario, contrasena, rol_id, activo,
                                     auth_version, password_changed_at, version)
                VALUES (?, '$2a$10$synthetic.unavailable.hash.for.bdd.only', NULL, TRUE,
                        0, CURRENT_TIMESTAMP, 0)
                RETURNING id
                """, Long.class, actorUsername);
        if (actorId == null) {
            throw new IllegalStateException("No se pudo crear el actor BDD");
        }
        Instant now = clock.instant();
        jdbc.update("""
                INSERT INTO platform_admins(usuario_id, active, granted_at,
                                            granted_by_usuario_id, revoked_at,
                                            security_version, mfa_required, updated_at)
                VALUES (?, TRUE, ?, NULL, NULL, 0, TRUE, ?)
                """, actorId, now, now);
        actor = new PlatformPrincipal(actorId, actorUsername, 0, 0,
                UUID.randomUUID(), now);
    }

    @Given("un SUPERADMIN de plataforma autenticado y autorizado")
    public void platformSuperadmin() {
        assertThat(actor).isNotNull();
    }

    @Given("no existe el tenant Escuela Danza Marcos Paz")
    public void tenantDoesNotExist() {
        assertThat(count("SELECT count(*) FROM tenants WHERE code = ?", tenantCode)).isZero();
    }

    @When("crea Escuela Danza Marcos Paz con administradora inicial")
    public void createSchool() {
        provisioned = createTenant(SCHOOL_NAME, tenantCode, adminUsername,
                "create-" + suffix);
    }

    @Then("existe exactamente un tenant activo para la escuela")
    public void activeTenantExists() {
        assertThat(count("SELECT count(*) FROM tenants WHERE code = ? AND status = 'ACTIVE'", tenantCode))
                .isOne();
        assertThat(provisioned.tenant().status()).isEqualTo("ACTIVE");
    }

    @Then("no se crean datos demo")
    public void noDemoData() {
        assertThat(count("""
                SELECT (SELECT count(*) FROM alumnos)
                     + (SELECT count(*) FROM disciplinas)
                     + (SELECT count(*) FROM inscripciones)
                     + (SELECT count(*) FROM mensualidades)
                     + (SELECT count(*) FROM pagos)
                     + (SELECT count(*) FROM movimientos_caja)
                """)).isZero();
    }

    @Then("se registra auditoría de creación")
    public void creationAuditExists() {
        assertThat(count("""
                SELECT count(*) FROM platform_audit_events
                WHERE action = 'TENANT_CREATE' AND target_id = ? AND result = 'SUCCESS'
                """, provisioned.tenant().id().toString())).isOne();
    }

    @Given("un administrador tenant sin capacidad de plataforma")
    public void tenantAdmin() {
        assertThat(actor).isNotNull();
    }

    @When("intenta crear Tenant Beta desde el endpoint de plataforma")
    public void tenantAdminAttemptsCreation() throws Exception {
        String payload = """
                {"code":"tenant-beta-%s","name":"Tenant Beta",
                 "initialAdmin":{"mode":"NEW","nombreUsuario":"beta.%s"}}
                """.formatted(suffix, suffix);
        mockMvc.perform(post("/api/platform/tenants")
                        .with(user("tenant-admin").roles("ADMINISTRADOR"))
                        .header("Idempotency-Key", "denied-" + suffix)
                        .header("X-Step-Up-Token", "synthetic-proof")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(payload))
                .andExpect(status().isForbidden());
    }

    @Then("Tenant Beta no existe")
    public void betaDoesNotExist() {
        assertThat(count("SELECT count(*) FROM tenants WHERE code = ?", "tenant-beta-" + suffix)).isZero();
    }

    @Given("existe Escuela Danza Marcos Paz con administradora pendiente")
    public void schoolWithPendingAdmin() {
        provisioned = createTenant(SCHOOL_NAME, tenantCode, adminUsername,
                "pending-" + suffix);
        assertThat(provisioned.activation()).isNotNull();
    }

    @When("la administradora activa su identidad e inicia sesión")
    public void activateAndLogin() {
        activations.activate(provisioned.activation().token(), ADMIN_PASSWORD,
                null, null, UUID.randomUUID());
        var result = authentication.login(
                new LoginRequest(adminUsername, ADMIN_PASSWORD, provisioned.tenant().id()),
                "bdd-user-agent", "192.0.2.10");
        assertThat(result.selectionRequired()).isFalse();
        assertThat(result.usuario().tenantActivo().id()).isEqualTo(provisioned.tenant().id());
    }

    @Then("existe una única membership administradora")
    public void uniqueAdminMembership() {
        assertThat(count("""
                SELECT count(*) FROM tenant_memberships m
                JOIN tenant_membership_roles mr ON mr.membership_id = m.id
                JOIN roles r ON r.id = mr.role_id
                WHERE m.usuario_id = ? AND m.tenant_id = ? AND r.codigo = 'ADMINISTRADOR'
                """, provisioned.initialAdmin().userId(), provisioned.tenant().id())).isOne();
    }

    @Then("sólo administra su tenant")
    public void onlyOwnTenant() {
        var other = createTenant("Tenant aislado", "tenant-isolated-" + suffix,
                "isolated." + suffix, "isolated-" + suffix);
        assertThat(tenantAccess.findActiveAccess(
                provisioned.initialAdmin().userId(), provisioned.tenant().id())).isPresent();
        assertThat(tenantAccess.findActiveAccess(
                provisioned.initialAdmin().userId(), other.tenant().id())).isEmpty();
    }

    @Given("existen Tenant Alpha y Tenant Beta")
    public void alphaAndBetaExist() {
        alpha = createTenant("Tenant Alpha", "tenant-alpha-" + suffix,
                "alpha." + suffix, "alpha-" + suffix);
        beta = createTenant("Tenant Beta", "tenant-beta-" + suffix,
                "beta." + suffix, "beta-" + suffix);
    }

    @When("se combina la membership de Alpha con el ID de Beta")
    public void crossTenantManipulation() {
        failure = catchThrowable(() -> controlPlane.updateMembershipRoles(
                beta.tenant().id(), alpha.initialAdmin().id(), List.of("ADMINISTRADOR"),
                alpha.initialAdmin().version(), actor, "cross-" + suffix,
                "proof-must-not-be-reached", UUID.randomUUID()));
    }

    @Then("la operación cross-tenant es denegada sin filtrar datos de Beta")
    public void crossTenantDenied() {
        assertThat(failure).isInstanceOf(RecursoNoEncontradoException.class)
                .hasMessage("Membership no encontrada");
        assertThat(failure.getMessage()).doesNotContain(beta.tenant().id().toString());
        assertThat(count("""
                SELECT count(*) FROM tenant_memberships
                WHERE tenant_id = ? AND id = ?
                """, beta.tenant().id(), alpha.initialAdmin().id())).isZero();
    }

    @Given("un tenant activo con una administradora habilitada")
    public void activeTenantWithAdmin() {
        provisioned = createTenant(SCHOOL_NAME, tenantCode, adminUsername,
                "suspend-source-" + suffix);
        activations.activate(provisioned.activation().token(), ADMIN_PASSWORD,
                null, null, UUID.randomUUID());
        assertThat(tenantAccess.findActiveAccess(
                provisioned.initialAdmin().userId(), provisioned.tenant().id())).isPresent();
        rowsBeforeSuspension = count(
                "SELECT count(*) FROM tenant_memberships WHERE tenant_id = ?",
                provisioned.tenant().id());
    }

    @When("SUPERADMIN suspende el tenant")
    public void suspendTenant() {
        String key = "suspend-" + suffix;
        String proof = verifiedProof(TENANT_STATUS, "TENANT",
                provisioned.tenant().id().toString(), key);
        var suspended = controlPlane.changeTenantStatus(
                provisioned.tenant().id(), "SUSPENDED", provisioned.tenant().version(),
                "Suspensión BDD controlada", actor, key, proof, UUID.randomUUID());
        assertThat(suspended.status()).isEqualTo("SUSPENDED");
    }

    @Then("la autenticación tenant es rechazada y los datos permanecen intactos")
    public void suspendedTenantPolicy() {
        assertThat(tenantAccess.findActiveAccess(
                provisioned.initialAdmin().userId(), provisioned.tenant().id())).isEmpty();
        assertThat(catchThrowable(() -> authentication.login(
                new LoginRequest(adminUsername, ADMIN_PASSWORD, provisioned.tenant().id()),
                "bdd-user-agent", "192.0.2.11")))
                .isInstanceOf(BadCredentialsException.class);
        assertThat(count("SELECT count(*) FROM tenant_memberships WHERE tenant_id = ?",
                provisioned.tenant().id())).isEqualTo(rowsBeforeSuspension);
    }

    @Given("dos requests equivalentes para una misma escuela")
    public void equivalentRequests() {
        assertThat(count("SELECT count(*) FROM tenants WHERE code = ?", tenantCode)).isZero();
    }

    @When("ambos provisionamientos se ejecutan concurrentemente")
    public void concurrentProvisioning() throws Exception {
        String key = "concurrent-" + suffix;
        String proof = verifiedProof(TENANT_CREATE, "TENANT", tenantCode, key);
        CountDownLatch start = new CountDownLatch(1);
        ExecutorService executor = Executors.newFixedThreadPool(2);
        try {
            Future<PlatformControlPlaneService.ProvisionedTenant> first = executor.submit(() -> {
                start.await(5, TimeUnit.SECONDS);
                return controlPlane.createTenant(command(), actor, key, proof, UUID.randomUUID());
            });
            Future<PlatformControlPlaneService.ProvisionedTenant> second = executor.submit(() -> {
                start.await(5, TimeUnit.SECONDS);
                return controlPlane.createTenant(command(), actor, key, proof, UUID.randomUUID());
            });
            start.countDown();
            concurrentResults = List.of(first.get(30, TimeUnit.SECONDS),
                    second.get(30, TimeUnit.SECONDS));
        } finally {
            executor.shutdownNow();
            assertThat(executor.awaitTermination(5, TimeUnit.SECONDS)).isTrue();
        }
    }

    @Then("existe una única entidad final consistente")
    public void oneConsistentEntity() {
        assertThat(count("SELECT count(*) FROM tenants WHERE code = ?", tenantCode)).isOne();
        assertThat(count("""
                SELECT count(*) FROM tenant_memberships m
                JOIN tenants t ON t.id = m.tenant_id WHERE t.code = ?
                """, tenantCode)).isOne();
        assertThat(concurrentResults).hasSize(2);
        assertThat(concurrentResults.stream().filter(PlatformControlPlaneService.ProvisionedTenant::replayed))
                .hasSize(1);
        assertThat(concurrentResults).extracting(value -> value.tenant().id())
                .containsOnly(concurrentResults.getFirst().tenant().id());
    }

    private PlatformControlPlaneService.ProvisionedTenant createTenant(
            String name, String code, String username, String key) {
        String proof = verifiedProof(TENANT_CREATE, "TENANT", code, key);
        return controlPlane.createTenant(new PlatformControlPlaneService.CreateTenant(
                        code, name,
                        new PlatformControlPlaneService.IdentityRequest("NEW", null, username)),
                actor, key, proof, UUID.randomUUID());
    }

    private PlatformControlPlaneService.CreateTenant command() {
        return new PlatformControlPlaneService.CreateTenant(
                tenantCode, SCHOOL_NAME,
                new PlatformControlPlaneService.IdentityRequest("NEW", null, adminUsername));
    }

    private String verifiedProof(String action, String targetType, String targetId, String key) {
        Instant now = clock.instant();
        String proof = "proof-" + UUID.randomUUID();
        var challenge = new PlatformStepUpRepository.Challenge(
                UUID.randomUUID(), actor.userId(), actor.sessionId(), action, targetType, targetId,
                key, UUID.randomUUID(), now, now.plusSeconds(300), null, null, null);
        var stored = stepUps.createOrFind(challenge);
        assertThat(stepUps.verify(stored.id(), PlatformStepUpService.hash(proof), now)).isTrue();
        return proof;
    }

    private long count(String sql, Object... arguments) {
        Long value = jdbc.queryForObject(sql, Long.class, arguments);
        return value == null ? 0 : value;
    }
}
