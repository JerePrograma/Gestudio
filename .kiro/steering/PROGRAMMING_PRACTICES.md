# Programming Practices & Code Quality Standards

> Historical supporting guidance. `AGENTS.md` takes precedence for Gestudio.

**Effective Date:** February 16, 2026  
**Scope:** Gestudio Java backend and code changes
**Owner:** Development Team

---

## 1. KISS Principle (Keep It Simple, Stupid)

### Core Rules

✅ **DO:**
- Write the simplest solution that solves the problem
- Avoid over-engineering and premature optimization
- Use straightforward control flow (if/else over complex ternary operators)
- Prefer explicit over implicit

❌ **DON'T:**
- Create unnecessary abstractions
- Use advanced features when simple ones work
- Over-generalize code for "future use cases"
- Write clever code that requires explanation

### Example: Simple vs. Overcomplicated

**❌ Overcomplicated:**
```java
public Optional<String> processUser(User u) {
    return Optional.ofNullable(u)
        .filter(user -> !user.getName().trim().isEmpty())
        .map(user -> user.getName().substring(0, 1).toUpperCase() 
            + user.getName().substring(1).toLowerCase())
        .or(() -> Optional.of("Unknown"));
}
```

**✅ Simple:**
```java
public String getUserDisplayName(User user) {
    if (user == null || user.getName().isBlank()) {
        return "Unknown";
    }
    return user.getName();
}
```

---

## 2. Code Conciseness

### Guidelines

- **Aim for 20-30 lines per method** (hard limit: 50 lines)
- **Aim for 200-300 lines per class** (hard limit: 500 lines)
- Eliminate verbose loops in favor of streams when it doesn't reduce readability
- Remove commented-out code completely
- Delete unused imports automatically

### Conciseness Checklist

- [ ] Can any conditional be simplified?
- [ ] Are there repeated code blocks that should be extracted?
- [ ] Can this method be split into smaller methods?
- [ ] Are variable declarations close to their use?
- [ ] Is the method name long enough to explain what it does?

### Example: Verbose vs. Concise

**❌ Verbose (45 lines):**
```java
public List<String> getActiveUserEmails(List<User> users) {
    List<String> result = new ArrayList<>();
    for (User user : users) {
        if (user != null) {
            if (user.isActive()) {
                String email = user.getEmail();
                if (email != null && !email.trim().isEmpty()) {
                    result.add(email.toLowerCase());
                }
            }
        }
    }
    return result;
}
```

**✅ Concise (3 lines):**
```java
public List<String> getActiveUserEmails(List<User> users) {
    return users.stream()
        .filter(User::isActive)
        .map(user -> user.getEmail().toLowerCase())
        .collect(Collectors.toList());
}
```

---

## 3. Short Variable Names

### Naming Rules

✅ **Acceptable Short Names (in specific contexts):**
- Loop counters: `i`, `j`, `k` (only in simple loops)
- Stream operations: `u` (for user in `.map(u -> ...)`), `a` (for amounts)
- Boolean predicates: `is...`, `has...`, `can...`, `should...`
- Single-letter generics: `<T>`, `<U>`, `<V>` (standard in Java)

✅ **Descriptive Short Names:**
- `user` instead of `u` in general code
- `amount` instead of `a`
- `email` instead of `e`
- `isActive` instead of `active`

❌ **Avoid These:**
- Non-standard abbreviations: `usr`, `amt`, `em`
- Hungarian notation: `strName`, `intAge`
- Single letters for non-loop variables: `x`, `y`, `z` (unless mathematical context)

### Context Rules

**Loop Counter - Acceptable:**
```java
for (int i = 0; i < students.size(); i++) {
    processStudent(students.get(i));
}
```

**Stream Operation - Acceptable:**
```java
payments.stream()
    .map(p -> p.getAmount() * 1.10)
    .collect(Collectors.toList());
```

**Regular Method - Must be Descriptive:**
```java
// ❌ Wrong
void process(List<S> items) {
    for (S s : items) {
        // ...
    }
}

// ✅ Correct
void processStudents(List<Student> students) {
    for (Student student : students) {
        // ...
    }
}
```

---

## 4. Short Methods

### Method Length Guidelines

| Category | Ideal | Maximum |
|----------|-------|---------|
| Getters/Setters | 1-3 lines | 5 lines |
| Utility methods | 5-10 lines | 20 lines |
| Business logic | 10-20 lines | 50 lines |
| Repository queries | 5-10 lines | 20 lines |

### How to Keep Methods Short

#### 1. Extract Helper Methods
```java
// ❌ Long method (30+ lines)
public PaymentResponse processPayment(PaymentRequest req) {
    // validate request
    // calculate amounts
    // process payment
    // update inventory
    // send notification
    // log transaction
}

// ✅ Short methods with helpers
public PaymentResponse processPayment(PaymentRequest req) {
    validateRequest(req);
    Payment payment = calculateAndProcessPayment(req);
    updateInventory(payment);
    sendNotifications(payment);
    return buildResponse(payment);
}

private void validateRequest(PaymentRequest req) { /* ... */ }
private Payment calculateAndProcessPayment(PaymentRequest req) { /* ... */ }
private void updateInventory(Payment p) { /* ... */ }
private void sendNotifications(Payment p) { /* ... */ }
private PaymentResponse buildResponse(Payment p) { /* ... */ }
```

#### 2. Use Early Returns
```java
// ❌ Nested if (harder to read)
public User findUser(String email) {
    if (email != null && !email.isBlank()) {
        User user = repository.findByEmail(email);
        if (user != null && user.isActive()) {
            return user;
        }
    }
    return null;
}

// ✅ Early returns (clearer intent)
public User findUser(String email) {
    if (email == null || email.isBlank()) {
        return null;
    }
    User user = repository.findByEmail(email);
    if (user == null || !user.isActive()) {
        return null;
    }
    return user;
}
```

#### 3. Separate Concerns with Private Methods
```java
// ✅ Delegate to private methods
public void importStudents(File csvFile) throws IOException {
    List<StudentData> data = parseCSVFile(csvFile);
    List<Student> students = convertToEntities(data);
    validateStudents(students);
    saveStudents(students);
}

private List<StudentData> parseCSVFile(File file) throws IOException { /* ... */ }
private List<Student> convertToEntities(List<StudentData> data) { /* ... */ }
private void validateStudents(List<Student> students) { /* ... */ }
private void saveStudents(List<Student> students) { /* ... */ }
```

---

## 5. Documented Code

### JavaDoc Standards

Every public class, interface, and method **must** have JavaDoc.

#### Class Documentation
```java
/**
 * Service for managing student payments and financial reconciliation.
 * 
 * Handles payment processing, amount calculations, and reconciliation reports.
 * Uses the payment gateway configured in application properties.
 * 
 * @since 1.0
 * @author Development Team
 */
public class PaymentService {
    // ...
}
```

#### Method Documentation
```java
/**
 * Processes a payment request and returns the transaction result.
 * 
 * @param request the payment request containing amount, method, and details
 * @return the payment response with transaction ID and status
 * @throws PaymentException if processing fails or amount is invalid
 * @throws IllegalArgumentException if request is null
 */
public PaymentResponse processPayment(PaymentRequest request) {
    // ...
}
```

#### Complex Logic Comments
```java
public void reconcileMonthlyPayments(Month month) {
    // Query all payments for the month, excluding refunds and adjustments
    // This separate query is needed due to legacy data inconsistencies
    List<Payment> payments = repository.findByMonthExcludingRefunds(month);
    
    // Sort by student ID for batch processing efficiency
    payments.sort(Comparator.comparing(Payment::getStudentId));
    
    // Process in batches to avoid memory issues with large datasets
    processBatchedPayments(payments, BATCH_SIZE);
}
```

### Comment Guidelines

✅ **Good Comments Explain:**
- Why code exists (not what it does)
- Design decisions and trade-offs
- Workarounds for bugs or system limitations
- Non-obvious algorithm choices

❌ **Avoid Comments That:**
- Restate obvious code: `i++; // increment i`
- Explain Java syntax
- Are outdated or deprecated
- Are redundant with method names

### Documentation Format

**Location of inline documentation:**
```java
public class PaymentService {
    
    /**
     * Default payment processing timeout in milliseconds.
     * Must be greater than gateway response time (typically 5-10 seconds).
     */
    private static final int PAYMENT_TIMEOUT_MS = 30_000;
    
    /**
     * Retries failed payment transactions up to this limit before giving up.
     * Accounts for temporary gateway connectivity issues.
     */
    private static final int MAX_PAYMENT_RETRIES = 3;
    
    // ... rest of class
}
```

---

## 6. Follow Java Conventions

### Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Classes | PascalCase | `PaymentService`, `StudentRepository` |
| Interfaces | PascalCase | `PaymentGateway`, `StudentValidator` |
| Methods | camelCase, action verb | `processPayment()`, `validateStudent()` |
| Constants | UPPER_SNAKE_CASE | `MAX_RETRIES`, `DEFAULT_TIMEOUT` |
| Variables | camelCase | `studentList`, `totalAmount` |
| Boolean methods | `is...`, `has...`, `can...` | `isActive()`, `hasPermission()` |
| Packages | lowercase (reverse domain) | `com.gestudio.servicios.pago` |

### Code Style Checklist

- [ ] Use 4-space indentation (not tabs)
- [ ] Opening braces on same line (Java style): `if (x) {`
- [ ] One statement per line
- [ ] Max 120 characters per line
- [ ] Blank line between methods
- [ ] 2 blank lines between inner classes
- [ ] `import` statements grouped and sorted

### Java Best Practices

✅ **DO:**
- Use `final` for variables and classes that won't change
- Use `@Override` annotation when overriding methods
- Use `Objects.requireNonNull()` for null checks in constructors
- Use try-with-resources for file/resource handling
- Use enums for fixed sets of values
- Use `List<T>` instead of raw `ArrayList`

❌ **DON'T:**
- Use raw types: `List` (use `List<String>`)
- Create `List` from arrays with loops (use `Arrays.asList()`)
- Catch generic `Exception` (be specific)
- Suppress warnings without explanation
- Create empty catch blocks

### Example: Proper Java Code

```java
/**
 * Manages student enrollment and academic record.
 */
public final class StudentEnrollment {
    
    private static final int MAX_COURSES_PER_SEMESTER = 6;
    private static final String DEFAULT_STATUS = "ACTIVE";
    
    private final String studentId;
    private final List<Course> enrolledCourses;
    private final EnrollmentStatus status;
    
    public StudentEnrollment(String studentId) {
        this.studentId = Objects.requireNonNull(studentId, "studentId cannot be null");
        this.enrolledCourses = new ArrayList<>();
        this.status = EnrollmentStatus.ACTIVE;
    }
    
    /**
     * Enrolls a student in a course.
     * 
     * @param course the course to enroll in
     * @throws IllegalStateException if student is at course limit
     * @throws IllegalArgumentException if course is null
     */
    public void enrollCourse(Course course) {
        Objects.requireNonNull(course, "course cannot be null");
        
        if (enrolledCourses.size() >= MAX_COURSES_PER_SEMESTER) {
            throw new IllegalStateException(
                "Student has reached maximum courses: " + MAX_COURSES_PER_SEMESTER);
        }
        
        enrolledCourses.add(course);
    }
    
    public int getCourseCount() {
        return enrolledCourses.size();
    }
    
    public boolean isFullyEnrolled() {
        return enrolledCourses.size() == MAX_COURSES_PER_SEMESTER;
    }
}
```

---

## 7. Architecture: Hexagonal / Clean / Ports & Adapters

### Layered Architecture

```
┌─────────────────────────────────────────────┐
│         API Layer (Controllers)              │
│    @RestController, @RequestMapping          │
└────────────────┬────────────────────────────┘
                 │
┌────────────────▼────────────────────────────┐
│       Application Layer (Services)           │
│    Business logic, orchestration             │
└────────────────┬────────────────────────────┘
                 │
┌────────────────▼────────────────────────────┐
│  Domain Layer (Entities, Value Objects)     │
│    Core business rules, no framework deps   │
└────────────────┬────────────────────────────┘
                 │
┌────────────────▼────────────────────────────┐
│    Infrastructure (Repositories, Adapters)  │
│    Database, external services              │
└─────────────────────────────────────────────┘
```

### Hexagonal Architecture Principles

#### 1. **Ports**: Define service interfaces
```java
// Ports (core domain interfaces)
package gestudio.core.ports;

public interface PaymentGateway {  // ← Port (outbound)
    PaymentResult process(PaymentRequest request);
}

public interface StudentRepository {  // ← Port (outbound)
    Optional<Student> findById(String id);
}
```

#### 2. **Adapters**: Implement ports
```java
// Adapters (implementations, external integrations)
package gestudio.infra.adapters;

@Component
public class PaypalPaymentGateway implements PaymentGateway {  // ← Adapter
    @Override
    public PaymentResult process(PaymentRequest request) {
        // Actual Paypal API integration
    }
}

@Repository
public class JpaStudentRepository implements StudentRepository {  // ← Adapter
    // JPA-based implementation
}
```

#### 3. **Application Services**: Domain orchestration (no business logic)
```java
package gestudio.servicios.pago;

@Service
public class PaymentProcessingService {
    
    private final PaymentGateway paymentGateway;  // ← Injected port
    private final StudentRepository studentRepo;   // ← Injected port
    
    public PaymentProcessingService(PaymentGateway gateway, StudentRepository repo) {
        this.paymentGateway = gateway;
        this.studentRepo = repo;
    }
    
    public PaymentResponse processStudentPayment(String studentId, BigDecimal amount) {
        Student student = studentRepo.findById(studentId)
            .orElseThrow(() -> new StudentNotFound(studentId));
        
        PaymentRequest request = PaymentRequest.builder()
            .amount(amount)
            .studentId(studentId)
            .build();
        
        return paymentGateway.process(request);
    }
}
```

#### 4. **Domain Layer**: Pure business logic (no dependencies)
```java
package gestudio.core.domain;

/**
 * Core business logic: payment calculation.
 * No Spring, no infrastructure dependencies.
 */
public class PaymentCalculator {
    
    public BigDecimal calculateMonthlyAmount(Student student, Discipline discipline) {
        BigDecimal baseAmount = discipline.getMonthlyFee();
        BigDecimal discount = student.getApplicableDiscount();
        return baseAmount.subtract(discount);
    }
    
    public List<Payment> calculateMonthlyPayments(
            List<StudentEnrollment> enrollments,
            Month month) {
        return enrollments.stream()
            .map(enrollment -> createPayment(enrollment, month))
            .collect(Collectors.toList());
    }
    
    private Payment createPayment(StudentEnrollment enrollment, Month month) {
        // Pure business logic
    }
}
```

### Package Structure Example

```
src/main/java/gestudio/
├── core/
│   ├── domain/              # Pure business entities
│   │   ├── Student.java
│   │   ├── Payment.java
│   │   └── PaymentCalculator.java
│   └── ports/               # Interfaces (outbound boundaries)
│       ├── PaymentGateway.java
│       ├── StudentRepository.java
│       └── NotificationService.java
│
├── servicios/               # Application services (orchestration)
│   ├── pago/
│   │   ├── PaymentProcessingService.java
│   │   └── PaymentReconciliationService.java
│   └── asistencias/
│       └── AttendanceService.java
│
├── infra/                   # Infrastructure (adapters)
│   ├── adapters/
│   │   └── PaypalPaymentGateway.java
│   ├── repositorios/        # Implementation of ports
│   │   └── JpaStudentRepository.java
│   └── external/
│       ├── EmailNotificationAdapter.java
│       └── SmsNotificationAdapter.java
│
└── controladores/           # Entry points (exposed boundary)
    ├── StudentController.java
    ├── PaymentController.java
    └── AttendanceController.java
```

### Dependency Flow Rule

```
Controllers → Services → Domain → Ports
            ↓           ↓
         Infrastructure (Adapters implement Ports)
```

**Key**: Inner layers (domain, ports) never depend on outer layers. Dependencies flow inward.

---

## 8. Avoid Warnings

### Compiler Warnings

Every Java file should compile **without warnings**.

#### Common Warnings to Eliminate

**Unused imports:**
```java
// ❌ Warning: unused import
import java.util.ArrayList;
import java.util.HashMap;

// ✅ Only import what you use
import java.util.List;
```

**Raw type usage:**
```java
// ❌ Warning: raw use of parameterized class
List students = new ArrayList();

// ✅ Properly parameterized
List<Student> students = new ArrayList<>();
```

**Unchecked casts:**
```java
// ❌ Warning: unchecked cast
Object obj = "test";
String str = (String) obj;  // Only if truly needed

// ✅ Use Optional or instanceof checks
if (obj instanceof String) {
    String str = (String) obj;
}
```

**Deprecated methods:**
```java
// ❌ Warning: deprecated
Date d = new Date();

// ✅ Use modern alternatives
LocalDate d = LocalDate.now();
```

### Maven Configuration for Warnings

Add to pom.xml if not present:
```xml
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-compiler-plugin</artifactId>
    <configuration>
        <source>21</source>
        <target>21</target>
        <showWarnings>true</showWarnings>
        <failOnWarning>false</failOnWarning>
    </configuration>
</plugin>
```

### Eclipse/IntelliJ Configuration

- Enable "Warnings" in Java compiler settings
- Set all warnings to "Error" or "Warning" (not "Ignore")
- Use code cleanup tools regularly

---

## 9. Always Create or Update Tests

### Testing Mandate

✅ **Every feature must have tests:**
- Unit tests for business logic (domain layer)
- Integration tests for services
- Controller tests for API endpoints

### Test Requirements

- **New Feature**: Must include unit tests (minimum 70% coverage)
- **Bug Fix**: Must include test that reproduces the bug, then passes when fixed
- **Code Refactoring**: Existing tests must still pass, no new tests required
- **Deprecated Code Removal**: Must update/remove corresponding tests

### Test Structure

```java
public class PaymentServiceTest {
    
    private PaymentService service;
    private PaymentGateway paymentGateway;
    private StudentRepository studentRepo;
    
    @BeforeEach
    public void setUp() {
        paymentGateway = mock(PaymentGateway.class);
        studentRepo = mock(StudentRepository.class);
        service = new PaymentService(paymentGateway, studentRepo);
    }
    
    @Test
    @DisplayName("Should process payment successfully")
    public void testProcessPaymentSuccess() {
        // Arrange
        Student student = Student.builder().id("123").build();
        when(studentRepo.findById("123")).thenReturn(Optional.of(student));
        
        // Act
        PaymentResponse response = service.processPayment("123", BigDecimal.TEN);
        
        // Assert
        assertNotNull(response);
        assertTrue(response.isSuccessful());
        verify(paymentGateway).process(any());
    }
    
    @Test
    @DisplayName("Should throw exception when student not found")
    public void testProcessPaymentStudentNotFound() {
        // Arrange
        when(studentRepo.findById("999")).thenReturn(Optional.empty());
        
        // Act & Assert
        assertThrows(StudentNotFoundException.class, 
            () -> service.processPayment("999", BigDecimal.TEN));
    }
}
```

### Test Coverage Goals

| Layer | Minimum | Target |
|-------|---------|--------|
| Domain/Business Logic | 90% | 95%+ |
| Services | 70% | 85%+ |
| Controllers | 60% | 75%+ |
| Overall Project | 50% | 70%+ |

---

## 10. Code Review Checklist

Before submitting code, verify:

- [ ] **KISS**: Solution is simple, not over-engineered
- [ ] **Conciseness**: Methods < 50 lines, classes < 500 lines
- [ ] **Naming**: Variables are meaningful, not abbreviated
- [ ] **Methods**: All methods < 50 lines, well-extracted
- [ ] **Documentation**: All public classes/methods have JavaDoc
- [ ] **Comments**: Comments explain "why", not "what"
- [ ] **Conventions**: Follows Java naming and style conventions
- [ ] **Architecture**: Maintains layered/hexagonal separation
- [ ] **Warnings**: No compiler or IDE warnings
- [ ] **Tests**: All features have corresponding tests
- [ ] **Tests Pass**: `mvn clean test` passes 100%
- [ ] **Coverage**: Coverage >= 70% for modified code

---

## 11. Enforcement & Tooling

### Pre-Commit Checks (Recommended)

Add git hooks to prevent committing code that violates standards:

```bash
#!/bin/bash
# .git/hooks/pre-commit

cd backend
mvn clean compile -q
if [ $? -ne 0 ]; then
  echo "Build failed. Commit rejected."
  exit 1
fi

mvn test -q
if [ $? -ne 0 ]; then
  echo "Tests failed. Commit rejected."
  exit 1
fi
```

### Maven Commands

```bash
# Full validation
mvn clean compile test

# Run tests only
mvn test

# Run with coverage report
mvn clean test jacoco:report

# Check for issues
mvn clean compile -Dorg.slf4j.simpleLogger.defaultLogLevel=warn
```

---

## 12. Special Cases & Exceptions

### When Short Variable Names Are Acceptable

1. **Mathematical/Scientific Code**
   ```java
   double result = (a * b) + (c * d);  // Mathematical formula
   ```

2. **Algorithm Implementation**
   ```java
   public int binarySearch(int[] arr, int target) {
       int left = 0, right = arr.length - 1;
       while (left <= right) { /* ... */ }
   }
   ```

3. **Stream Operations with Clear Context**
   ```java
   students.stream()
       .filter(s -> s.isActive())
       .map(s -> s.getGrade())
       .collect(Collectors.toList());
   ```

### When Methods Can Be Longer

1. **SQL/Query Building** (up to 50 lines)
2. **Complex Data Transformation** (up to 50 lines)
3. **Legacy Code Integration** (document why it's necessary)

### When to Suppress Warnings

Only when justified and documented:

```java
@SuppressWarnings("unchecked")  // Necessary for legacy API compatibility
List<Student> students = (List<Student>) legacyMethod();
```

---

## 13. References & Resources

- [Google Java Style Guide](https://google.github.io/styleguide/javaguide.html)
- [Java Code Conventions](https://www.oracle.com/java/technologies/javase/codeconventions-150003.pdf)
- [Clean Code by Robert Martin](https://www.oreilly.com/library/view/clean-code-a/9780136083238/)
- [Hexagonal Architecture](https://alistair.cockburn.us/hexagonal-architecture/)
- [SOLID Principles](https://en.wikipedia.org/wiki/SOLID)
- [JUnit 5 Documentation](https://junit.org/junit5/docs/current/user-guide/)
- [Mockito Documentation](https://javadoc.io/doc/org.mockito/mockito-core/latest/org/mockito/Mockito.html)

---

## 14. Questions & Clarifications

**Q: What if KISS conflicts with design patterns?**
A: KISS wins. Use design patterns only if they reduce complexity, not add it.

**Q: Can I use Lombok to reduce boilerplate?**
A: Yes, but ensure generated code is reviewed. Add JavaDoc to classes using Lombok.

**Q: What about performance optimization?**
A: Write clear code first. Profile before optimizing. Readability > micro-optimization.

**Q: How do I make an exception to these rules?**
A: Document it with `@SuppressWarnings` or inline comments explaining the trade-off.

---

**Last Updated:** February 16, 2026  
**Version:** 1.0  
**Status:** Active
