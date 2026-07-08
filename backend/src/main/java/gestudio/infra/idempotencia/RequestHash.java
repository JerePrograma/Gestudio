package gestudio.infra.idempotencia;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;

public final class RequestHash {
    private RequestHash() {
    }

    public static String sha256(String... values) {
        StringBuilder canonical = new StringBuilder();
        for (String value : values) {
            if (value == null) {
                canonical.append("-1:");
            } else {
                canonical.append(value.length()).append(':').append(value);
            }
        }
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
                    .digest(canonical.toString().getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 no disponible", e);
        }
    }
}
