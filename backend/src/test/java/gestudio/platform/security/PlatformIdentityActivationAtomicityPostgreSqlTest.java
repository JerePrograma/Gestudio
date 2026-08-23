package gestudio.platform.security;

import gestudio.platform.control.PlatformIdentityActivationService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.testcontainers.postgresql.PostgreSQLContainer;

import java.nio.charset.StandardCharsets;
import java.sql.Timestamp;
import java.time.Clock;
import java.time.Instant;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

@SpringBootTest
@ActiveProfiles("test")
class PlatformIdentityActivationAtomicityPostgreSqlTest {
    private static final byte[] TOTP_SECRET =
            "12345678901234567890".getBytes(StandardCharsets.US_ASCII);
    private static final String TOTP_SECRET_BASE32 = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ";
    private static final String INITIAL_PASSWORD = "initial-platform-password";
    private static final String NEW_PASSWORD = "new-platform-password";

    private static final PostgreSQLContainer POSTGRESQL =
            new PostgreSQLContainer("postgres:15.18-alpine3.24")
                    .withDatabaseName("gestudio_activation_atomicity")
                    .withUsername("activation_atomicity")
                    .withPassword("activation_atomicity");

    static {
        POSTGRESQL.start();
    }

    @DynamicPropertySource
    static void postgresqlProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRESQL::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRESQL::getUsername);
        registry.add("spring.datasource.password", POSTGRESQL::getPassword);
        registry.add("spring.flyway.enabled", () -> true);
        registry.add("spring.flyway.baseline-on-migrate", () -> false);
        registry.add("spring.flyway.default-schema", () -> "public");
        registry.add("spring.flyway.schemas", () -> "public");
        registry.add("app.platform-datasource.url", POSTGRESQL::getJdbcUrl);
        registry.add("app.platform-datasource.username", POSTGRESQL::getUsername);
        registry.add("app.platform-datasource.password", POSTGRESQL::getPassword);
    }

    @Autowired @Qualifier("platformJdbcTemplate") private JdbcTemplate jdbc;
    @Autowired private PlatformIdentityActivationService activation;
    @Autowired private PasswordEncoder passwordEncoder;
    @Autowired private Clock clock;

    private long creatorId;

    @BeforeEach
    void createPlatformActor() {
        creatorId = insertUser("atomicity-creator-" + UUID.randomUUID(), true);
        jdbc.update("""
                INSERT INTO platform_admins(usuario_id, active, granted_at)
                VALUES (?, TRUE, ?)
                """, creatorId, Timestamp.from(clock.instant()));
    }

    @Test
    void failureAfterMfaProvisioningRollsBackEverythingAndLeavesTokenReusable() {
        assertThat(TransactionSynchronizationManager.isActualTransactionActive()).isFalse();
        long targetId = insertUser("atomicity-target-" + UUID.randomUUID(), false);
        Timestamp now = Timestamp.from(clock.instant());
        jdbc.update("""
                INSERT INTO platform_admins(
                    usuario_id, active, granted_at, granted_by_usuario_id, revoked_at,
                    security_version, updated_at)
                VALUES (?, FALSE, ?, ?, ?, ?, ?)
                """, targetId, now, creatorId, now, Long.MAX_VALUE, now);
        String rawToken = insertActivation(targetId);

        assertThatThrownBy(() -> activation.activate(
                rawToken, NEW_PASSWORD, TOTP_SECRET_BASE32, currentTotp(), UUID.randomUUID()))
                .isInstanceOf(DataIntegrityViolationException.class)
                .hasMessageContaining("out of range");

        assertThat(TransactionSynchronizationManager.isActualTransactionActive()).isFalse();
        assertRolledBack(targetId);

        jdbc.update("UPDATE platform_admins SET security_version=0 WHERE usuario_id=?", targetId);
        UUID correlationId = UUID.randomUUID();
        PlatformIdentityActivationService.ActivationResult result = activation.activate(
                rawToken, NEW_PASSWORD, TOTP_SECRET_BASE32, currentTotp(), correlationId);

        assertThat(result.recoveryCodes()).hasSize(10).doesNotHaveDuplicates();
        assertThat(jdbc.queryForObject(
                "SELECT consumed_at IS NOT NULL FROM platform_identity_activations WHERE usuario_id=?",
                Boolean.class, targetId)).isTrue();
        assertThat(jdbc.queryForObject(
                "SELECT count(*) FROM platform_mfa_credentials WHERE usuario_id=? AND revoked_at IS NULL",
                Long.class, targetId)).isOne();
        assertThat(jdbc.queryForObject(
                "SELECT secret_ciphertext FROM platform_mfa_credentials WHERE usuario_id=?",
                byte[].class, targetId)).isNotEqualTo(TOTP_SECRET);
        assertThat(jdbc.queryForObject("""
                SELECT count(*) FROM platform_recovery_codes rc
                JOIN platform_mfa_credentials mc ON mc.id=rc.credential_id
                WHERE mc.usuario_id=? AND rc.used_at IS NULL
                """, Long.class, targetId)).isEqualTo(10L);
        assertThat(jdbc.queryForObject(
                "SELECT activo FROM usuarios WHERE id=?", Boolean.class, targetId)).isTrue();
        assertThat(passwordEncoder.matches(NEW_PASSWORD, jdbc.queryForObject(
                "SELECT contrasena FROM usuarios WHERE id=?", String.class, targetId))).isTrue();
        assertThat(jdbc.queryForObject(
                "SELECT auth_version FROM usuarios WHERE id=?", Long.class, targetId)).isOne();
        assertThat(jdbc.queryForObject(
                "SELECT security_version FROM platform_admins WHERE usuario_id=?",
                Long.class, targetId)).isOne();
        assertThat(jdbc.queryForObject(
                "SELECT active AND revoked_at IS NULL FROM platform_admins WHERE usuario_id=?",
                Boolean.class, targetId)).isTrue();
        assertThat(jdbc.queryForObject("""
                SELECT count(*) FROM platform_audit_events
                WHERE actor_usuario_id=? AND action='PLATFORM_MFA_ENROLLED'
                  AND correlation_id=? AND result='SUCCESS'
                """, Long.class, targetId, correlationId)).isOne();
    }

    private void assertRolledBack(long targetId) {
        assertThat(jdbc.queryForObject(
                "SELECT activo FROM usuarios WHERE id=?", Boolean.class, targetId)).isFalse();
        assertThat(passwordEncoder.matches(INITIAL_PASSWORD, jdbc.queryForObject(
                "SELECT contrasena FROM usuarios WHERE id=?", String.class, targetId))).isTrue();
        assertThat(jdbc.queryForObject(
                "SELECT auth_version FROM usuarios WHERE id=?", Long.class, targetId)).isZero();
        assertThat(jdbc.queryForObject(
                "SELECT version FROM usuarios WHERE id=?", Long.class, targetId)).isZero();
        assertThat(jdbc.queryForObject(
                "SELECT security_version FROM platform_admins WHERE usuario_id=?",
                Long.class, targetId)).isEqualTo(Long.MAX_VALUE);
        assertThat(jdbc.queryForObject(
                "SELECT NOT active AND revoked_at IS NOT NULL FROM platform_admins WHERE usuario_id=?",
                Boolean.class, targetId)).isTrue();
        assertThat(jdbc.queryForObject(
                "SELECT count(*) FROM platform_mfa_credentials WHERE usuario_id=?",
                Long.class, targetId)).isZero();
        assertThat(jdbc.queryForObject("""
                SELECT count(*) FROM platform_recovery_codes rc
                JOIN platform_mfa_credentials mc ON mc.id=rc.credential_id
                WHERE mc.usuario_id=?
                """, Long.class, targetId)).isZero();
        assertThat(jdbc.queryForObject(
                "SELECT consumed_at IS NULL FROM platform_identity_activations WHERE usuario_id=?",
                Boolean.class, targetId)).isTrue();
        assertThat(jdbc.queryForObject(
                "SELECT count(*) FROM platform_audit_events WHERE actor_usuario_id=?",
                Long.class, targetId)).isZero();
    }

    private long insertUser(String username, boolean active) {
        Long id = jdbc.queryForObject("""
                INSERT INTO usuarios(nombre_usuario, contrasena, rol_id, activo)
                VALUES (?, ?, NULL, ?)
                RETURNING id
                """, Long.class, username, passwordEncoder.encode(INITIAL_PASSWORD), active);
        if (id == null) throw new IllegalStateException("Usuario de prueba sin id");
        return id;
    }

    private String insertActivation(long userId) {
        String raw = "activation-" + UUID.randomUUID();
        Instant now = clock.instant();
        jdbc.update("""
                INSERT INTO platform_identity_activations(
                    id, usuario_id, purpose, token_hash, issued_at, expires_at,
                    created_by_usuario_id)
                VALUES (?, ?, 'PLATFORM_MFA_RESET', ?, ?, ?, ?)
                """, UUID.randomUUID(), userId, PlatformStepUpService.hash(raw),
                Timestamp.from(now.minusSeconds(1)), Timestamp.from(now.plusSeconds(600)), creatorId);
        return raw;
    }

    private String currentTotp() {
        return TotpService.code(TOTP_SECRET,
                clock.instant().getEpochSecond() / TotpService.STEP_SECONDS);
    }
}
