package gestudio.platform.security;

import org.springframework.stereotype.Component;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.ByteBuffer;
import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.util.OptionalLong;

@Component
public class TotpService {
    static final long STEP_SECONDS = 30;

    private final Clock clock;

    public TotpService(Clock clock) {
        this.clock = clock;
    }

    public OptionalLong verify(byte[] secret, String candidate, Long lastCounter) {
        if (candidate == null || !candidate.matches("\\d{6}")) return OptionalLong.empty();
        long current = Math.floorDiv(clock.instant().getEpochSecond(), STEP_SECONDS);
        for (long counter = current - 1; counter <= current + 1; counter++) {
            if ((lastCounter == null || counter > lastCounter)
                    && MessageDigest.isEqual(
                    code(secret, counter).getBytes(StandardCharsets.US_ASCII),
                    candidate.getBytes(StandardCharsets.US_ASCII))) {
                return OptionalLong.of(counter);
            }
        }
        return OptionalLong.empty();
    }

    static String code(byte[] secret, long counter) {
        try {
            Mac mac = Mac.getInstance("HmacSHA1");
            mac.init(new SecretKeySpec(secret, "HmacSHA1"));
            byte[] digest = mac.doFinal(ByteBuffer.allocate(Long.BYTES).putLong(counter).array());
            int offset = digest[digest.length - 1] & 0x0f;
            int binary = ((digest[offset] & 0x7f) << 24)
                    | ((digest[offset + 1] & 0xff) << 16)
                    | ((digest[offset + 2] & 0xff) << 8)
                    | (digest[offset + 3] & 0xff);
            return "%06d".formatted(binary % 1_000_000);
        } catch (GeneralSecurityException exception) {
            throw new IllegalStateException("HMAC-SHA1 no disponible", exception);
        }
    }
}
