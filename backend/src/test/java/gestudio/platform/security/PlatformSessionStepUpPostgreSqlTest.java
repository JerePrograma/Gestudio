package gestudio.platform.security;

import gestudio.infra.persistencia.PostgreSqlIntegrationTest;
import gestudio.infra.seguridad.RefreshTokenReuseException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.BadCredentialsException;
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
class PlatformSessionStepUpPostgreSqlTest extends PostgreSqlIntegrationTest {
    private static final byte[] TOTP_SECRET =
            "12345678901234567890".getBytes(StandardCharsets.US_ASCII);
    private static final String TOTP_SECRET_BASE32 = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ";

    @Autowired @Qualifier("platformJdbcTemplate") private JdbcTemplate jdbc;
    @Autowired private PlatformIdentityRepository identities;
    @Autowired private PlatformMfaService mfa;
    @Autowired private PlatformRefreshSessionService sessions;
    @Autowired private PlatformStepUpService stepUp;
    @Autowired private PasswordEncoder passwordEncoder;
    @Autowired private Clock clock;

    private long userId;
    private PlatformIdentityRepository.Identity identity;
    private PlatformMfaService.ProvisionedMfa provisioned;

    @BeforeEach
    void createMfaProtectedPlatformIdentity() {
        Long inserted = jdbc.queryForObject("""
                INSERT INTO usuarios(nombre_usuario, contrasena, rol_id, activo)
                VALUES (?, ?, NULL, TRUE) RETURNING id
                """, Long.class, "platform-security-" + UUID.randomUUID(),
                passwordEncoder.encode("platform-password"));
        if (inserted == null) throw new IllegalStateException("Usuario de prueba sin id");
        userId = inserted;
        jdbc.update("""
                INSERT INTO platform_admins(usuario_id, active, granted_at)
                VALUES (?, TRUE, ?)
                """, userId, Timestamp.from(clock.instant()));
        provisioned = provisionWithPreviousCounter();
        identity = identities.findActiveById(userId).orElseThrow();
    }

    @Test
    void refreshRotationPersistsReplacementAndReuseRevokesWholeFamily() {
        PlatformRefreshSessionService.Emission first = sessions.start(
                identity, clock.instant(), "Browser/1.0", "192.0.2.10");
        PlatformRefreshSessionService.Emission second = sessions.rotate(
                first.refreshToken(), "Browser/2.0", "192.0.2.11");

        UUID familyId = jdbc.queryForObject(
                "SELECT family_id FROM platform_refresh_sessions WHERE id=?",
                UUID.class, first.sessionId());
        assertThat(familyId).isNotNull();
        assertThat(jdbc.queryForObject("""
                SELECT count(*) FROM platform_refresh_sessions
                WHERE family_id=? AND usuario_id=?
                """, Long.class, familyId, userId)).isEqualTo(2L);
        assertThat(jdbc.queryForObject("""
                SELECT used_at IS NOT NULL AND replaced_by_id=?
                FROM platform_refresh_sessions WHERE id=?
                """, Boolean.class, second.sessionId(), first.sessionId())).isTrue();
        assertThat(jdbc.queryForObject("""
                SELECT family_expires_at=(
                    SELECT family_expires_at FROM platform_refresh_sessions WHERE id=?
                ) FROM platform_refresh_sessions WHERE id=?
                """, Boolean.class, first.sessionId(), second.sessionId())).isTrue();

        assertThatThrownBy(() -> sessions.rotate(first.refreshToken(), null, null))
                .isInstanceOf(RefreshTokenReuseException.class);
        assertThat(jdbc.queryForObject("""
                SELECT count(*) FROM platform_refresh_sessions
                WHERE family_id=? AND revoked_at IS NOT NULL AND revoke_reason='REUSE_DETECTED'
                """, Long.class, familyId)).isEqualTo(2L);
    }

    @Test
    void stepUpProofIsPurposeBoundExpiresAndCanBeConsumedOnlyOnce() {
        PlatformRefreshSessionService.Emission session = sessions.start(
                identity, clock.instant(), null, null);
        PlatformPrincipal principal = new PlatformPrincipal(userId, identity.username(),
                identity.authVersion(), identity.platformSecurityVersion(), session.sessionId(),
                session.mfaAt());
        String key = "tenant-status-" + UUID.randomUUID();
        UUID correlation = UUID.randomUUID();

        PlatformStepUpService.ChallengeEmission challenge = stepUp.challenge(principal,
                "TENANT_STATUS", "TENANT", "tenant-42", key, correlation);
        PlatformStepUpService.ProofEmission proof = stepUp.verify(
                principal, challenge.challengeId(), currentTotp());

        assertThat(jdbc.queryForObject("""
                SELECT proof_hash=? AND verified_at IS NOT NULL AND consumed_at IS NULL
                FROM platform_step_up_challenges WHERE id=?
                """, Boolean.class, PlatformStepUpService.hash(proof.stepUpToken()),
                challenge.challengeId())).isTrue();
        assertThatThrownBy(() -> stepUp.requireAndConsume(principal, proof.stepUpToken(),
                "TENANT_UPDATE", "TENANT", "tenant-42", key))
                .isInstanceOf(PlatformPreconditionRequiredException.class);
        stepUp.requireAndConsume(principal, proof.stepUpToken(),
                "TENANT_STATUS", "TENANT", "tenant-42", key);
        assertThatThrownBy(() -> stepUp.requireAndConsume(principal, proof.stepUpToken(),
                "TENANT_STATUS", "TENANT", "tenant-42", key))
                .isInstanceOf(PlatformPreconditionRequiredException.class);

        String expiredKey = "expired-" + UUID.randomUUID();
        var expired = stepUp.challenge(principal, "TENANT_UPDATE", "TENANT",
                "tenant-42", expiredKey, correlation);
        Instant now = clock.instant();
        jdbc.update("""
                UPDATE platform_step_up_challenges
                SET issued_at=?, expires_at=? WHERE id=?
                """, Timestamp.from(now.minusSeconds(120)),
                Timestamp.from(now.minusSeconds(60)), expired.challengeId());
        assertThatThrownBy(() -> stepUp.verify(principal, expired.challengeId(), currentTotp()))
                .isInstanceOf(PlatformPreconditionRequiredException.class);
    }

    @Test
    void recoveryCodeIsOneUseAndMfaFailuresPersistUntilDatabaseBackedBlock() {
        String recovery = provisioned.recoveryCodes().getFirst();

        Instant beforeVerification = clock.instant();
        Instant verifiedAt = mfa.verifyRecovery(userId, recovery.toLowerCase());
        Instant afterVerification = clock.instant();
        assertThat(verifiedAt).isBetween(beforeVerification, afterVerification);
        assertThatThrownBy(() -> mfa.verifyRecovery(userId, recovery))
                .isInstanceOf(BadCredentialsException.class);

        for (int attempt = 1; attempt < 5; attempt++) {
            assertThatThrownBy(() -> mfa.verifyTotp(userId, "000000"))
                    .isInstanceOf(BadCredentialsException.class);
        }
        assertThatThrownBy(() -> mfa.verifyTotp(userId, "000000"))
                .isInstanceOf(PlatformMfaRateLimitedException.class)
                .satisfies(error -> assertThat(((PlatformMfaRateLimitedException) error).retryAfter())
                        .isEqualTo(java.time.Duration.ofMinutes(15)));
        assertThat(jdbc.queryForObject("""
                SELECT failed_attempts=5 AND blocked_until IS NOT NULL
                FROM platform_mfa_credentials
                WHERE usuario_id=? AND revoked_at IS NULL
                """, Boolean.class, userId)).isTrue();
        assertThatThrownBy(() -> mfa.verifyTotp(userId, currentTotp()))
                .isInstanceOf(PlatformMfaRateLimitedException.class);
    }

    private PlatformMfaService.ProvisionedMfa provisionWithPreviousCounter() {
        for (int retry = 0; retry < 2; retry++) {
            long current = clock.instant().getEpochSecond() / TotpService.STEP_SECONDS;
            try {
                return mfa.provisionInitial(userId, TOTP_SECRET_BASE32,
                        TotpService.code(TOTP_SECRET, current - 1));
            } catch (BadCredentialsException boundaryCrossed) {
                if (retry == 1) throw boundaryCrossed;
            }
        }
        throw new IllegalStateException("No se pudo preparar TOTP de prueba");
    }

    private String currentTotp() {
        long current = clock.instant().getEpochSecond() / TotpService.STEP_SECONDS;
        return TotpService.code(TOTP_SECRET, current);
    }
}
