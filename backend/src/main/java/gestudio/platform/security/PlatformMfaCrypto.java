package gestudio.platform.security;

import org.springframework.stereotype.Component;

import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import java.security.GeneralSecurityException;
import java.security.SecureRandom;
import java.util.Arrays;
import java.util.Base64;

@Component
public class PlatformMfaCrypto {
    private static final int IV_BYTES = 12;
    private static final int TAG_BITS = 128;

    private final SecretKeySpec key;
    private final int keyVersion;
    private final SecureRandom random = new SecureRandom();

    public PlatformMfaCrypto(PlatformSecurityProperties properties) {
        this.key = new SecretKeySpec(Base64.getDecoder().decode(properties.mfaEncryptionKey()), "AES");
        this.keyVersion = properties.mfaKeyVersion();
    }

    public Encrypted encrypt(byte[] plaintext) {
        if (plaintext == null || plaintext.length == 0) throw new IllegalArgumentException("Secret MFA vacío");
        byte[] iv = new byte[IV_BYTES];
        random.nextBytes(iv);
        try {
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, key, new GCMParameterSpec(TAG_BITS, iv));
            byte[] ciphertext = cipher.doFinal(plaintext);
            byte[] envelope = new byte[iv.length + ciphertext.length];
            System.arraycopy(iv, 0, envelope, 0, iv.length);
            System.arraycopy(ciphertext, 0, envelope, iv.length, ciphertext.length);
            return new Encrypted(envelope, keyVersion);
        } catch (GeneralSecurityException exception) {
            throw new IllegalStateException("No se pudo cifrar el secreto MFA", exception);
        }
    }

    public byte[] decrypt(byte[] envelope, int persistedKeyVersion) {
        if (persistedKeyVersion != keyVersion || envelope == null || envelope.length <= IV_BYTES + 16) {
            throw new IllegalStateException("Credencial MFA cifrada con versión no disponible");
        }
        byte[] iv = Arrays.copyOfRange(envelope, 0, IV_BYTES);
        byte[] ciphertext = Arrays.copyOfRange(envelope, IV_BYTES, envelope.length);
        try {
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, key, new GCMParameterSpec(TAG_BITS, iv));
            return cipher.doFinal(ciphertext);
        } catch (GeneralSecurityException exception) {
            throw new IllegalStateException("No se pudo descifrar la credencial MFA", exception);
        }
    }

    public record Encrypted(byte[] ciphertext, int keyVersion) {
        public Encrypted {
            ciphertext = ciphertext.clone();
        }

        @Override
        public byte[] ciphertext() {
            return ciphertext.clone();
        }
    }
}
