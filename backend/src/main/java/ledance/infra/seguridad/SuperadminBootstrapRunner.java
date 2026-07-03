package ledance.infra.seguridad;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;

@Component
public class SuperadminBootstrapRunner implements ApplicationRunner {
    private static final Logger log = LoggerFactory.getLogger(SuperadminBootstrapRunner.class);

    private final SuperadminBootstrapProperties properties;
    private final AdminBootstrapProperties legacyProperties;
    private final SuperadminBootstrapService service;

    public SuperadminBootstrapRunner(SuperadminBootstrapProperties properties,
                                     AdminBootstrapProperties legacyProperties,
                                     SuperadminBootstrapService service) {
        this.properties = properties;
        this.legacyProperties = legacyProperties;
        this.service = service;
    }

    @Override
    public void run(ApplicationArguments args) {
        if (properties.enabled() && legacyProperties.enabled()) {
            throw new IllegalStateException("No habilite simultáneamente ambos bootstraps");
        }
        if (!properties.enabled() && !legacyProperties.enabled()) return;

        String username = properties.enabled() ? properties.username() : legacyProperties.username();
        String password = properties.enabled() ? properties.password() : legacyProperties.password();
        if (legacyProperties.enabled()) {
            log.warn("APP_BOOTSTRAP_ADMIN_* está deprecado; use APP_BOOTSTRAP_SUPERADMIN_*");
        }
        Long usuarioId = service.bootstrap(username, password).getId();
        log.warn("SUPERADMIN inicial creado con id={}. Deshabilite el bootstrap antes de reiniciar.", usuarioId);
    }
}
