package gestudio.infra.configuracion;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class MultitenancyConfigurationGuardTest {

    private static final String JDBC_URL = "jdbc:postgresql://db:5432/gestudio";

    @Test
    void aceptaTresCredencialesSeparadasEnLaMismaBase() {
        assertThatCode(() -> new MultitenancyConfigurationGuard(
                true,
                JDBC_URL,
                "gestudio_app_prod",
                "gestudio_migrator",
                JDBC_URL,
                "gestudio_platform_runtime",
                "platform-secret"))
                .doesNotThrowAnyException();
    }

    @Test
    void rechazaDesactivacionUsuarioAppVacioSuperuserOMismoRol() {
        assertThatThrownBy(() -> new MultitenancyConfigurationGuard(
                false, JDBC_URL, "gestudio_app", "gestudio_migrator",
                JDBC_URL, "gestudio_platform_runtime", "platform-secret"))
                .hasMessageContaining("multitenancy obligatorio");
        assertThatThrownBy(() -> new MultitenancyConfigurationGuard(
                true, JDBC_URL, "", "gestudio_migrator",
                JDBC_URL, "gestudio_platform_runtime", "platform-secret"))
                .hasMessageContaining("usuarios PostgreSQL distintos");
        assertThatThrownBy(() -> new MultitenancyConfigurationGuard(
                true, JDBC_URL, "postgres", "gestudio_migrator",
                JDBC_URL, "gestudio_platform_runtime", "platform-secret"))
                .hasMessageContaining("usuarios PostgreSQL distintos");
        assertThatThrownBy(() -> new MultitenancyConfigurationGuard(
                true, JDBC_URL, "gestudio_app", "GESTUDIO_APP",
                JDBC_URL, "gestudio_platform_runtime", "platform-secret"))
                .hasMessageContaining("usuarios PostgreSQL distintos");
    }

    @Test
    void rechazaCredencialPlatformIncompletaCompartidaPrivilegiadaOEnOtraBase() {
        for (String forbiddenUser : new String[]{"gestudio_app", "GESTUDIO_MIGRATOR", "postgres"}) {
            assertThatThrownBy(() -> new MultitenancyConfigurationGuard(
                    true, JDBC_URL, "gestudio_app", "gestudio_migrator",
                    JDBC_URL, forbiddenUser, "platform-secret"))
                    .hasMessageContaining("usuario runtime dedicado");
        }

        assertThatThrownBy(() -> new MultitenancyConfigurationGuard(
                true, JDBC_URL, "gestudio_app", "gestudio_migrator",
                JDBC_URL, "gestudio_platform_runtime", ""))
                .hasMessageContaining("usuario runtime dedicado");
        assertThatThrownBy(() -> new MultitenancyConfigurationGuard(
                true, JDBC_URL, "gestudio_app", "gestudio_migrator",
                "jdbc:postgresql://other-db:5432/gestudio", "gestudio_platform_runtime", "platform-secret"))
                .hasMessageContaining("mismo PostgreSQL");
    }
}
