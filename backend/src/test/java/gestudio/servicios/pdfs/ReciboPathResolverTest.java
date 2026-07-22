package gestudio.servicios.pdfs;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

class ReciboPathResolverTest {

    @TempDir
    Path temp;

    @Test
    void resuelveUnArchivoFisicoDentroDelDirectorio() throws IOException {
        Path root = Files.createDirectory(temp.resolve("receipts"));
        Path receipt = Files.writeString(root.resolve("recibo_7.pdf"), "pdf");

        assertThat(ReciboPathResolver.resolveExistingFile(root, "recibo_7.pdf"))
                .isEqualTo(receipt.toRealPath());
        assertThat(ReciboPathResolver.resolveExistingFile(root, "../secreto.txt")).isNull();
        assertThat(ReciboPathResolver.resolveExistingFile(root, temp.resolve("secreto.txt").toString())).isNull();
    }

    @Test
    void rechazaSymlinkFinal() throws IOException {
        Path root = Files.createDirectory(temp.resolve("receipts"));
        Path secret = Files.writeString(temp.resolve("secreto.txt"), "secreto");
        Path link = root.resolve("recibo_7.pdf");
        assumeTrue(createSymlink(link, secret), "El sistema no permite crear symlinks para la prueba");

        assertThat(ReciboPathResolver.resolveExistingFile(root, "recibo_7.pdf")).isNull();
    }

    @Test
    void rechazaDirectorioIntermedioQueEscapaPorSymlink() throws IOException {
        Path root = Files.createDirectory(temp.resolve("receipts"));
        Path outside = Files.createDirectory(temp.resolve("outside"));
        Files.writeString(outside.resolve("recibo_7.pdf"), "secreto");
        assumeTrue(createSymlink(root.resolve("subdir"), outside),
                "El sistema no permite crear symlinks para la prueba");

        assertThat(ReciboPathResolver.resolveExistingFile(root, "subdir/recibo_7.pdf")).isNull();
    }

    private static boolean createSymlink(Path link, Path target) {
        try {
            Files.createSymbolicLink(link, target);
            return true;
        } catch (IOException | UnsupportedOperationException | SecurityException e) {
            return false;
        }
    }
}
