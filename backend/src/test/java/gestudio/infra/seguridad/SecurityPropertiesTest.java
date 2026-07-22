package gestudio.infra.seguridad;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class SecurityPropertiesTest {

    @Test
    void aceptaConfiguracionSegura() {
        assertThatCode(() -> properties(12, true, "Strict", "", "/api/login"))
                .doesNotThrowAnyException();
        assertThatCode(() -> properties(12, true, "None", ".example.test", "/api/login"))
                .doesNotThrowAnyException();
    }

    @Test
    void rechazaCostoDebilOCookieManipulable() {
        assertThatThrownBy(() -> properties(9, true, "Strict", "", "/api/login"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("BCrypt");
        assertThatThrownBy(() -> properties(12, false, "None", "", "/api/login"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("Secure");
        assertThatThrownBy(() -> properties(12, true, "Strict", "example.test\r\nInjected: x", "/"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("Domain");
        assertThatThrownBy(() -> properties(12, true, "Strict", "", "api/login"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("Path");
    }

    private SecurityProperties properties(
            int strength, boolean secure, String sameSite, String domain, String path) {
        return new SecurityProperties(strength,
                new SecurityProperties.RefreshCookie("gestudio_refresh", secure, sameSite, domain, path));
    }
}
