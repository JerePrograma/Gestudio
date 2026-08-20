package gestudio.platform.security;

import java.io.ByteArrayOutputStream;
import java.util.Locale;

final class Base32 {
    private static final int BITS_PER_BYTE = 8;
    private static final char[] ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".toCharArray();

    private Base32() {
    }

    static String encode(byte[] value) {
        if (value == null || value.length == 0) throw new IllegalArgumentException("Valor Base32 vacío");
        StringBuilder output = new StringBuilder((value.length * 8 + 4) / 5);
        int buffer = 0;
        int bits = 0;
        for (byte current : value) {
            buffer = (buffer << 8) | (current & 0xff);
            bits += 8;
            while (bits >= 5) {
                output.append(ALPHABET[(buffer >>> (bits - 5)) & 31]);
                bits -= 5;
            }
        }
        if (bits > 0) output.append(ALPHABET[(buffer << (5 - bits)) & 31]);
        return output.toString();
    }

    static byte[] decode(String value) {
        String normalized = normalize(value);
        ByteArrayOutputStream output = new ByteArrayOutputStream(normalized.length() * 5 / 8);
        int buffer = 0;
        int bits = 0;
        for (int i = 0; i < normalized.length(); i++) {
            int digit = digit(normalized.charAt(i));
            if (digit < 0) throw new IllegalArgumentException("Secret TOTP Base32 inválido");
            buffer = (buffer << 5) | digit;
            bits += 5;
            if (bits >= BITS_PER_BYTE) {
                output.write((buffer >>> (bits - BITS_PER_BYTE)) & 0xff);
                bits -= BITS_PER_BYTE;
            }
        }
        return validateLength(output.toByteArray());
    }

    private static String normalize(String value) {
        String normalized = value == null ? "" : value.replace(" ", "")
                .replace("-", "").replace("=", "").toUpperCase(Locale.ROOT);
        if (normalized.isEmpty()) throw new IllegalArgumentException("Secret TOTP requerido");
        return normalized;
    }

    private static byte[] validateLength(byte[] decoded) {
        if (decoded.length < 20 || decoded.length > 64) {
            throw new IllegalArgumentException("Secret TOTP debe tener entre 160 y 512 bits");
        }
        return decoded;
    }

    private static int digit(char value) {
        if (value >= 'A' && value <= 'Z') return value - 'A';
        if (value >= '2' && value <= '7') return value - '2' + 26;
        return -1;
    }
}
