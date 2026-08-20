package gestudio.platform.security;

import gestudio.infra.persistencia.PostgreSqlIntegrationTest;
import gestudio.infra.seguridad.InvalidTokenException;
import gestudio.platform.control.PlatformIdentityActivationService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.sql.Timestamp;
import java.time.Clock;
import java.time.Instant;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

@SpringBootTest
@Transactional(transactionManager = "platformTransactionManager")
class PlatformIdentityActivationPostgreSqlTest extends PostgreSqlIntegrationTest {
    private static final byte[] TOTP_SECRET =
            "12345678901234567890".getBytes(StandardCharsets.US_ASCII);
    private static final String TOTP_SECRET_BASE32 = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ";

    @Autowired @Qualifier("platformJdbcTemplate") private JdbcTemplate jdbc;
    @Autowired private PlatformIdentityActivationService activation;
    @Autowired private PasswordEncoder passwordEncoder;
    @Autowired private Clock clock;

    private long creatorId;

    @BeforeEach
    void createPlatformActor() {
        creatorId = insertUser("activation-creator-" + UUID.randomUUID(), true);
        jdbc.update("""
                INSERT INTO platform_admins(usuario_id, active, granted_at)
                VALUES (?, TRUE, ?)
                """, creatorId, Timestamp.from(clock.instant()));
    }

    @Test
    void identityActivationSetsPasswordAndUserActiveWithoutCreatingPlatformMfa() {
        long targetId = insertUser("new-tenant-admin-" + UUID.randomUUID(), false);
        String rawToken = insertActivation(targetId, "IDENTITY_ACTIVATION", clock.instant().plusSeconds(600));
        UUID correlationId = UUID.randomUUID();

        PlatformIdentityActivationService.ActivationResult result = activation.activate(
                rawToken, "tenant-password-strong", null, null, correlationId);

        assertThat(result.recoveryCodes()).isEmpty();
        assertThat(jdbc.queryForObject("SELECT activo FROM usuarios WHERE id=?", Boolean.class, targetId))
                .isTrue();
        assertThat(passwordEncoder.matches("tenant-password-strong",
                jdbc.queryForObject("SELECT contrasena FROM usuarios WHERE id=?", String.class, targetId)))
                .isTrue();
        assertThat(jdbc.queryForObject("SELECT auth_version FROM usuarios WHERE id=?", Long.class, targetId))
                .isEqualTo(1L);
        assertThat(jdbc.queryForObject(
                "SELECT count(*) FROM platform_mfa_credentials WHERE usuario_id=?", Long.class, targetId))
                .isZero();
        assertConsumedAndAudited(targetId, "PLATFORM_IDENTITY_ACTIVATED", correlationId);

        assertThatThrownBy(() -> activation.activate(
                rawToken, "another-tenant-password", null, null, UUID.randomUUID()))
                .isInstanceOf(InvalidTokenException.class);
    }

    @Test
    void mfaEnrollmentActivatesPlatformCapabilityAndReturnsRecoveryCodesOnlyOnce() {
        long targetId = insertPlatformTarget("mfa-enrollment-" + UUID.randomUUID(), true);
        String rawToken = insertActivation(
                targetId, "PLATFORM_MFA_ENROLLMENT", clock.instant().plusSeconds(600));
        UUID correlationId = UUID.randomUUID();

        PlatformIdentityActivationService.ActivationResult result = activation.activate(
                rawToken, null, TOTP_SECRET_BASE32, currentTotp(), correlationId);

        assertThat(result.recoveryCodes()).hasSize(10).doesNotHaveDuplicates()
                .allMatch(code -> code.matches("[A-Z2-7]{8}(?:-[A-Z2-7]{8}){2}-[A-Z2-7]{2}"));
        assertThat(jdbc.queryForObject(
                "SELECT active FROM platform_admins WHERE usuario_id=?", Boolean.class, targetId)).isTrue();
        assertThat(jdbc.queryForObject(
                "SELECT security_version FROM platform_admins WHERE usuario_id=?", Long.class, targetId))
                .isEqualTo(1L);
        assertThat(jdbc.queryForObject("""
                SELECT count(*) FROM platform_mfa_credentials
                WHERE usuario_id=? AND verified_at IS NOT NULL AND revoked_at IS NULL
                """, Long.class, targetId)).isEqualTo(1L);
        assertThat(jdbc.queryForObject("""
                SELECT count(*) FROM platform_recovery_codes rc
                JOIN platform_mfa_credentials mc ON mc.id=rc.credential_id
                WHERE mc.usuario_id=? AND rc.used_at IS NULL
                """, Long.class, targetId)).isEqualTo(10L);
        assertConsumedAndAudited(targetId, "PLATFORM_MFA_ENROLLED", correlationId);

        assertThatThrownBy(() -> activation.activate(
                rawToken, null, TOTP_SECRET_BASE32, currentTotp(), UUID.randomUUID()))
                .isInstanceOf(InvalidTokenException.class);
    }

    @Test
    void mfaResetCanAtomicallyReplacePasswordAndReactivateIdentity() {
        long targetId = insertPlatformTarget("mfa-reset-" + UUID.randomUUID(), false);
        String rawToken = insertActivation(
                targetId, "PLATFORM_MFA_RESET", clock.instant().plusSeconds(600));

        PlatformIdentityActivationService.ActivationResult result = activation.activate(
                rawToken, "new-platform-password", TOTP_SECRET_BASE32, currentTotp(), UUID.randomUUID());

        assertThat(result.recoveryCodes()).hasSize(10);
        assertThat(jdbc.queryForObject("SELECT activo FROM usuarios WHERE id=?", Boolean.class, targetId))
                .isTrue();
        assertThat(passwordEncoder.matches("new-platform-password",
                jdbc.queryForObject("SELECT contrasena FROM usuarios WHERE id=?", String.class, targetId)))
                .isTrue();
        assertThat(jdbc.queryForObject(
                "SELECT active FROM platform_admins WHERE usuario_id=?", Boolean.class, targetId)).isTrue();
    }

    @Test
    void expiredActivationDoesNotConsumeTokenOrActivateCapability() {
        long targetId = insertPlatformTarget("mfa-expired-" + UUID.randomUUID(), true);
        String expired = insertActivation(
                targetId, "PLATFORM_MFA_ENROLLMENT", clock.instant().minusSeconds(1));

        assertThatThrownBy(() -> activation.activate(
                expired, null, TOTP_SECRET_BASE32, currentTotp(), UUID.randomUUID()))
                .isInstanceOf(InvalidTokenException.class);

        assertThat(jdbc.queryForObject(
                "SELECT consumed_at IS NULL FROM platform_identity_activations WHERE usuario_id=?",
                Boolean.class, targetId)).isTrue();
        assertThat(jdbc.queryForObject(
                "SELECT active FROM platform_admins WHERE usuario_id=?", Boolean.class, targetId)).isFalse();
        assertThat(jdbc.queryForObject(
                "SELECT count(*) FROM platform_mfa_credentials WHERE usuario_id=?", Long.class, targetId))
                .isZero();
    }

    @Test
    void wrongTotpDoesNotConsumeTokenOrActivateCapability() {
        long targetId = insertPlatformTarget("mfa-wrong-code-" + UUID.randomUUID(), true);
        String valid = insertActivation(
                targetId, "PLATFORM_MFA_ENROLLMENT", clock.instant().plusSeconds(600));

        assertThatThrownBy(() -> activation.activate(
                valid, null, TOTP_SECRET_BASE32, "000000", UUID.randomUUID()))
                .isInstanceOf(org.springframework.security.authentication.BadCredentialsException.class);

        assertThat(jdbc.queryForObject(
                "SELECT consumed_at IS NULL FROM platform_identity_activations WHERE usuario_id=?",
                Boolean.class, targetId)).isTrue();
        assertThat(jdbc.queryForObject(
                "SELECT active FROM platform_admins WHERE usuario_id=?", Boolean.class, targetId)).isFalse();
        assertThat(jdbc.queryForObject(
                "SELECT count(*) FROM platform_mfa_credentials WHERE usuario_id=?", Long.class, targetId))
                .isZero();
    }

    private long insertPlatformTarget(String username, boolean userActive) {
        long userId = insertUser(username, userActive);
        jdbc.update("""
                INSERT INTO platform_admins(usuario_id, active, granted_at, granted_by_usuario_id, revoked_at)
                VALUES (?, FALSE, ?, ?, ?)
                """, userId, Timestamp.from(clock.instant()), creatorId,
                Timestamp.from(clock.instant()));
        return userId;
    }

    private long insertUser(String username, boolean active) {
        Long id = jdbc.queryForObject("""
                INSERT INTO usuarios(nombre_usuario, contrasena, rol_id, activo)
                VALUES (?, ?, NULL, ?)
                RETURNING id
                """, Long.class, username, passwordEncoder.encode("initial-password"), active);
        if (id == null) throw new IllegalStateException("Usuario de prueba sin id");
        return id;
    }

    private String insertActivation(long userId, String purpose, Instant expiresAt) {
        String raw = "activation-" + UUID.randomUUID();
        Instant issuedAt = expiresAt.isAfter(clock.instant())
                ? clock.instant().minusSeconds(1) : expiresAt.minusSeconds(60);
        jdbc.update("""
                INSERT INTO platform_identity_activations(
                    id, usuario_id, purpose, token_hash, issued_at, expires_at, created_by_usuario_id)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """, UUID.randomUUID(), userId, purpose, PlatformStepUpService.hash(raw),
                Timestamp.from(issuedAt), Timestamp.from(expiresAt), creatorId);
        return raw;
    }

    private String currentTotp() {
        return TotpService.code(TOTP_SECRET,
                clock.instant().getEpochSecond() / TotpService.STEP_SECONDS);
    }

    private void assertConsumedAndAudited(long targetId, String action, UUID correlationId) {
        assertThat(jdbc.queryForObject("""
                SELECT consumed_at IS NOT NULL
                FROM platform_identity_activations WHERE usuario_id=?
                """, Boolean.class, targetId)).isTrue();
        assertThat(jdbc.queryForObject("""
                SELECT count(*) FROM platform_audit_events
                WHERE actor_usuario_id=? AND action=? AND target_id=?
                  AND correlation_id=? AND result='SUCCESS'
                """, Long.class, targetId, action, Long.toString(targetId), correlationId)).isEqualTo(1L);
    }
}
