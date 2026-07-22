package gestudio.infra.seguridad;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;

@Component
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
        if (!properties.enabled()) return;

        Long usuarioId = service.bootstrap(properties.username(), properties.password()).getId();
        log.warn("SUPERADMIN inicial creado con id={}. Deshabilite el bootstrap antes de reiniciar.", usuarioId);
    }
}
