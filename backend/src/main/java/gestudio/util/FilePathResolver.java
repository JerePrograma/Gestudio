// src/main/java/gestudio/util/FilePathResolver.java
package gestudio.util;

import java.nio.file.Path;
import java.nio.file.Paths;

/**
 * Utilidad para resolver rutas partiendo de la variable de entorno GESTUDIO_HOME.
 */
public final class FilePathResolver {

    private static final String BASE_DIR = initBaseDir();

    private FilePathResolver() {
        // No instanciable
    }

    private static String initBaseDir() {
        String baseDir = System.getProperty("gestudio.home");
        if (baseDir == null || baseDir.isBlank()) {
            baseDir = System.getenv("GESTUDIO_HOME");
        }
        if (baseDir == null || baseDir.isBlank()) {
            throw new IllegalStateException(
                    "GESTUDIO_HOME no definida (variable de entorno o propiedad gestudio.home)"
            );
        }
        return baseDir;
    }

    /**
     * Resuelve una ruta a partir del directorio base,
     * concatenando los segmentos que le pases.
     * Ejemplo:
     *   FilePathResolver.of("imgs", "firma.png")
     *   → /opt/gestudio/imgs/firma.png   (suponiendo GESTUDIO_HOME=/opt/gestudio)
     *
     * @param segments segmentos de la ruta relativa
     * @return Path completo
     */
    public static Path of(String... segments) {
        return Paths.get(BASE_DIR, segments);
    }
}
