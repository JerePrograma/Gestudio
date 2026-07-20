package gestudio.integraciones.jereplatform.infrastructure;

import gestudio.integraciones.jereplatform.application.StudentSourceExportException;
import org.springframework.stereotype.Component;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.util.HexFormat;

import static gestudio.integraciones.jereplatform.application.StudentSourceExportException.Code.SIGNATURE_FAILED;
import static gestudio.integraciones.jereplatform.application.StudentSourceExportException.Code.SOURCE_SECRET_MISSING;
import static gestudio.integraciones.jereplatform.application.StudentSourceExportException.Code.SOURCE_SECRET_TOO_SHORT;

@Component
public class StudentSourceExportSigner {
    private final StudentSourceExportProperties properties;

    public StudentSourceExportSigner(StudentSourceExportProperties properties) {
        this.properties = properties;
    }

    public void requireConfigured() {
        key();
    }

    public String sign(byte[] payload) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(key(), "HmacSHA256"));
            return "sha256=" + HexFormat.of().formatHex(mac.doFinal(payload));
        } catch (GeneralSecurityException exception) {
            throw new StudentSourceExportException(SIGNATURE_FAILED);
        }
    }

    private byte[] key() {
        if (properties.currentSecret() == null || properties.currentSecret().isBlank()) {
            throw new StudentSourceExportException(SOURCE_SECRET_MISSING);
        }
        byte[] key = properties.currentSecret().getBytes(StandardCharsets.UTF_8);
        if (key.length < 32) {
            throw new StudentSourceExportException(SOURCE_SECRET_TOO_SHORT);
        }
        return key;
    }
}
