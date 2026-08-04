package gestudio.infra.configuracion;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

@Component
@Profile({"prod", "remote-demo"})
public class MultitenancyConfigurationGuard {

    public MultitenancyConfigurationGuard(
            @Value("${app.multitenancy.required:true}") boolean required,
            @Value("${spring.datasource.username:}") String applicationUser,
            @Value("${spring.flyway.user:}") String migrationUser) {
        if (!required) {
            throw new IllegalStateException("Los perfiles públicos exigen multitenancy obligatorio");
        }
        if (blank(applicationUser) || blank(migrationUser)
                || applicationUser.equalsIgnoreCase(migrationUser)
                || applicationUser.equalsIgnoreCase("postgres")) {
            throw new IllegalStateException(
                    "RLS exige usuarios PostgreSQL distintos para aplicación y migraciones");
        }
    }

    private static boolean blank(String value) {
        return value == null || value.isBlank();
    }
}
