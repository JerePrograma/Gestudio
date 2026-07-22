package gestudio.servicios.pdfs;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.InvalidPathException;
import java.nio.file.LinkOption;
import java.nio.file.Path;

public final class ReciboPathResolver {

    private ReciboPathResolver() {
    }

    public static Path resolveExistingFile(Path configuredRoot, String storageKey) {
        if (storageKey == null || storageKey.isBlank()) {
            return null;
        }
        try {
            Path root = configuredRoot.toAbsolutePath().normalize();
            Path candidate = root.resolve(storageKey).normalize();
            if (!candidate.startsWith(root)
                    || !Files.isRegularFile(candidate, LinkOption.NOFOLLOW_LINKS)) {
                return null;
            }

            Path realRoot = root.toRealPath();
            Path realFile = candidate.toRealPath();
            return realFile.startsWith(realRoot)
                    && Files.isRegularFile(realFile, LinkOption.NOFOLLOW_LINKS)
                    ? realFile
                    : null;
        } catch (IOException | InvalidPathException | SecurityException e) {
            return null;
        }
    }
}
