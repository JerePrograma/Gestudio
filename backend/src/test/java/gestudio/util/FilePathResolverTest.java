package gestudio.util;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.io.TempDir;

import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Unit tests for FilePathResolver utility class.
 *
 * Uses a temporary application home so the test is independent from the host.
 */
@DisplayName("FilePathResolver Tests")
public class FilePathResolverTest {

    @TempDir
    private static Path gestudioHome;

    @BeforeAll
    public static void setUpEnvironment() {
        System.setProperty("gestudio.home", gestudioHome.toString());
    }

    @AfterAll
    public static void clearEnvironment() {
        System.clearProperty("gestudio.home");
    }

    @Test
    @DisplayName("Should resolve path with single segment")
    public void testOfWithSingleSegment() {
        Path result = FilePathResolver.of("imgs");
        assertNotNull(result);
        assertTrue(result.toString().contains("imgs"));
        assertEquals(gestudioHome.resolve("imgs").toString(), result.toString());
    }

    @Test
    @DisplayName("Should resolve path with multiple segments")
    public void testOfWithMultipleSegments() {
        Path result = FilePathResolver.of("imgs", "firma.png");
        assertNotNull(result);
        assertTrue(result.toString().contains("imgs"));
        assertTrue(result.toString().contains("firma.png"));
        assertEquals(gestudioHome.resolve(Path.of("imgs", "firma.png")).toString(), result.toString());
    }

    @Test
    @DisplayName("Should resolve path with three segments")
    public void testOfWithThreeSegments() {
        Path result = FilePathResolver.of("data", "reports", "2024.pdf");
        assertNotNull(result);
        assertTrue(result.toString().contains("data"));
        assertTrue(result.toString().contains("reports"));
        assertTrue(result.toString().contains("2024.pdf"));
        assertEquals(gestudioHome.resolve(Path.of("data", "reports", "2024.pdf")).toString(), result.toString());
    }

    @Test
    @DisplayName("Should resolve path with many segments")
    public void testOfWithManySegments() {
        Path result = FilePathResolver.of("a", "b", "c", "d", "e", "file.txt");
        assertNotNull(result);
        assertTrue(result.toString().contains("a"));
        assertTrue(result.toString().contains("b"));
        assertTrue(result.toString().contains("c"));
        assertTrue(result.toString().contains("d"));
        assertTrue(result.toString().contains("e"));
        assertTrue(result.toString().contains("file.txt"));
    }

    @Test
    @DisplayName("Should handle segments with special characters")
    public void testOfWithSpecialCharacters() {
        Path result = FilePathResolver.of("folder-1", "file_2023.txt");
        assertNotNull(result);
        assertTrue(result.toString().contains("folder-1"));
        assertTrue(result.toString().contains("file_2023.txt"));
    }

    @Test
    @DisplayName("Should handle empty string segment")
    public void testOfWithEmptySegment() {
        Path result = FilePathResolver.of("folder", "", "file.txt");
        assertNotNull(result);
        // Path will normalize the empty segment, but it should still work
        assertTrue(result.toString().contains("folder"));
        assertTrue(result.toString().contains("file.txt"));
    }

    @Test
    @DisplayName("Should not allow null object instantiation")
    public void testConstructorIsPrivate() {
        try {
            // Try to instantiate via reflection - should fail since constructor is private
            java.lang.reflect.Constructor<FilePathResolver> constructor =
                    FilePathResolver.class.getDeclaredConstructor();
            assertThrows(IllegalAccessException.class, () -> constructor.newInstance());
        } catch (NoSuchMethodException e) {
            // This is expected - there should be no accessible constructor
            assertTrue(true);
        }
    }

    @Test
    @DisplayName("Should start with configured base directory")
    public void testPathStartsWithBaseDirectory() {
        Path result = FilePathResolver.of("test");
        String resultString = result.toString();
        String expectedPrefix = gestudioHome.toString();
        assertTrue(resultString.startsWith(expectedPrefix),
                "Path should start with the configured home: " + expectedPrefix);
    }

    @Test
    @DisplayName("Should handle numeric segment names")
    public void testOfWithNumericSegments() {
        Path result = FilePathResolver.of("2024", "02", "15");
        assertNotNull(result);
        assertTrue(result.toString().contains("2024"));
        assertTrue(result.toString().contains("02"));
        assertTrue(result.toString().contains("15"));
    }

    @Test
    @DisplayName("Should handle mixed case segment names")
    public void testOfWithMixedCaseSegments() {
        Path result = FilePathResolver.of("Images", "MyFile.PNG");
        assertNotNull(result);
        assertTrue(result.toString().contains("Images"));
        assertTrue(result.toString().contains("MyFile.PNG"));
    }

    @Test
    @DisplayName("Should resolve consistent path for same input")
    public void testConsistencyOfResolution() {
        Path result1 = FilePathResolver.of("data", "export");
        Path result2 = FilePathResolver.of("data", "export");
        assertEquals(result1, result2, "Same input should produce same Path");
    }

    @Test
    @DisplayName("Should handle dot segments in path")
    public void testOfWithDotSegments() {
        Path result = FilePathResolver.of("folder", "subdir", ".htaccess");
        assertNotNull(result);
        assertTrue(result.toString().contains(".htaccess"));
    }

    @Test
    @DisplayName("Should not include trailing slash")
    public void testNoTrailingSlash() {
        Path result = FilePathResolver.of("folder", "file.txt");
        String pathStr = result.toString();
        assertFalse(pathStr.endsWith("/") && !pathStr.equals("/"),
                "Path should not have unnecessary trailing slash");
    }
}
