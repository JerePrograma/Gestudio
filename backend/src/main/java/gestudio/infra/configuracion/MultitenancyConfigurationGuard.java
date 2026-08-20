package gestudio.infra.configuracion;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

@Component
@Profile({"prod", "remote-demo"})
public class MultitenancyConfigurationGuard {

    public MultitenancyConfigurationGuard(
            @Value("${app.multitenancy.required:true}") boolean required,
            @Value("${spring.datasource.url:}") String applicationUrl,
            @Value("${spring.datasource.username:}") String applicationUser,
            @Value("${spring.flyway.user:}") String migrationUser,
            @Value("${app.platform-datasource.url:}") String platformUrl,
            @Value("${app.platform-datasource.username:}") String platformUser,
            @Value("${app.platform-datasource.password:}") String platformPassword) {
        if (!required) {
            throw new IllegalStateException("Los perfiles públicos exigen multitenancy obligatorio");
        }
        if (blank(applicationUser) || blank(migrationUser)
                || applicationUser.equalsIgnoreCase(migrationUser)
                || applicationUser.equalsIgnoreCase("postgres")) {
            throw new IllegalStateException(
                    "RLS exige usuarios PostgreSQL distintos para aplicación y migraciones");
        }
        if (blank(platformUrl) || blank(platformUser) || blank(platformPassword)
                || !platformUrl.equals(applicationUrl)
                || platformUser.equalsIgnoreCase(applicationUser)
                || platformUser.equalsIgnoreCase(migrationUser)
                || platformUser.equalsIgnoreCase("postgres")) {
            throw new IllegalStateException(
                    "Control plane exige el mismo PostgreSQL y un usuario runtime dedicado");
        }
    }

    private static boolean blank(String value) {
        return value == null || value.isBlank();
    }
}
