# Unit Testing Quick Start Guide

## Quick Commands

### Run All Tests
```bash
cd backend
export GESTUDIO_HOME=/opt/gestudio
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
mvn test
```

### Run Specific Test Class
```bash
mvn test -Dtest=FilePathResolverTest
```

### Generate Coverage Report
```bash
mvn clean test
# Report will be at: backend/target/site/jacoco/index.html
```

### View Coverage Report (macOS)
```bash
open backend/target/site/jacoco/index.html
```

### View Coverage Report (Linux)
```bash
firefox backend/target/site/jacoco/index.html
# or
xdg-open backend/target/site/jacoco/index.html
```

## Current Test Coverage

| Package | Classes | Tests | Status |
|---------|---------|-------|--------|
| `gestudio.util` | 1 | 13 ✅ | Complete |
| `gestudio.validaciones.*` | 5+ | 0 | Needed |
| `gestudio.servicios.pago` | 1 | 2 ✅ | Partial |
| `gestudio.servicios.*` | 30+ | ~2 | Critical |
| `gestudio.dto.*` | 100+ | 0 | Needed |

## Adding New Tests

### 1. Create Test File
```bash
# For a class: backend/src/main/java/gestudio/mypackage/MyClass.java
# Create:     backend/src/test/java/gestudio/mypackage/MyClassTest.java
touch backend/src/test/java/gestudio/mypackage/MyClassTest.java
```

### 2. Test Template
```java
package gestudio.mypackage;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import static org.junit.jupiter.api.Assertions.*;

@DisplayName("MyClass Tests")
public class MyClassTest {

    private MyClass myClass;

    @BeforeEach
    public void setUp() {
        myClass = new MyClass();
    }

    @Test
    @DisplayName("Should do something specific")
    public void testSomething() {
        // Arrange
        var input = "test";
        
        // Act
        var result = myClass.methodUnderTest(input);
        
        // Assert
        assertNotNull(result);
        assertEquals("expected", result);
    }
}
```

### 3. Run New Test
```bash
mvn test -Dtest=MyClassTest
```

## Best Practices

✅ **DO:**
- Write one assertion per test when possible
- Use descriptive test names with `@DisplayName`
- Test edge cases and error conditions
- Use `BeforeEach` for common setup
- Test behavior, not implementation

❌ **DON'T:**
- Mock everything (use real objects when possible)
- Test multiple unrelated things in one test
- Skip tests that are hard to test
- Ignore test failures

## Coverage Goals

| Metric | Current | Target |
|--------|---------|--------|
| Line Coverage | ~3% | 70% |
| Branch Coverage | ~2% | 60% |
| Instruction Coverage | ~2% | 70% |

## Environment Setup

### Linux Setup
```bash
# Install Java 21
sudo apt install openjdk-21-jdk

# Install Maven
sudo apt install maven

# Set default Java
sudo update-alternatives --config java

# Create GESTUDIO_HOME for tests
export GESTUDIO_HOME=/opt/gestudio
```

### macOS Setup
```bash
# Install via Homebrew
brew install openjdk@21
brew install maven

# Set environment
export JAVA_HOME=/opt/homebrew/opt/openjdk@21
export GESTUDIO_HOME=/opt/gestudio
```

## IDE Integration

### VS Code
1. Install "Test Runner for Java" extension
2. Install "SonarLint" for code quality
3. Tests will appear in Test Explorer (left sidebar)

### IntelliJ IDEA
1. Right-click test file → "Run" or "Run with Coverage"
2. View → Tool Windows → Coverage
3. Built-in JaCoCo integration

## Troubleshooting

**❌ Error: "Variable de entorno GESTUDIO_HOME no definida"**
```bash
# Solution: Set the environment variable
export GESTUDIO_HOME=/opt/gestudio
mvn test
```

**❌ Error: "release version 21 not supported"**
```bash
# Solution: Use correct JAVA_HOME
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
mvn test
```

**❌ Tests fail in IDE but work in CLI**
- Check IDE's Java version settings
- Run: `mvn eclipse:eclipse` or `mvn idea:idea`
- Rebuild IDE project index

## Next Steps

1. **This Week:** Create tests for validation classes
2. **Next Week:** Create tests for top 5 service classes
3. **Monthly Goal:** Reach 50% code coverage
4. **Quarterly Goal:** Reach 70% code coverage

## References

- [JUnit 5 User Guide](https://junit.org/junit5/docs/current/user-guide/)
- [Mockito Documentation](https://javadoc.io/doc/org.mockito/mockito-core/latest/org/mockito/Mockito.html)
- [JaCoCo Plugin Guide](https://www.eclemma.org/jacoco/trunk/doc/maven.html)
- [Spring Boot Testing](https://spring.io/guides/gs/testing-web/)

## Support

For questions or issues with tests:
1. Check existing test examples in `backend/src/test/`
2. Review code comments in test files
3. Run with Maven verbose flag: `mvn -X test`
