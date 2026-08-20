package gestudio.infra.seguridad;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;

@Component
@ConditionalOnProperty(name = "app.bootstrap-superadmin.enabled", havingValue = "true")
public class SuperadminBootstrapRunner implements ApplicationRunner {
    private static final Logger log = LoggerFactory.getLogger(SuperadminBootstrapRunner.class);

    private final SuperadminBootstrapProperties properties;
    private final SuperadminBootstrapService service;

    public SuperadminBootstrapRunner(SuperadminBootstrapProperties properties,
                                     SuperadminBootstrapService service) {
        this.properties = properties;
        this.service = service;
    }

    @Override
    public void run(ApplicationArguments args) {
        var result = service.bootstrap(properties.username(), properties.password(),
                properties.totpSecret(), properties.totpCode(),
                codes -> writeRecoveryCodes(properties.recoveryCodesFile(), codes));
        log.warn("SUPERADMIN de plataforma inicial creado con id={}. Deshabilite el bootstrap antes de reiniciar.",
                result.userId());
    }

    private static void writeRecoveryCodes(String rawPath, java.util.List<String> recoveryCodes) {
        if (rawPath == null || rawPath.isBlank()) {
            throw new IllegalStateException("APP_BOOTSTRAP_PLATFORM_RECOVERY_CODES_FILE es obligatorio");
        }
        Path path = Path.of(rawPath).toAbsolutePath().normalize();
        try {
            Files.write(path, recoveryCodes, StandardCharsets.US_ASCII,
                    StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE);
            try {
                Files.setPosixFilePermissions(path, java.nio.file.attribute.PosixFilePermissions.fromString("rw-------"));
            } catch (UnsupportedOperationException ignored) {
                // Windows/containers without POSIX permissions rely on the isolated job filesystem.
            }
        } catch (IOException exception) {
            throw new IllegalStateException("No se pudo escribir el archivo one-time de recovery codes", exception);
        }
    }
}
