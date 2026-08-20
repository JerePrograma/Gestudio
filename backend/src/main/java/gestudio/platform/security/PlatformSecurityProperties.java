package gestudio.platform.security;

import org.springframework.boot.context.properties.ConfigurationProperties;

import java.time.Duration;
import java.util.Base64;

@ConfigurationProperties(prefix = "app.platform-security")
public record PlatformSecurityProperties(
        String audience,
        Duration accessTokenTtl,
        Duration refreshTokenTtl,
        Duration stepUpTtl,
        String mfaEncryptionKey,
        int mfaKeyVersion,
        RefreshCookie refreshCookie
) {
    public PlatformSecurityProperties {
        if (audience == null || audience.isBlank()) {
            throw new IllegalArgumentException("Platform JWT audience es obligatoria");
        }
        if (!positive(accessTokenTtl) || !positive(refreshTokenTtl) || !positive(stepUpTtl)) {
            throw new IllegalArgumentException("Los TTL de plataforma deben ser positivos");
        }
        byte[] encryptionKey;
        try {
            encryptionKey = Base64.getDecoder().decode(mfaEncryptionKey == null ? "" : mfaEncryptionKey);
        } catch (IllegalArgumentException exception) {
            throw new IllegalArgumentException("La clave MFA debe ser Base64 válido", exception);
        }
        if (encryptionKey.length != 32 || mfaKeyVersion < 1) {
            throw new IllegalArgumentException("MFA exige una clave AES-256 y versión positiva");
        }
        if (refreshCookie == null) {
            throw new IllegalArgumentException("La cookie refresh de plataforma es obligatoria");
        }
    }

    private static boolean positive(Duration value) {
        return value != null && !value.isZero() && !value.isNegative();
    }

    public record RefreshCookie(String name, boolean secure, String sameSite, String domain, String path) {
        public RefreshCookie {
            if (name == null || !name.matches("[A-Za-z0-9_-]{1,64}")) {
                throw new IllegalArgumentException("Nombre de cookie refresh de plataforma inválido");
            }
            if (sameSite == null || !(sameSite.equalsIgnoreCase("Strict")
                    || sameSite.equalsIgnoreCase("Lax") || sameSite.equalsIgnoreCase("None"))) {
                throw new IllegalArgumentException("SameSite de plataforma inválido");
            }
            if (sameSite.equalsIgnoreCase("None") && !secure) {
                throw new IllegalArgumentException("SameSite=None exige cookie Secure");
            }
            if (path == null || !path.startsWith("/") || headerDelimiter(path)) {
                throw new IllegalArgumentException("Path de cookie refresh de plataforma inválido");
            }
            if (domain != null && !domain.isBlank()
                    && (headerDelimiter(domain)
                    || !domain.matches("\\.?[A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)*"))) {
                throw new IllegalArgumentException("Domain de cookie refresh de plataforma inválido");
            }
        }

        private static boolean headerDelimiter(String value) {
            return value.contains("\r") || value.contains("\n") || value.contains(";");
        }
    }
}
