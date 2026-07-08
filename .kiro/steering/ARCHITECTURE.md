# Architecture Decisions & Design Patterns

**Effective Date:** February 16, 2026  
**Scope:** All backend code in Le Dance project  
**Owner:** Development Team

---

## 1. Architecture Overview

Le Dance uses **Hexagonal (Ports & Adapters) Architecture** combined with **Clean Architecture** principles.

### Core Structure

```
External World (REST Clients, Databases, External APIs)
        ↓
    Adapters (Controllers, Repositories)
        ↓
    Application Services (Orchestration)
        ↓
    Domain Layer (Business Logic)
        ↓
    Ports (Interfaces)
        ↓
    Adapters (Implementations)
        ↓
External World
```

---

## 2. Layering Rules

### Layer Responsibilities

#### 1. **Domain Layer** (No Dependencies)
- **Package**: `gestudio.core.domain.*`
- **Examples**: `Student`, `Payment`, `Enrollment`
- **Rules**:
  - Domain classes are **pure Java** (no Spring annotations)
  - No database/persistence logic
  - No HTTP/REST logic
  - All business rules live here
  - Testable in unit tests (no mocks needed for dependencies)

#### 2. **Ports Layer** (Defines Contracts)
- **Package**: `gestudio.core.ports.*`
- **Examples**: `StudentRepository`, `PaymentGateway`, `NotificationService`
- **Rules**:
  - These are **interfaces** defining boundaries
  - No implementation
  - Define what external systems the domain needs
  - Should be simple and focused

#### 3. **Application Services** (Orchestration Only)
- **Package**: `gestudio.servicios.*`
- **Examples**: `PaymentService`, `StudentEnrollmentService`
- **Rules**:
  - Contain **no business logic** (that's in domain)
  - Orchestrate domain objects and ports
  - Handle transactions and error handling
  - Should be thin (delegate to domain)

#### 4. **Infrastructure/Adapters** (Implementations)
- **Packages**: 
  - `gestudio.infra.repositorios.*` (Port implementations)
  - `gestudio.infra.adapters.*` (External integrations)
- **Examples**: `JpaStudentRepository`, `PaypalPaymentGateway`
- **Rules**:
  - Implement ports
  - Contain database/framework-specific code
  - May use Spring annotations
  - Testable with integration tests

#### 5. **Controllers/API** (Entry Points)
- **Package**: `gestudio.controladores.*`
- **Examples**: `PaymentController`, `StudentController`
- **Rules**:
  - Receive HTTP requests
  - Validate input
  - Call services
  - Return HTTP responses
  - Minimal logic (validation only)

### Dependency Rules

```
✅ Dependencies flow INWARD:
   Controllers → Services → Domain ← Ports
   Adapters implement Ports

❌ NEVER:
   - Domain depends on Services
   - Domain depends on Controllers
   - Domain depends on Framework
   - Services depend on Controllers
   - Controllers pass entities to Services
```

---

## 3. Design Patterns & When to Use

### Service Pattern (Already Used)

```java
// Orchestration service
@Service
public class PaymentService {
    
    private final PaymentGateway gateway;
    private final StudentRepository repo;
    
    public PaymentResponse processPayment(String studentId, BigDecimal amount) {
        Student student = findStudent(studentId);
        Payment payment = createPayment(student, amount);
        return gateway.process(payment);
    }
}
```

**When to use**: Managing transactions, coordinating multiple operations.

### Repository Pattern (Already Used)

```java
// Port definition
public interface StudentRepository {
    Optional<Student> findById(String id);
    List<Student> findAll();
    void save(Student student);
}

// Implementation
@Repository
public class JpaStudentRepository implements StudentRepository {
    // JPA-based implementation
}
```

**When to use**: Abstracting data access layer.

### Factory Pattern

```java
public class PaymentFactory {
    
    public static Payment createMonthlyPayment(Student student, Month month) {
        Discipline discipline = student.getDiscipline();
        BigDecimal amount = calculateMonthlyAmount(discipline);
        return new Payment(student, amount, month);
    }
    
    private static BigDecimal calculateMonthlyAmount(Discipline d) {
        // Business logic
    }
}
```

**When to use**: Complex object creation with business logic.

### Builder Pattern (For DTOs/Rich Objects)

```java
@Builder
public class PaymentRequest {
    private String studentId;
    private BigDecimal amount;
    private String method;
    private String reference;
    
    public PaymentRequest build() {
        validate();
        return new PaymentRequest(studentId, amount, method, reference);
    }
    
    private void validate() {
        Objects.requireNonNull(studentId);
        if (amount.compareTo(ZERO) <= 0) {
            throw new IllegalArgumentException("Amount must be positive");
        }
    }
}
```

**When to use**: Creating objects with multiple optional fields.

### Strategy Pattern

```java
public interface PaymentGateway {
    PaymentResult process(PaymentRequest request);
}

// Different strategies
public class PaypalGateway implements PaymentGateway { /* ... */ }
public class StripeGateway implements PaymentGateway { /* ... */ }
public class ManualGateway implements PaymentGateway { /* ... */ }

// Usage
@Service
public class PaymentService {
    @Autowired
    @Qualifier("paypalGateway")
    private PaymentGateway gateway;
}
```

**When to use**: Different algorithms for the same operation.

### Adapter Pattern (For External Systems)

```java
public interface EmailService {
    void send(EmailMessage message);
}

@Component
public class SendgridEmailAdapter implements EmailService {
    @Override
    public void send(EmailMessage message) {
        // SendGrid integration
    }
}
```

**When to use**: Integrating external systems without coupling domain.

### Value Object Pattern

```java
/**
 * Immutable value object for money.
 * Always together: amount + currency.
 */
public final class Money {
    private final BigDecimal amount;
    private final Currency currency;
    
    public Money(BigDecimal amount, Currency currency) {
        this.amount = Objects.requireNonNull(amount);
        this.currency = Objects.requireNonNull(currency);
    }
    
    public Money add(Money other) {
        if (!this.currency.equals(other.currency)) {
            throw new IllegalArgumentException("Cannot add different currencies");
        }
        return new Money(this.amount.add(other.amount), this.currency);
    }
    
    @Override
    public boolean equals(Object o) {
        // Value-based equality
    }
}
```

**When to use**: Grouping related values, ensuring they're always valid together.

### Domain Event Pattern

```java
// Event
public class PaymentProcessedEvent {
    private final String studentId;
    private final BigDecimal amount;
    private final LocalDateTime timestamp;
    
    // Immutable
}

// Publisher
@Service
public class PaymentService {
    private final ApplicationEventPublisher eventPublisher;
    
    public void processPayment(Payment p) {
        // Process...
        eventPublisher.publishEvent(new PaymentProcessedEvent(...));
    }
}

// Listener
@Component
public class PaymentNotificationListener {
    
    @EventListener
    public void onPaymentProcessed(PaymentProcessedEvent event) {
        // Send email, update inventory, etc.
    }
}
```

**When to use**: Decoupling side effects from main business logic.

---

## 4. Package Organization

### Standard Package Structure

```
com.gestudio
│
├── core/                          # Domain & Ports (business logic)
│   ├── domain/
│   │   ├── model/                # Entity classes
│   │   │   ├── Alumno.java
│   │   │   ├── Disciplina.java
│   │   │   └── Pago.java
│   │   ├── service/              # Domain services (business logic)
│   │   │   ├── PagoCalculadora.java
│   │   │   └── AsistenciaValidator.java
│   │   └── event/                # Domain events
│   │       └── PagoProcessadoEvent.java
│   │
│   └── ports/                    # Interfaces (outbound boundaries)
│       ├── PagoRepositorio.java
│       ├── PagoGateway.java
│       └── NotificationService.java
│
├── servicios/                      # Application layer (orchestration)
│   ├── pago/
│   │   ├── PagoService.java
│   │   └── ReconciliationService.java
│   ├── asistencias/
│   │   └── AsistenciaService.java
│   └── alumnos/
│       └── AlumnoService.java
│
├── infra/                          # Infrastructure (adapters)
│   ├── repositorios/              # Port implementations
│   │   ├── JpaPagoRepositorio.java
│   │   ├── JpaAlumnoRepositorio.java
│   │   └── ...
│   ├── adapters/                  # External integrations
│   │   ├── PaypalPagoGateway.java
│   │   ├── SendgridEmailAdapter.java
│   │   └── TwilioSmsAdapter.java
│   └── config/                    # Infrastructure configuration
│       ├── PersistenceConfig.java
│       └── SecurityConfig.java
│
├── controladores/                  # Entry points
│   ├── PagoController.java
│   ├── AlumnoController.java
│   └── AsistenciaController.java
│
├── dto/                            # Data transfer objects
│   ├── PagoRequest.java
│   ├── AlumnoResponse.java
│   └── ...
│
├── entidades/                      # JPA entities (mirror of domain)
│   ├── AlumnoEntity.java
│   ├── PagoEntity.java
│   └── ...
│
└── config/                         # Global configuration
    ├── SecurityConfig.java
    └── ApplicationConfig.java
```

### Naming Conventions by Layer

| Layer | Package | Class Suffix | Example |
|-------|---------|-------------|---------|
| Domain | `core.domain` | (none) | `Student`, `Payment` |
| Ports | `core.ports` | (none) | `StudentRepository`, `PaymentGateway` |
| Services | `servicios.*` | `Service` | `PaymentService` |
| Repositories | `infra.repositorios` | `Repository` | `JpaStudentRepository` |
| Adapters | `infra.adapters` | (varies) | `PaypalPaymentGateway` |
| Controllers | `controladores` | `Controller` | `PaymentController` |
| DTOs | `dto` | `Request`, `Response` | `PaymentRequest`, `StudentResponse` |

---

## 5. Domain-Driven Design (DDD) Principles

### Ubiquitous Language

Use consistent business terminology across code, tests, and documentation.

**Example**: Le Dance Domain Language
- "Student" (Alumno)
- "Discipline" (Disciplina)
- "Payment" (Pago)
- "Monthly Fee" (Cuota Mensual)
- "Enrollment" (Inscripción)
- "Attendance Record" (Registro de Asistencia)

```java
// ✅ Good: Uses ubiquitous language
public class StudentEnrollment {
    private Student student;
    private Discipline discipline;
    private List<AttendanceRecord> records;
    
    public MonthlyFee calculateMonthlyFee() { /* ... */ }
    public void recordAttendance(AttendanceRecord record) { /* ... */ }
}

// ❌ Bad: Mixing technical and business terms
public class EnrollmentEntity {
    private User u;
    private Subject s;
    private List<Attendance> a;
    
    public BigDecimal calc() { /* ... */ }
    public void add(Attendance x) { /* ... */ }
}
```

### Aggregate Pattern

Group related objects into aggregates. Access through aggregate root.

```java
/**
 * Aggregate: Student with all related data.
 * StudentEnrollment is the aggregate root.
 */
public class StudentEnrollment {
    
    private String studentId;              // Aggregate ID
    private Student student;                // Root entity
    private List<EnrolledDiscipline> disciplines;  // Child entities
    private List<PaymentRecord> payments;   // Child entities
    
    /**
     * External access through root only.
     * Cannot access EnrolledDiscipline directly.
     */
    public void addDiscipline(Discipline d) {
        this.disciplines.add(new EnrolledDiscipline(d));
    }
    
    public Money calculateTotalFees() {
        return disciplines.stream()
            .map(EnrolledDiscipline::getMonthlyFee)
            .reduce(Money.ZERO, Money::add);
    }
}
```

### Domain Events

Publish domain events for important state changes.

```java
public class PaymentReceived {
    private final String studentId;
    private final Money amount;
    private final LocalDateTime receivedAt;
    
    // Domain logic triggered by event
    public void notifyStudent() { /* ... */ }
    public void updateInventory() { /* ... */ }
    public void generateReceipt() { /* ... */ }
}

@Service
public class PaymentService {
    public void recordPayment(Payment p) {
        payment.markAsReceived();
        // Event published automatically
        applicationEventPublisher.publishEvent(
            new PaymentReceivedEvent(payment));
    }
}
```

---

## 6. SOLID Principles Application

### S - Single Responsibility Principle

```java
// ❌ Wrong: Multiple responsibilities
public class PaymentService {
    public void processPayment(Payment p) { /* ... */ }
    public void sendEmail(String to, String subject) { /* ... */ }
    public void updateDatabase(Payment p) { /* ... */ }
    public void logTransaction(Payment p) { /* ... */ }
}

// ✅ Correct: Each class has one reason to change
@Service
public class PaymentService {
    public void processPayment(Payment p) {
        // Payment processing only
    }
}

@Service
public class EmailService {
    public void sendPaymentConfirmation(Payment p) { /* ... */ }
}

@Component
public class PaymentLogger {
    public void logTransaction(Payment p) { /* ... */ }
}
```

### O - Open/Closed Principle

```java
// ✅ Open for extension, closed for modification
public interface PaymentGateway {
    PaymentResult process(Payment payment);
}

// Can add new payment methods without changing existing code
public class PaypalGateway implements PaymentGateway { }
public class StripeGateway implements PaymentGateway { }
public class ManualGateway implements PaymentGateway { }
```

### L - Liskov Substitution Principle

```java
// ✅ All Payment Gateways work the same way
PaymentGateway gateway = getGateway();  // Could be Paypal, Stripe, Manual
PaymentResult result = gateway.process(payment);  // Works regardless of type
```

### I - Interface Segregation Principle

```java
// ❌ Fat interface
public interface PaymentRepository {
    void save(Payment p);
    void update(Payment p);
    void delete(Payment p);
    Payment findById(String id);
    List<Payment> findAll();
    List<Payment> findByStudent(String studentId);
    List<Payment> findByMonth(Month m);
    BigDecimal sumByMonth(Month m);
}

// ✅ Segregated interfaces
public interface PaymentRepository {
    void save(Payment p);
    Payment findById(String id);
}

public interface PaymentReportRepository {
    List<Payment> findByStudent(String studentId);
    List<Payment> findByMonth(Month m);
    BigDecimal sumByMonth(Month m);
}
```

### D - Dependency Inversion Principle

```java
// ❌ High-level depends on low-level
public class PaymentService {
    private PaypalGateway paypal = new PaypalGateway();  // Concrete impl
    
    public void process(Payment p) {
        paypal.charge(p.getAmount());
    }
}

// ✅ Both depend on abstraction
public class PaymentService {
    private PaymentGateway gateway;  // Interface
    
    public PaymentService(PaymentGateway gateway) {
        this.gateway = gateway;
    }
}
```

---

## 7. Exception Handling Strategy

### Exception Hierarchy

```
Exception
├── CheckedException (Reserved by Java)
│   └── IOException, SQLException, etc.
│
└── RuntimeException
    ├── BusinessException (Domain exceptions - expected)
    │   ├── StudentNotFoundException
    │   ├── InsufficientFundsException
    │   ├── InvalidPaymentAmountException
    │   └── EnrollmentLimitExceededException
    │
    └── TechnicalException (Infrastructure/System issues)
        ├── PaymentGatewayException
        ├── DatabaseException
        └── ExternalServiceException
```

### Business Exceptions (Expected)

```java
// ✅ Domain exceptions for business logic
public class StudentNotFoundException extends RuntimeException {
    public StudentNotFoundException(String studentId) {
        super("Student not found: " + studentId);
    }
}

public class InsufficientFundsException extends RuntimeException {
    public InsufficientFundsException(Money required, Money available) {
        super("Insufficient funds. Required: " + required + ", Available: " + available);
    }
}

// Usage in services
@Service
public class PaymentService {
    public void processPayment(String studentId, Money amount) {
        Student student = studentRepository.findById(studentId)
            .orElseThrow(() -> new StudentNotFoundException(studentId));
        
        if (!student.hasSufficientFunds(amount)) {
            throw new InsufficientFundsException(amount, student.getBalance());
        }
    }
}
```

### Error Handling in Controllers

```java
@RestController
@RequestMapping("/payments")
public class PaymentController {
    
    @PostMapping
    public ResponseEntity<?> processPayment(@RequestBody PaymentRequest req) {
        try {
            PaymentResponse response = paymentService.process(req);
            return ResponseEntity.ok(response);
        } catch (StudentNotFoundException e) {
            return ResponseEntity.notFound().build();
        } catch (InsufficientFundsException e) {
            return ResponseEntity.badRequest()
                .body(new ErrorResponse("INSUFFICIENT_FUNDS", e.getMessage()));
        } catch (PaymentGatewayException e) {
            return ResponseEntity.status(SERVICE_UNAVAILABLE)
                .body(new ErrorResponse("SERVICE_UNAVAILABLE", "Payment service temporarily unavailable"));
        }
    }
    
    @ExceptionHandler(TechnicalException.class)
    public ResponseEntity<?> handleTechnical(TechnicalException e) {
        return ResponseEntity.status(INTERNAL_SERVER_ERROR)
            .body(new ErrorResponse("INTERNAL_ERROR", "An unexpected error occurred"));
    }
}
```

---

## 8. Data Flow Best Practices

### Never Pass Entities Across Service Boundaries

```java
// ❌ Wrong: Raw entity passed across layers
@RestController
public class StudentController {
    @GetMapping("/{id}")
    public Student getStudent(@PathVariable String id) {
        return studentService.findById(id);  // Returns entity directly
    }
}

// ✅ Correct: Map to DTO at boundary
@RestController
public class StudentController {
    @GetMapping("/{id}")
    public StudentResponse getStudent(@PathVariable String id) {
        Student student = studentService.findById(id);
        return StudentMapper.toResponse(student);
    }
}
```

### DTO Structure

```java
// Request DTO (what API accepts)
@Data
@Builder
public class PaymentRequest {
    private String studentId;
    private BigDecimal amount;
    private String method;  // Simple types only
}

// Response DTO (what API returns)
@Data
public class PaymentResponse {
    private String transactionId;
    private String status;
    private LocalDateTime processedAt;
}

// Mapper (conversion)
public class PaymentMapper {
    
    public static PaymentDomain toDomain(PaymentRequest dto) {
        return new PaymentDomain(dto.getStudentId(), dto.getAmount());
    }
    
    public static PaymentResponse toResponse(PaymentDomain domain) {
        return new PaymentResponse(
            domain.getId(),
            domain.getStatus().toString(),
            domain.getProcessedAt()
        );
    }
}
```

---

## 9. Transaction & Concurrency

### Transaction Scope

```java
// ✅ Transaction at service level
@Service
public class PaymentService {
    
    @Transactional  // Spring manages transaction
    public PaymentResponse processPayment(String studentId, BigDecimal amount) {
        // All DB operations here are in same transaction
        Student student = studentRepo.findById(studentId).lock();
        Payment payment = createPayment(student, amount);
        studentRepo.save(student);
        paymentRepo.save(payment);
        publishPaymentEvent(payment);
        
        return payment;  // Transaction commits after method returns
    }
}
```

### Optimistic Locking for Concurrency

```java
@Entity
public class Student {
    
    @Id
    private String id;
    
    @Version  // Optimistic lock
    private Long version;
    
    private Money balance;
    
    // JPA automatically increments version on save
    // Detects concurrent updates
}
```

---

## 10. Testing Strategy by Layer

### Unit Tests (Domain/Business Logic)
- **Location**: `src/test/java/com/gestudio/core/domain`
- **Mock**: Nothing (use real objects)
- **Coverage**: 90%+

### Integration Tests (Service + Repository)
- **Location**: `src/test/java/com/gestudio/servicios`
- **Mock**: External services (payment gateways, email)
- **Coverage**: 70%+

### Controller/API Tests
- **Location**: `src/test/java/com/gestudio/controladores`
- **Mock**: Services
- **Coverage**: 60%+

### Example Structure

```java
// Unit test (no mocks)
@DisplayName("Payment Calculator Tests")
public class PaymentCalculatorTest {
    
    private PaymentCalculator calculator = new PaymentCalculator();
    
    @Test
    public void calculateMonthlyPayment() {
        Student student = Student.builder().discount(10).build();
        Discipline discipline = Discipline.builder().fee(100).build();
        
        Money result = calculator.calculateMonthlyAmount(student, discipline);
        
        assertEquals(new Money(90), result);
    }
}

// Integration test (mock external)
@SpringBootTest
public class PaymentServiceTest {
    
    @MockBean
    private PaymentGateway gateway;
    
    @Autowired
    private PaymentService service;
    
    @Test
    public void processPayment() {
        when(gateway.process(any())).thenReturn(successResult());
        
        PaymentResponse response = service.processPayment("123", new Money(100));
        
        assertThat(response).isSuccessful();
    }
}
```

---

## 11. Configuration & Environment Management

### Environment-Specific Configuration

```yaml
# application-dev.properties
spring.datasource.url=jdbc:postgresql://localhost:5432/gestudio_dev
spring.jpa.hibernate.ddl-auto=create-drop
payment.gateway=manual

# application-prod.properties
spring.datasource.url=jdbc:postgresql://prod-db:5432/gestudio
spring.jpa.hibernate.ddl-auto=validate
payment.gateway=paypal
```

### Configuration Classes

```java
@Configuration
@ConditionalOnProperty(name = "payment.gateway", havingValue = "paypal")
public class PaypalConfig {
    
    @Bean
    public PaymentGateway paymentGateway() {
        return new PaypalPaymentGateway(
            environment.getProperty("paypal.api.key"));
    }
}

@Configuration
@ConditionalOnProperty(name = "payment.gateway", havingValue = "manual")
public class ManualPaymentConfig {
    
    @Bean
    public PaymentGateway paymentGateway() {
        return new ManualPaymentGateway();
    }
}
```

---

## 12. Architecture Decision Log (ADL)

Place in project root for important decisions:

```markdown
# ADL - Architecture Decision Log

## ADL-001: Use Hexagonal Architecture
**Date**: 2026-02-16
**Status**: Accepted
**Context**: Need clear separation between business logic and infrastructure
**Decision**: Implement ports & adapters pattern
**Consequences**: Easier testing, better maintainability, potential overhead for small features

## ADL-002: DTO vs Entity Approach
**Date**: 2026-02-16
**Status**: Accepted
**Context**: How to pass data across layers
**Decision**: Always use DTOs at controller boundaries, entities internally
**Consequences**: More classes, but clear contracts and security benefits
```

---

**Last Updated**: February 16, 2026  
**Status**: Active  
**Maintainer**: Development Team
