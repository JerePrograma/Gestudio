package gestudio.servicios.pdfs;

import gestudio.infra.configuracion.AppProperties;
import gestudio.tenancy.TenantContext;
import gestudio.tenancy.TenantMetrics;
import gestudio.tenancy.TenantRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.FileAlreadyExistsException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.regex.Pattern;

@Component
@ConditionalOnProperty(name = "app.multitenancy.required", havingValue = "true", matchIfMissing = true)
public class ReceiptNamespaceMigrator implements ApplicationRunner {
    private static final Logger log = LoggerFactory.getLogger(ReceiptNamespaceMigrator.class);
    private static final Pattern LEGACY_KEY = Pattern.compile("recibo_[1-9][0-9]*\\.pdf");
    private static final int BATCH = 100;

    private final TenantRepository tenants;
    private final JdbcTemplate jdbc;
    private final AppProperties properties;
    private final TenantMetrics metrics;
    private final AtomicBoolean complete = new AtomicBoolean();
    private final AtomicBoolean healthy = new AtomicBoolean();

    public ReceiptNamespaceMigrator(TenantRepository tenants, JdbcTemplate jdbc,
                                    AppProperties properties, TenantMetrics metrics) {
        this.tenants = tenants;
        this.jdbc = jdbc;
        this.properties = properties;
        this.metrics = metrics;
    }

    @Override
    public void run(ApplicationArguments args) {
        boolean success = true;
        for (UUID tenantId : tenants.findAllIds()) {
            try (TenantContext.Scope ignored = TenantContext.open(tenantId, null)) {
                migrateTenant(tenantId);
            } catch (RuntimeException | IOException failure) {
                success = false;
                metrics.crossScopeBlocked("migrate", "receipt_file");
                log.error("receipt_namespace_migration result=failure type={}",
                        failure.getClass().getSimpleName());
            }
        }
        healthy.set(success);
        complete.set(true);
        log.info("receipt_namespace_migration result={}", success ? "success" : "failure");
    }

    public boolean isHealthy() {
        return complete.get() && healthy.get();
    }

    private void migrateTenant(UUID tenantId) throws IOException {
        Path root = properties.receiptsPath().toAbsolutePath().normalize();
        while (true) {
            List<LegacyReceipt> legacy = jdbc.query("""
                    SELECT id, storage_key
                      FROM recibos
                     WHERE storage_key IS NOT NULL
                       AND storage_key NOT LIKE ?
                     ORDER BY id
                     LIMIT ?
                    """, (rs, row) -> new LegacyReceipt(rs.getLong("id"), rs.getString("storage_key")),
                    tenantId + "/recibos/%", BATCH);
            if (legacy.isEmpty()) return;
            for (LegacyReceipt receipt : legacy) migrate(root, tenantId, receipt);
        }
    }

    private void migrate(Path root, UUID tenantId, LegacyReceipt receipt) throws IOException {
        if (!LEGACY_KEY.matcher(receipt.storageKey()).matches()) {
            throw new IOException("Legacy receipt key is not a basename");
        }
        String targetKey = tenantId + "/recibos/" + receipt.storageKey();
        Path source = ReciboPathResolver.resolveExistingFile(root, receipt.storageKey());
        Path target = root.resolve(targetKey).normalize();
        if (!target.startsWith(root)) throw new IOException("Invalid tenant receipt target");

        if (source == null && !Files.isRegularFile(target)) {
            throw new IOException("Referenced legacy receipt is missing");
        }
        if (source != null) copyOnce(source, target);

        int updated = jdbc.update("UPDATE recibos SET storage_key = ? WHERE id = ? AND storage_key = ?",
                targetKey, receipt.id(), receipt.storageKey());
        if (updated != 1) throw new IOException("Receipt key changed concurrently");
        if (source != null && !source.equals(target)) Files.deleteIfExists(source);
    }

    private static void copyOnce(Path source, Path target) throws IOException {
        Files.createDirectories(target.getParent());
        if (Files.exists(target)) {
            if (Files.mismatch(source, target) != -1) throw new IOException("Receipt namespace collision");
            return;
        }
        Path temporary = Files.createTempFile(target.getParent(), target.getFileName().toString(), ".tmp");
        try {
            Files.copy(source, temporary, StandardCopyOption.REPLACE_EXISTING);
            try {
                Files.move(temporary, target, StandardCopyOption.ATOMIC_MOVE);
            } catch (AtomicMoveNotSupportedException exception) {
                Files.move(temporary, target);
            } catch (FileAlreadyExistsException concurrent) {
                if (Files.mismatch(source, target) != -1) throw concurrent;
            }
        } finally {
            Files.deleteIfExists(temporary);
        }
    }

    private record LegacyReceipt(long id, String storageKey) {
    }
}
