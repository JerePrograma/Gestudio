package gestudio.infra.seguridad;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "app.security")
public record SecurityProperties(int bcryptStrength, RefreshCookie refreshCookie) {
    public SecurityProperties {
        if (bcryptStrength < 10 || bcryptStrength > 16) {
            throw new IllegalArgumentException("BCrypt strength debe estar entre 10 y 16");
        }
        if (refreshCookie == null) {
            throw new IllegalArgumentException("La configuración de cookie refresh es obligatoria");
        }
    }

    public record RefreshCookie(
            String name,
            boolean secure,
            String sameSite,
            String domain,
            String path
    ) {
        public RefreshCookie {
            if (name == null || !name.matches("[A-Za-z0-9_-]{1,64}")) {
                throw new IllegalArgumentException("Nombre de cookie refresh inválido");
            }
            if (sameSite == null || !(sameSite.equalsIgnoreCase("Strict")
                    || sameSite.equalsIgnoreCase("Lax")
                    || sameSite.equalsIgnoreCase("None"))) {
                throw new IllegalArgumentException("SameSite debe ser Strict, Lax o None");
            }
            if (sameSite.equalsIgnoreCase("None") && !secure) {
                throw new IllegalArgumentException("SameSite=None exige cookie Secure");
            }
            if (path == null || !path.startsWith("/") || hasHeaderDelimiter(path)) {
                throw new IllegalArgumentException("Path de cookie refresh inválido");
            }
            if (domain != null && !domain.isBlank()
                    && (hasHeaderDelimiter(domain)
                    || !domain.matches("\\.?[A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)*"))) {
                throw new IllegalArgumentException("Domain de cookie refresh inválido");
            }
        }

        private static boolean hasHeaderDelimiter(String value) {
            return value.contains("\r") || value.contains("\n") || value.contains(";");
        }
    }
}
