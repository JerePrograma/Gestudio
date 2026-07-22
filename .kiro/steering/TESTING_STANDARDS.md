# Testing Policies & Standards

> Historical supporting guidance. `AGENTS.md` and `TESTING.md` are the current
> test contract for Gestudio.

**Effective Date:** February 16, 2026  
**Scope:** Gestudio test code
**Owner:** Development Team

---

## 1. Testing Mandate

### Every Feature Must Have Tests

**Non-negotiable rule**: 
- ✅ New business logic → Must have unit tests
- ✅ Bug fixes → Must have test that reproduces bug
- ✅ API endpoints → Must have controller tests
- ✅ Database operations → Must have integration tests
- ✅ External integrations → Must have adapter tests

**Exception Process**:
If you cannot write a test for something, document why in a comment:

```java
// Test not possible because: [reason]
// Blocked by: [issue or dependency]
@Disabled("Awaiting X3PO API mock documentation")
public void testExternalIntegration() {
    // ... future implementation
}
```

---

## 2. Test Types & Where to Write Them

### 1. Unit Tests (Domain Layer)

**Purpose**: Test business logic in isolation  
**Location**: `src/test/java/gestudio/core/domain`  
**Dependencies**: None (no mocks)  
**Framework**: JUnit 5  
**Target Coverage**: 90%+

```java
@DisplayName("Payment Calculator Tests")
public class PaymentCalculatorTest {
    
    private PaymentCalculator calculator;
    
    @BeforeEach
    public void setUp() {
        calculator = new PaymentCalculator();
    }
    
    @Test
    @DisplayName("Should calculate monthly payment with discount")
    public void calculatePaymentWithDiscount() {
        // Arrange
        Student student = Student.builder()
            .discount(Money.of(10))
            .build();
        Discipline discipline = Discipline.builder()
            .monthlyFee(Money.of(100))
            .build();
        
        // Act
        Money result = calculator.calculate(student, discipline);
        
        // Assert
        assertEquals(Money.of(90), result);
    }
    
    @Test
    @DisplayName("Should throw exception for negative discount")
    public void rejectNegativeDiscount() {
        Student student = Student.builder()
            .discount(Money.of(-10))
            .build();
        
        assertThrows(IllegalArgumentException.class, 
            () -> new Student(student));  // Validation in constructor
    }
}
```

**Unit Test Checklist**:
- [ ] No mocks (use real objects)
- [ ] No `@SpringBootTest` annotations
- [ ] Tests run in <100ms
- [ ] No database calls
- [ ] No external service calls
- [ ] Clear Arrange-Act-Assert structure
- [ ] Descriptive test names with `@DisplayName`

### 2. Integration Tests (Service + Repository)

**Purpose**: Test services with real repositories, mocked external calls  
**Location**: `src/test/java/gestudio/servicios`  
**Dependencies**: Database (in-memory or testcontainers), Mocked gateways  
**Framework**: JUnit 5 + Spring Boot Test  
**Target Coverage**: 70%+

```java
@SpringBootTest
@DisplayName("Payment Service Integration Tests")
public class PaymentServiceIntegrationTest {
    
    @MockBean
    private PaymentGateway paymentGateway;
    
    @Autowired
    private PaymentService paymentService;
    
    @Autowired
    private PaymentRepository paymentRepo;
    
    @Test
    @DisplayName("Should persist payment after successful gateway processing")
    public void processAndPersistPayment() {
        // Arrange
        Student student = createTestStudent();
        PaymentRequest request = PaymentRequest.builder()
            .studentId(student.getId())
            .amount(Money.of(100))
            .build();
        
        when(paymentGateway.process(any()))
            .thenReturn(PaymentResult.success("txn-123"));
        
        // Act
        PaymentResponse response = paymentService.processPayment(request);
        
        // Assert
        assertTrue(response.isSuccessful());
        
        // Verify persisted
        Payment saved = paymentRepo.findById(response.getTransactionId())
            .orElseThrow();
        assertEquals(PaymentStatus.COMPLETED, saved.getStatus());
    }
    
    @Test
    @DisplayName("Should not persist payment if gateway fails")
    public void failGracefullyOnGatewayError() {
        // Arrange
        PaymentRequest request = PaymentRequest.builder()
            .studentId("123")
            .amount(Money.of(100))
            .build();
        
        when(paymentGateway.process(any()))
            .thenThrow(new PaymentGatewayException("Network timeout"));
        
        // Act & Assert
        assertThrows(PaymentGatewayException.class,
            () -> paymentService.processPayment(request));
        
        // Verify nothing was saved
        assertTrue(paymentRepo.findAll().isEmpty());
    }
}
```

**Integration Test Checklist**:
- [ ] Uses `@SpringBootTest` or `@DataJpaTest`
- [ ] Mocks external services only (gateway, email, etc.)
- [ ] Real repositories and database
- [ ] Cleans up data between tests (`@Transactional`)
- [ ] Tests run in 100-500ms range
- [ ] Tests both happy path and error cases
- [ ] Verifies persistence and side effects

### 3. Controller/API Tests

**Purpose**: Test HTTP contract and request/response mapping  
**Location**: `src/test/java/gestudio/controladores`  
**Dependencies**: Services (mocked)  
**Framework**: JUnit 5 + MockMvc  
**Target Coverage**: 60%+

```java
@WebMvcTest(PaymentController.class)
@DisplayName("Payment Controller Tests")
public class PaymentControllerTest {
    
    @MockBean
    private PaymentService paymentService;
    
    @Autowired
    private MockMvc mockMvc;
    
    @Autowired
    private ObjectMapper objectMapper;
    
    @Test
    @DisplayName("Should return 200 with payment response on success")
    public void processPaymentSuccess() throws Exception {
        // Arrange
        PaymentRequest request = PaymentRequest.builder()
            .studentId("123")
            .amount(new BigDecimal("100.00"))
            .build();
        
        PaymentResponse response = PaymentResponse.builder()
            .transactionId("txn-123")
            .status("SUCCESS")
            .processedAt(LocalDateTime.now())
            .build();
        
        when(paymentService.processPayment(any()))
            .thenReturn(response);
        
        // Act & Assert
        mockMvc.perform(post("/api/payments")
                .contentType(APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(request)))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.transactionId").value("txn-123"))
            .andExpect(jsonPath("$.status").value("SUCCESS"));
    }
    
    @Test
    @DisplayName("Should return 400 for invalid request")
    public void processPaymentInvalidRequest() throws Exception {
        // Arrange
        PaymentRequest request = PaymentRequest.builder()
            .studentId(null)  // Invalid: required field
            .amount(new BigDecimal("100.00"))
            .build();
        
        // Act & Assert
        mockMvc.perform(post("/api/payments")
                .contentType(APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(request)))
            .andExpect(status().isBadRequest());
    }
    
    @Test
    @DisplayName("Should return 404 when student not found")
    public void processPaymentStudentNotFound() throws Exception {
        // Arrange
        PaymentRequest request = PaymentRequest.builder()
            .studentId("999")
            .amount(new BigDecimal("100.00"))
            .build();
        
        when(paymentService.processPayment(any()))
            .thenThrow(new StudentNotFoundException("999"));
        
        // Act & Assert
        mockMvc.perform(post("/api/payments")
                .contentType(APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(request)))
            .andExpect(status().isNotFound());
    }
}
```

**API Test Checklist**:
- [ ] Tests HTTP status codes (200, 400, 404, 500)
- [ ] Tests request validation
- [ ] Tests response structure
- [ ] Tests error responses
- [ ] Uses `MockMvc` for testing
- [ ] Mocks services (no database)
- [ ] Tests authentication/authorization if applicable
- [ ] Tests multipart requests if applicable

### 4. Repository Tests (Data Access)

**Purpose**: Test database queries and mappings  
**Location**: `src/test/java/gestudio/infra/repositorios`  
**Dependencies**: Database (embedded/testcontainers)  
**Framework**: JUnit 5 + Spring Data Test (`@DataJpaTest`)  
**Target Coverage**: 70%+

```java
@DataJpaTest
@DisplayName("Student Repository Tests")
public class StudentRepositoryTest {
    
    @Autowired
    private StudentRepository repository;
    
    @Autowired
    private TestEntityManager entityManager;
    
    @Test
    @DisplayName("Should find student by email")
    public void findByEmail() {
        // Arrange
        StudentEntity student = new StudentEntity();
        student.setName("Juan Perez");
        student.setEmail("juan@example.com");
        entityManager.persistAndFlush(student);
        
        // Act
        Optional<StudentEntity> found = repository.findByEmail("juan@example.com");
        
        // Assert
        assertTrue(found.isPresent());
        assertEquals("Juan Perez", found.get().getName());
    }
    
    @Test
    @DisplayName("Should return empty when student email not found")
    public void findByEmailNotFound() {
        // Act
        Optional<StudentEntity> found = repository.findByEmail("notexist@example.com");
        
        // Assert
        assertTrue(found.isEmpty());
    }
    
    @Test
    @DisplayName("Should find all active students")
    public void findAllActive() {
        // Arrange
        StudentEntity active1 = createStudent("Active 1", true);
        StudentEntity active2 = createStudent("Active 2", true);
        StudentEntity inactive = createStudent("Inactive", false);
        
        entityManager.persist(active1);
        entityManager.persist(active2);
        entityManager.persist(inactive);
        entityManager.flush();
        
        // Act
        List<StudentEntity> active = repository.findByStatusTrue();
        
        // Assert
        assertEquals(2, active.size());
        assertTrue(active.stream().anyMatch(s -> s.getName().equals("Active 1")));
        assertTrue(active.stream().anyMatch(s -> s.getName().equals("Active 2")));
    }
    
    private StudentEntity createStudent(String name, boolean status) {
        StudentEntity student = new StudentEntity();
        student.setName(name);
        student.setStatus(status);
        return student;
    }
}
```

**Repository Test Checklist**:
- [ ] Uses `@DataJpaTest` (not `@SpringBootTest`)
- [ ] Tests each custom query method
- [ ] Tests sorting and pagination
- [ ] Tests filtering
- [ ] Checks entity relationships load correctly
- [ ] Uses `TestEntityManager` for setup
- [ ] Tests edge cases (null, empty results, etc.)

### 5. Adapter/Integration Tests (External Systems)

**Purpose**: Test integration with external services  
**Location**: `src/test/java/gestudio/infra/adapters`  
**Dependencies**: Mocked external services (Wiremock, testcontainers)  
**Framework**: JUnit 5 + Wiremock / testcontainers  
**Target Coverage**: 60%+

```java
@ExtendWith(WireMockExtension.class)
@DisplayName("Paypal Gateway Adapter Tests")
public class PaypalPaymentGatewayTest {
    
    private PaypalPaymentGateway gateway;
    private WireMockServer wireMock;
    
    @BeforeEach
    public void setUp(WireMockRuntimeInfo wmRuntimeInfo) {
        this.wireMock = wmRuntimeInfo.getWireMock();
        this.gateway = new PaypalPaymentGateway(
            wmRuntimeInfo.getHttpBaseUrl(),
            "test-api-key");
    }
    
    @Test
    @DisplayName("Should successfully process payment with Paypal API")
    public void processPaymentSuccess() {
        // Arrange
        wireMock.stubFor(post("/payments")
            .willReturn(aResponse()
                .withStatus(200)
                .withHeader("Content-Type", "application/json")
                .withBody("""
                    {
                        "id": "txn-123",
                        "status": "SUCCESS",
                        "timestamp": "2026-02-16T10:30:00Z"
                    }
                    """)));
        
        PaymentRequest request = PaymentRequest.builder()
            .amount(Money.of(100))
            .build();
        
        // Act
        PaymentResult result = gateway.process(request);
        
        // Assert
        assertTrue(result.isSuccess());
        assertEquals("txn-123", result.getTransactionId());
    }
    
    @Test
    @DisplayName("Should handle Paypal API timeout")
    public void processPaymentTimeout() {
        // Arrange
        wireMock.stubFor(post("/payments")
            .willReturn(aResponse()
                .withFixedDelay(5000)
                .withStatus(504)));
        
        PaymentRequest request = PaymentRequest.builder()
            .amount(Money.of(100))
            .build();
        
        // Act & Assert
        assertThrows(PaymentGatewayException.class,
            () -> gateway.process(request));
    }
}
```

**Adapter Test Checklist**:
- [ ] Uses Wiremock or testcontainers for external service simulation
- [ ] Tests successful calls
- [ ] Tests error responses
- [ ] Tests timeouts
- [ ] Tests retry logic
- [ ] Verifies correct API calls are made
- [ ] Tests data transformation

---

## 3. Test Coverage Requirements

### By Layer

| Layer | Minimum Coverage | Target Coverage | Priority |
|-------|-----------------|-----------------|----------|
| Domain/Business Logic | 85% | 95%+ | **CRITICAL** |
| Application Services | 70% | 85%+ | **HIGH** |
| Repositories | 70% | 80%+ | **HIGH** |
| Controllers | 60% | 75%+ | **MEDIUM** |
| Adapters | 60% | 75%+ | **MEDIUM** |
| Utilities | 70% | 85%+ | **HIGH** |

### Overall Project Goals

- **Current**: ~3% (as of Feb 16, 2026)
- **Year 1 Target**: 50%+
- **Long-term Target**: 70%+

### Enforcement

```bash
# Check coverage locally before committing
mvn clean test jacoco:report

# CI/CD will fail the build if:
# - Overall coverage drops below 20%
# - Domain coverage drops below 85%
```

---

## 4. Test Naming Convention

### Method Names

Use clear, behavior-focused names:

```java
// ✅ Good: Describes behavior and expected outcome
@Test
public void shouldCalculatePaymentWithStudentDiscount() { }

@Test
public void shouldThrowExceptionWhenStudentNotFound() { }

@Test
public void shouldReturnHttpNotFoundWhenResourceDoesNotExist() { }

@Test
public void shouldProcessPaymentSuccessfullyWhenGatewayIsAvailable() { }

// ❌ Avoid: Generic or unclear names
@Test
public void testPayment() { }

@Test
public void test1() { }

@Test
public void paymentTest() { }

@Test
public void processPayment() { }  // Sounds like real method
```

### Using @DisplayName

```java
@Test
@DisplayName("Should calculate monthly payment correctly when student has discount")
public void calculatePaymentWithDiscount() { }

// This appears in test reports and is more readable than method names
```

---

## 5. Mocking & Test Doubles

### When to Use Mocks

✅ **DO mock:**
- External APIs (Paypal, Sendgrid, etc.)
- Database calls (in integration tests)
- Time-dependent code (dates, clocks)
- Random/non-deterministic behavior

❌ **DON'T mock:**
- Domain objects (use real instances)
- Business logic (would not test actual logic)
- Objects you're testing (circular dependency)

### Mocking Patterns

```java
// ✅ Good: Mock interface (port)
@Test
public void testWithMock() {
    PaymentGateway gateway = mock(PaymentGateway.class);
    when(gateway.process(any())).thenReturn(success());
    
    PaymentService service = new PaymentService(gateway);
    PaymentResponse result = service.processPayment("123", money(100));
    
    assertTrue(result.isSuccessful());
    verify(gateway).process(any());  // Verify interaction
}

// ❌ Bad: Mocking what you're testing
@Test
public void testWithBadMock() {
    PaymentService service = mock(PaymentService.class);  // DON'T DO THIS
    when(service.processPayment(any(), any())).thenReturn(success());
    
    PaymentResponse result = service.processPayment("123", money(100));
    assertTrue(result.isSuccessful());
}
```

### Test Fixtures

```java
// Create reusable test data
public class PaymentTestFixtures {
    
    public static Student createStudent() {
        return Student.builder()
            .id("test-student-123")
            .name("Test Student")
            .email("test@example.com")
            .status(StudentStatus.ACTIVE)
            .build();
    }
    
    public static PaymentRequest createPaymentRequest() {
        return PaymentRequest.builder()
            .studentId("test-student-123")
            .amount(Money.of(100))
            .method(PaymentMethod.CREDIT_CARD)
            .build();
    }
}

// Usage
@Test
public void testPayment() {
    Student student = PaymentTestFixtures.createStudent();
    PaymentRequest request = PaymentTestFixtures.createPaymentRequest();
    
    // Test code...
}
```

---

## 6. Parameterized Tests

For testing multiple scenarios:

```java
@ParameterizedTest
@CsvSource({
    "10, 90, 10",      // amount, fee, expected_payment
    "50, 100, 50",
    "0, 100, 0",
    "-50, 100, 100"    // Error case
})
@DisplayName("Should calculate payment correctly")
public void calculatePaymentVariations(int amount, int fee, int expected) {
    Discipline discipline = Discipline.builder().fee(fee).build();
    Student student = Student.builder().balance(amount).build();
    
    int result = calculator.calculate(student, discipline);
    
    assertEquals(expected, result);
}
```

---

## 7. Test Organization

### Arrange-Act-Assert (AAA) Pattern

```java
@Test
public void shouldProcessPayment() {
    // ===== ARRANGE (Setup test data) =====
    String studentId = "123";
    Money amount = Money.of(100);
    Student student = studentRepository.save(
        Student.builder()
            .id(studentId)
            .balance(Money.of(500))
            .build()
    );
    
    // ===== ACT (Execute the action) =====
    PaymentResponse response = paymentService.processPayment(studentId, amount);
    
    // ===== ASSERT (Verify results) =====
    assertTrue(response.isSuccessful());
    assertEquals("SUCCESS", response.getStatus());
    
    Payment saved = paymentRepository.findById(response.getTransactionId())
        .orElseThrow();
    assertEquals(studentId, saved.getStudentId());
}
```

### Test Class Organization

```java
@DisplayName("Invoice Service Tests")
public class InvoiceServiceTest {
    
    private InvoiceService service;
    private InvoiceRepository repository;
    
    @BeforeEach
    public void setUp() {
        repository = mock(InvoiceRepository.class);
        service = new InvoiceService(repository);
    }
    
    // ========== SUCCESSFUL SCENARIOS ==========
    
    @Test
    @DisplayName("Should generate invoice for active student")
    public void generateInvoiceSuccess() { }
    
    @Test
    @DisplayName("Should include all enrolled disciplines in invoice")
    public void invoiceIncludesAllDisciplines() { }
    
    // ========== ERROR SCENARIOS ==========
    
    @Test
    @DisplayName("Should throw exception when student not found")
    public void generateInvoiceStudentNotFound() { }
    
    @Test
    @DisplayName("Should throw exception when no disciplines enrolled")
    public void generateInvoiceNoDisciplines() { }
    
    // ========== EDGE CASES ==========
    
    @Test
    @DisplayName("Should handle zero-cost disciplines")
    public void invoiceWithZeroCostDiscipline() { }
}
```

---

## 8. Testing Anti-Patterns

### ❌ Don't: Test Implementation Details

```java
// ❌ Bad: Tests internal logic, not behavior
@Test
public void testPrivateMethodCall() {
    Method method = PaymentService.class.getDeclaredMethod("validateAmount");
    method.setAccessible(true);
    method.invoke(service, amount);  // Tests private method directly
}

// ✅ Good: Tests public behavior
@Test
public void shouldRejectNegativeAmount() {
    assertThrows(IllegalArgumentException.class,
        () -> service.processPayment("123", Money.of(-100)));
}
```

### ❌ Don't: Multiple Assertions on Unrelated Things

```java
// ❌ Bad: Tests multiple unrelated behaviors
@Test
public void testEverything() {
    paymentService.processPayment(request);
    studentService.updateBalance(student);
    emailService.sendConfirmation(student);
    // All in one test - hard to understand failures
}

// ✅ Good: One test, one concept
@Test
public void shouldProcessPayment() { }

@Test
public void shouldUpdateStudentBalance() { }

@Test
public void shouldSendConfirmationEmail() { }
```

### ❌ Don't: Test Framework Features

```java
// ❌ Bad: Testing Spring, not your code
@Test
public void testSpringInjection() {
    assertNotNull(paymentService);  // Never fails if Spring works
    assertNotNull(repository);
}

// ✅ Good: Test your code
@Test
public void shouldProcessPaymentWithInjectedDependencies() {
    PaymentResponse response = paymentService.processPayment(...);
    assertTrue(response.isSuccessful());
}
```

### ❌ Don't: Ignore Test Failures

```java
// ❌ Bad: Silent failure
@Test
public void maybeWorks() {
    try {
        assertSomething();
    } catch (Exception e) {
        // Silently ignore
    }
}

// ✅ Good: Let failures be visible
@Test
public void shouldWork() {
    assertSomething();  // Fail loudly if it doesn't work
}
```

---

## 9. Continuous Integration Testing

### GitHub Actions Example

```yaml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-java@v3
        with:
          java-version: '21'
      
      - name: Run tests
        run: |
          cd backend
          mvn clean test
      
      - name: Generate coverage report
        run: |
          cd backend
          mvn jacoco:report
      
      - name: Check coverage
        run: |
          if [ $(grep -o '<line covered="[0-9]*"' target/site/jacoco/index.html | \
                grep -o '[0-9]*' | awk '{s+=$1} END {print s/NR}') -lt 50 ]; then
            echo "Coverage below 50%"
            exit 1
          fi
      
      - name: Upload coverage
        uses: codecov/codecov-action@v3
        with:
          file: ./backend/target/site/jacoco/jacoco.xml
```

---

## 10. Test Maintenance

### Refactoring Tests

When you refactor production code, update tests:

```java
// If you rename a method
public Money calculateMonthlyAmount() { }  // was: calculatePayment()

// Update tests
@Test
public void shouldCalculateMonthlyAmountCorrectly() { }  // was: shouldCalculatePaymentCorrectly
```

### Removing Dead Tests

Delete tests for removed functionality:

```bash
# When ProductService.deprecated() is removed
# Delete: ProductServiceTest.testDeprecated()
```

### Keeping Tests DRY

Extract common setup:

```java
public abstract class BasePaymentServiceTest {
    
    protected PaymentService service;
    protected PaymentGateway gateway;
    protected StudentRepository repository;
    
    @BeforeEach
    public void setUpBase() {
        gateway = mock(PaymentGateway.class);
        repository = mock(StudentRepository.class);
        service = new PaymentService(gateway, repository);
    }
}

// Extend base class
public class PaymentServiceTest extends BasePaymentServiceTest {
    // Reuse setup from base
}
```

---

## 11. Testing Checklist for Code Review

When reviewing code, verify:

- [ ] All new public methods have tests
- [ ] Bug fixes include regression tests
- [ ] Tests follow naming convention (clear names, `@DisplayName`)
- [ ] Tests use AAA pattern (Arrange-Act-Assert)
- [ ] No mock abuse (only mock external dependencies)
- [ ] No test for framework features
- [ ] Coverage >= project minimum for changed code
- [ ] Tests pass locally before PR submission
- [ ] Integration tests clean up data (`@Transactional`)
- [ ] Flaky tests are fixed or documented

---

## 12. Resources & References

- [JUnit 5 User Guide](https://junit.org/junit5/docs/current/user-guide/)
- [Mockito Documentation](https://javadoc.io/doc/org.mockito/mockito-core/latest/org/mockito/Mockito.html)
- [Spring Boot Testing](https://spring.io/guides/gs/testing-web/)
- [Test-Driven Development](https://en.wikipedia.org/wiki/Test-driven_development)
- [JaCoCo Coverage](https://www.eclemma.org/jacoco/)
- [XUnit Patterns](http://xunitpatterns.com/)

---

**Last Updated**: February 16, 2026  
**Status**: Active  
**Maintainer**: Development Team
