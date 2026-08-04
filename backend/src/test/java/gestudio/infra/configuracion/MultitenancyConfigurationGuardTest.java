package gestudio.infra.configuracion;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class MultitenancyConfigurationGuardTest {

    @Test
    void aceptaRolesSeparadosConMultitenancyObligatorio() {
        assertThatCode(() -> new MultitenancyConfigurationGuard(
                true, "gestudio_app_prod", "gestudio_migrator"))
                .doesNotThrowAnyException();
    }

    @Test
    void rechazaDesactivacionUsuarioVacioSuperuserOMismoRol() {
        assertThatThrownBy(() -> new MultitenancyConfigurationGuard(
                false, "gestudio_app", "gestudio_migrator"))
                .hasMessageContaining("multitenancy obligatorio");
        assertThatThrownBy(() -> new MultitenancyConfigurationGuard(
                true, "", "gestudio_migrator"))
                .hasMessageContaining("usuarios PostgreSQL distintos");
        assertThatThrownBy(() -> new MultitenancyConfigurationGuard(
                true, "postgres", "gestudio_migrator"))
                .hasMessageContaining("usuarios PostgreSQL distintos");
        assertThatThrownBy(() -> new MultitenancyConfigurationGuard(
                true, "gestudio_app", "GESTUDIO_APP"))
                .hasMessageContaining("usuarios PostgreSQL distintos");
    }
}
