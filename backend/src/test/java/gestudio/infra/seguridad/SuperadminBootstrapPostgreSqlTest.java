package gestudio.infra.seguridad;

import gestudio.infra.persistencia.PostgreSqlIntegrationTest;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.Timeout;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.boot.test.context.SpringBootTest;

import java.nio.charset.StandardCharsets;
import java.nio.ByteBuffer;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

@SpringBootTest
class SuperadminBootstrapPostgreSqlTest extends PostgreSqlIntegrationTest {
    private static final String PASSWORD = "clave-superadmin-segura";
    private static final String TOTP_SECRET = "JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP";
    private static final String MFA_KEY =
            java.util.Base64.getEncoder().encodeToString("12345678901234567890123456789012"
                    .getBytes(StandardCharsets.US_ASCII));

    @DynamicPropertySource
    static void platformProperties(DynamicPropertyRegistry registry) {
        registry.add("app.platform-datasource.url", POSTGRESQL::getJdbcUrl);
        registry.add("app.platform-datasource.username", POSTGRESQL::getUsername);
        registry.add("app.platform-datasource.password", POSTGRESQL::getPassword);
        registry.add("app.platform-security.mfa-encryption-key", () -> MFA_KEY);
        registry.add("app.platform-security.refresh-cookie.secure", () -> false);
    }

    @Autowired private SuperadminBootstrapService bootstrap;
    @Autowired private JdbcTemplate jdbc;
    @Autowired private PasswordEncoder passwordEncoder;

    @Test
    @Timeout(40)
    void bootstrapEsPlatformOnlyMfaObligatorioAtomicoEIdempotente() throws Exception {
        String username = "bootstrap-platform-" + UUID.randomUUID();

        assertThatThrownBy(() -> bootstrap.bootstrap(username, "corta", TOTP_SECRET,
                currentCode(), ignored -> { }))
                .isInstanceOf(IllegalStateException.class).hasMessageContaining("16 y 72");
        assertThat(claims()).isZero();

        assertThatThrownBy(() -> bootstrap.bootstrap(username, PASSWORD, TOTP_SECRET,
                "000000", ignored -> { }))
                .isInstanceOf(RuntimeException.class);
        assertThat(claims()).isZero();
        assertThat(platformAdmins()).isZero();

        assertThatThrownBy(() -> bootstrap.bootstrap(username, PASSWORD, TOTP_SECRET,
                currentCode(), ignored -> { throw new IllegalStateException("sink seguro falló"); }))
                .isInstanceOf(IllegalStateException.class).hasMessageContaining("sink seguro");
        assertThat(claims()).isZero();
        assertThat(jdbc.queryForObject("SELECT count(*) FROM usuarios WHERE nombre_usuario=?",
                Integer.class, username)).isZero();

        CountDownLatch start = new CountDownLatch(1);
        ExecutorService executor = Executors.newFixedThreadPool(2);
        Future<Object> first = executor.submit(() -> runBootstrap(start, username));
        Future<Object> second = executor.submit(() -> runBootstrap(start, username + "-other"));
        List<Object> results;
        try {
            start.countDown();
            results = List.of(first.get(20, TimeUnit.SECONDS), second.get(20, TimeUnit.SECONDS));
        } finally {
            executor.shutdownNow();
            assertThat(executor.awaitTermination(5, TimeUnit.SECONDS)).isTrue();
        }

        assertThat(results.stream().filter(SuperadminBootstrapService.BootstrapResult.class::isInstance))
                .hasSize(1);
        assertThat(results.stream().filter(RuntimeException.class::isInstance)).hasSize(1);
        assertThat(claims()).isOne();
        assertThat(platformAdmins()).isOne();

        Long userId = jdbc.queryForObject("""
                SELECT b.usuario_id FROM bootstrap_ejecuciones b
                WHERE b.tipo='SUPERADMIN_INICIAL'
                """, Long.class);
        assertThat(userId).isNotNull();
        assertThat(jdbc.queryForObject("SELECT rol_id FROM usuarios WHERE id=?",
                Long.class, userId)).isNull();
        assertThat(jdbc.queryForObject("SELECT count(*) FROM tenant_memberships WHERE usuario_id=?",
                Integer.class, userId)).isZero();
        assertThat(jdbc.queryForObject("""
                SELECT u.password_changed_at IS NOT NULL
                       AND pa.granted_at IS NOT NULL
                       AND pa.updated_at IS NOT NULL
                FROM usuarios u
                JOIN platform_admins pa ON pa.usuario_id=u.id
                WHERE u.id=?
                """, Boolean.class, userId)).isTrue();
        assertThat(jdbc.queryForObject("""
                SELECT count(*) FROM platform_mfa_credentials
                WHERE usuario_id=? AND verified_at IS NOT NULL AND revoked_at IS NULL
                """, Integer.class, userId)).isOne();
        assertThat(jdbc.queryForObject("""
                SELECT count(*) FROM platform_recovery_codes rc
                JOIN platform_mfa_credentials mc ON mc.id=rc.credential_id
                WHERE mc.usuario_id=? AND rc.used_at IS NULL
                """, Integer.class, userId)).isEqualTo(10);
        assertThat(jdbc.queryForObject("""
                SELECT count(*) FROM platform_audit_events
                WHERE action='PLATFORM_SUPERADMIN_BOOTSTRAP' AND actor_usuario_id=?
                """, Integer.class, userId)).isOne();

        String encoded = jdbc.queryForObject("SELECT contrasena FROM usuarios WHERE id=?",
                String.class, userId);
        assertThat(encoded).isNotEqualTo(PASSWORD);
        assertThat(passwordEncoder.matches(PASSWORD, encoded)).isTrue();

        assertThatThrownBy(() -> bootstrap.bootstrap("another", PASSWORD, TOTP_SECRET,
                currentCode(), ignored -> { }))
                .isInstanceOf(IllegalStateException.class).hasMessageContaining("ya fue ejecutado");
    }

    private Object runBootstrap(CountDownLatch start, String username) {
        try {
            start.await(5, TimeUnit.SECONDS);
            List<String> delivered = new ArrayList<>();
            var result = bootstrap.bootstrap(username, PASSWORD, TOTP_SECRET, currentCode(), delivered::addAll);
            assertThat(delivered).hasSize(10);
            return result;
        } catch (RuntimeException exception) {
            return exception;
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            return exception;
        }
    }

    private String currentCode() {
        byte[] half = "Hello!\u00de\u00ad\u00be\u00ef".getBytes(StandardCharsets.ISO_8859_1);
        byte[] secret = new byte[half.length * 2];
        System.arraycopy(half, 0, secret, 0, half.length);
        System.arraycopy(half, 0, secret, half.length, half.length);
        long counter = Math.floorDiv(Instant.now().getEpochSecond(), 30);
        try {
            Mac mac = Mac.getInstance("HmacSHA1");
            mac.init(new SecretKeySpec(secret, "HmacSHA1"));
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

    private int claims() {
        return jdbc.queryForObject("SELECT count(*) FROM bootstrap_ejecuciones WHERE tipo='SUPERADMIN_INICIAL'",
                Integer.class);
    }

    private int platformAdmins() {
        return jdbc.queryForObject("SELECT count(*) FROM platform_admins", Integer.class);
    }
}
