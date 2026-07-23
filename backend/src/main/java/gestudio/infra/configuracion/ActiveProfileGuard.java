package gestudio.infra.configuracion;

import org.springframework.core.env.Environment;
import org.springframework.stereotype.Component;

import java.util.Set;

@Component
public class ActiveProfileGuard {

    private static final Set<String> ALLOWED_PROFILES = Set.of(
            "dev",
            "test",
            "prod",
            "remote-demo"
    );

    public ActiveProfileGuard(Environment environment) {
        String[] activeProfiles = environment.getActiveProfiles();
        if (activeProfiles.length != 1 || !ALLOWED_PROFILES.contains(activeProfiles[0])) {
            throw new IllegalStateException(
                    "Debe activar exactamente un perfil Spring explícito: dev, test, prod o remote-demo"
            );
        }
    }
}
