# Historical implementation tasks: Gestudio membership management system

> Historical snapshot only. It is not the current release checklist.

## Implementation Status Summary

**Current State:**
- ✅ Backend: Spring Boot infrastructure, domain entities, controllers, services, and repositories are mostly implemented
- ✅ Frontend: React pages, components, and API integrations are mostly implemented
- ✅ Database: Schema and migrations are in place via Flyway
- ⚠️ **Action Items:** Bug fixes, feature completion, testing, security hardening, and deployment optimization

**This task list focuses on completing, validating, and optimizing what exists.**

---

## Implementation Plan

- [ ] 1. Authentication & Security Layer Hardening
  - Verify JWT token implementation in AutenticacionControlador and TokenService with proper expiration and signing
  - Implement BCryptPasswordEncoder for password hashing in AutenticacionService
  - Add Spring Security configuration with @EnableWebSecurity and authorize endpoints by role (ADMIN, CAJA, CONSULTA, PROFESOR)
  - Implement CORS configuration to allow frontend origin (http://localhost:3000 dev, https://domain.com prod)
  - Add request validation error handling in TratadorDeErrores to return 400 Bad Request with structured error messages
  - Add rate limiting on POST /auth/login endpoint (max 5 attempts per IP per 15 minutes)
  - Verify all controllers require JWT token in Authorization header (except POST /auth/login)
  - _Requirements: 28.1, 28.2, 28.3, 28.4, 27.1, 27.2_

- [ ] 2. Backend API Validation & Response Standardization
  - Review all Jakarta Validation annotations on entities (@NotNull, @Email, @Min, @Max, @Pattern)
  - Standardize API response format: success responses return 200/201 with data, errors return appropriate status codes with error structure
  - Implement custom exception classes (AlumnoNotFoundException, InscripcionNotFoundException, PagoNotFoundException, etc.)
  - Add global exception handler in TratadorDeErrores to catch and map exceptions to HTTP responses
  - Add DTO classes for request/response mapping (AlumnoDTO, PagoDTO, InscripcionDTO, etc.)
  - Validate business logic: importeInicial and montoPagado relationship (montoPagado + saldoRestante = importeInicial)
  - Test all endpoints with invalid inputs (null required fields, invalid email, negative amounts, etc.)
  - _Requirements: 27.1, 27.2, 27.3, 27.4, 27.5, 27.6_

- [ ] 3. Student (Alumno) Module Completion
  - ✅ AlumnoControlador and services exist; verify CRUD operations (GET /alumnos, GET /alumnos/{id}, POST /alumnos, PUT /alumnos/{id}, DELETE /alumnos/{id})
  - Implement search and filter functionality in GET /alumnos with query parameters: search (by nombre/apellido), filter (activos/inactivos/todos), page, size
  - Verify alumno.cuotaTotal is calculated correctly when student has multiple enrollments (sum of disciplina.valorCuota minus bonificaciones)
  - Verify logical deletion: DELETE sets activo=false and preserves all historical data
  - Implement endpoint to retrieve student debt status and payment history
  - Implement endpoint to retrieve student enrollment history with dates and status
  - Add integration tests for Alumno CRUD operations with database
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 1.10_

- [ ] 4. Discipline (Disciplina) Module Completion
  - ✅ DisciplinaControlador exists; verify CRUD operations
  - Verify disciplina.valorCuota is immutable (changes create new pricing history, not overwrite)
  - Implement DisciplinaHorario management: POST/PUT/DELETE /disciplinas/{id}/horarios with diaSemana, horarioInicio, duracion
  - Verify disciplina.profesor is required and linked correctly
  - Verify disciplina.salon is optional and linked correctly
  - Implement search by nombre and sort by nombre (ascending/descending) in GET /disciplinas
  - Verify claseSuelta and clasePrueba pricing is optional and properly stored
  - Implement endpoint to retrieve active students enrolled in discipline
  - Add integration tests for Disciplina CRUD and DisciplinaHorario management
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9, 2.10_

- [ ] 5. Profesor Module Enhancement
  - ✅ ProfesorControlador exists; verify CRUD operations
  - Verify ProfesorControlador endpoints: GET /profesores, GET /profesores/{id}, POST /profesores, PUT /profesores/{id}, DELETE /profesores/{id}
  - Implement automatic edad calculation from fechaNacimiento (preferably on @PrePersist)
  - Verify profesor.usuario relationship is optional (one-to-one, can be null)
  - Implement ObservacionProfesorControlador: POST /observaciones-profesores, GET /observaciones-profesores?profesor_id={id}
  - Verify disciplinas assigned to profesor are retrievable via GET /profesores/{id}
  - Add integration tests for Profesor and ObservacionProfesor entities
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8_

- [ ] 6. Enrollment (Inscripcion) Module Completion & Mensualidad Auto-Generation
  - ✅ InscripcionControlador and MensualidadControlador exist
  - Verify inscripcion creation: POST /inscripciones triggers automatic monthly fee generation (auto-generate mensualidades for next N months)
  - Implement mensualidad auto-generation service: when inscripcion is created, generate pending mensualidades with estado=PENDIENTE, importeInicial=disciplina.valorCuota, montoAbonado=0
  - Verify inscripcion.bonificacion is applied correctly to generated mensualidades (reduce importeInicial by bonificacion.valorFijo or bonificacion.porcentajeDescuento)
  - Implement endpoint to retrieve enrollments grouped by student with total cost calculations
  - Verify estado transitions: ACTIVA → INACTIVA (set fechaBaja) → FINALIZADA
  - Implement cascading deletion: deleting inscripcion deletes related mensualidades and detallePagos
  - Add integration tests for inscripcion creation with auto-generated mensualidades and bonificacion application
  - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 4.8, 4.9, 4.10_

- [ ] 7. Monthly Fee (Mensualidad) Module Completion & State Tracking
  - ✅ MensualidadControlador exists
  - Verify mensualidad fields: fechaGeneracion, fechaCuota, estado (PENDIENTE/PAGADO/OMITIDO), importeInicial, montoAbonado, importePendiente
  - Implement balance calculation: importePendiente = importeInicial - montoAbonado (invariant validation)
  - Implement estado update logic: when montoAbonado reaches importeInicial, automatically update estado=PAGADO
  - Implement GET /mensualidades with filters: alumno_id, estado (PENDIENTE/PAGADO/OMITIDO), date range
  - Implement PUT /mensualidades/{id} to update estado and track payment date (fechaPago)
  - Verify recargo and bonificacion relationships and their impact on importeInicial
  - Add integration tests for mensualidad payment state transitions
  - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 5.8, 5.9, 5.10_

- [ ] 8. Payment (Pago) Core Module Completion & Balance Calculation
  - ✅ PagoControlador exists; verify all CRUD endpoints
  - Verify pago fields: fecha, importeInicial, montoPagado, saldoRestante, estadoPago (ACTIVO/HISTORICO/ANULADO)
  - Implement invariant validation: montoPagado + saldoRestante = importeInicial (enforce on save and update)
  - Implement saldoRestante auto-calculation on POST /pagos: saldoRestante = importeInicial - montoPagado
  - Implement estadoPago transitions: ACTIVO (initial) → HISTORICO (when saldoRestante = 0) → ANULADO (on cancellation)
  - Implement PUT /pagos/{id} to update montoPagado with automatic saldoRestante recalculation
  - Verify GET /pagos returns payments sorted by most recent first (fecha DESC)
  - Implement relacionadas entity updates: when payment is recorded, update related mensualidades and alumno.deudaPendiente status
  - Add integration tests for payment balance calculations and estado transitions
  - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7, 6.8, 6.9, 6.10_

- [ ] 9. Payment Detail Line Items (DetallePago) Module Completion
  - ✅ DetallePagoControlador exists
  - Verify detallePago fields: descripcionConcepto, aCobrar, tipo (MENSUALIDAD/MATRICULA/CLASE_SUELTA/CLASE_PRUEBA/STOCK_VENTA/OTRO)
  - Implement multi-item payment support: POST /pagos accepts pago with array of detallePagos, all persisted together
  - Implement line item types:
    - MENSUALIDAD: links to mensualidad, auto-populates valorBase, importeInicial, importePendiente
    - MATRICULA: links to matricula, updates matricula.pagada=true and fecha_pago
    - CLASE_SUELTA: decrements alumno.creditoAcumulado from detalle amount
    - STOCK_VENTA: links to stock, decrements stock quantity, sets stock.fechaEgreso
    - Other line items: links to concepto/subconcepto, bonificacion, recargo
  - Implement GET /detalles-pago with filters: pago_id, alumno_id
  - Implement cobrado flag tracking (default=false, set=true after collection)
  - Add version field for optimistic locking on DetallePago (prevent concurrent modification)
  - Add integration tests for multi-item payment composition and each line item type
  - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 7.6, 7.7, 7.8, 7.9, 7.10, 7.11, 7.12_

- [ ] 10. Discount (Bonificacion) Module Completion
  - ✅ BonificacionControlador exists
  - Verify bonificacion fields: descripcion, porcentajeDescuento (percentage), valorFijo (optional fixed amount), activo
  - Verify GET /bonificaciones endpoints with pagination/filtering
  - Implement bonificacion application rules: when applied to inscripcion, reduce importeInicial by (porcentaje * valorCuota) OR valorFijo
  - Verify bonificacion is NOT retroactively applied to historical enrollments (only for new enrollments after creation)
  - Verify inactive bonificaciones cannot be assigned to new enrollments
  - Implement endpoint to retrieve list of students currently using each bonificacion
  - Add integration tests for bonificacion application to new enrollments and historical data preservation
  - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 8.6, 8.7, 8.8, 8.9_

- [ ] 11. Surcharge (Recargo) Module Completion
  - ✅ RecargoControlador exists
  - Verify recargo fields: descripcion, porcentaje, valorFijo (optional), diaDelMesAplicacion (day of month to apply)
  - Verify GET /recargos endpoints
  - Implement recargo application: when applied to mensualidad/pago, increase importeInicial by (porcentaje * base) OR valorFijo
  - Implement diaDelMesAplicacion logic: recargos should apply automatically on specified day (if implemented as scheduled task)
  - Verify recargos don't retroactively apply to historical fees
  - Add integration tests for recargo application to fees
  - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5, 9.6_

- [ ] 12. Annual Registration (Matricula) Module Completion
  - ✅ MatriculaControlador exists
  - Verify matricula fields: anio, pagada (default=false), fechaPago, alumno_id
  - Implement auto-generation on student enrollment (optional: create matricula for each school year)
  - Verify matricula payment tracking: when detallePago with tipo=MATRICULA is created, set matricula.pagada=true and fichaaPago
  - Implement GET /matriculas to retrieve all matricula records with filter by alumno_id and año
  - Verify matricula is separated from monthly fees in billing statements
  - Add integration tests for matricula payment tracking
  - _Requirements: 10.1, 10.2, 10.3, 10.4_

- [ ] 13. Daily Cash Management (Caja) Module Completion
  - ✅ CajaControlador exists
  - Verify caja fields: fecha, totalEfectivo, totalTransferencia, observaciones
  - Implement automatic aggregation: when payment is recorded with specific metodoPago (contains "Efectivo" or "Transferencia"), auto-add to daily caja totals
  - Implement GET /cajas with pagination (page, size) to retrieve daily caja records
  - Implement GET /cajas/{id} to retrieve specific day's details with linked pagos
  - Implement caja balance calculation: sum all ingresos minus all egresos for period
  - Verify caja records are linked to actual pagos for reconciliation
  - Add integration tests for caja aggregation and balance calculations
  - _Requirements: 11.1, 11.2, 11.3, 11.4, 11.5, 11.6_

- [ ] 14. Expense Management (Egreso) Module Completion
  - ✅ EgresoControlador exists
  - Verify egreso fields: fecha, monto, metodoPago (optional), observaciones, activo
  - Verify GET /egresos retrieves all expense records with optional filters
  - Implement POST /egresos to record new expenses
  - Verify egreso.activo=false excludes expense from cash flow calculations
  - Implement cash flow calculation: sum active egresos and subtract from ingresos
  - Add integration tests for egreso recording and cash flow impact
  - _Requirements: 12.1, 12.2, 12.3, 12.4, 12.5, 12.6, 12.7_

- [ ] 15. Payment Method (MetodoPago) Module Completion
  - ✅ MetodoPagoControlador exists
  - Verify metodo_pago fields: descripcion, recargo (optional surcharge %), activo
  - Verify GET /metodo-pagos retrieves all payment methods with status
  - Implement recargo application: when metodoPago has recargo value, apply it to pago (if implemented)
  - Verify inactive metodos cannot be used for new payments (validation on POST /pagos)
  - Verify historical payments with previous recargo values are not retroactively modified
  - Add integration tests for metodo pago management
  - _Requirements: 13.1, 13.2, 13.3, 13.4, 13.5, 13.6_

- [ ] 16. User & Role Management Module Completion
  - ✅ UsuarioControlador and RolControlador exist
  - Verify usuario fields: nombreUsuario (unique), contrasena (hashed), rol_id, activo
  - Implement GET /usuarios to retrieve all user accounts
  - Implement POST /usuarios with password hashing (BCryptPasswordEncoder)
  - Verify password is never logged or exposed in responses
  - Implement PUT /usuarios/{id} to update username and rol assignment
  - Verify DELETE /usuarios/{id} sets activo=false (logical deletion)
  - Implement GET /roles to retrieve all role definitions
  - Verify rol.descripcion is used to generate Spring Security GrantedAuthority with pattern "ROLE_{descripcion}"
  - Implement role-based endpoint access control:
    - ADMIN: full access to all endpoints
    - CAJA: /pagos, /cajas, /egresos, /metodo-pagos (write), /alumnos, /inscripciones, /mensualidades (read-only)
    - CONSULTA: all endpoints (read-only)
    - PROFESOR: /asistencias-mensuales, /asistencias-diarias, /observaciones-profesores (write), /alumnos, /inscripciones (read-only)
  - Add integration tests for user authentication and role-based authorization
  - _Requirements: 14.1, 14.2, 14.3, 14.4, 14.5, 14.6, 28.1, 28.2, 28.3, 28.4, 28.5, 28.6_

- [ ] 17. Classroom (Salon) Module Management
  - ✅ SalonControlador exists
  - Verify salon fields: nombre (required), descripcion (optional)
  - Verify GET /salones retrieves all classrooms
  - Verify disciplina.salon relationship is optional (many disciplines can use one salon over time)
  - Add integration tests for salon management
  - _Requirements: 16.1, 16.2, 16.3, 16.4, 16.5_

- [ ] 18. Concept & SubConcept Management
  - ✅ ConceptoControlador and SubConceptoControlador exist
  - Verify subconcepto fields: descripcion
  - Verify concepto fields: descripcion, precio, subConcepto_id (foreign key)
  - Verify hierarchical structure in responses: subConcepto > concepto
  - Verify concepto is used in detallePago line items for itemized billing
  - Add integration tests for concept hierarchy management
  - _Requirements: 17.1, 17.2, 17.3, 17.4, 17.5_

- [ ] 19. Stock Management Module Completion
  - ✅ StockControlador exists
  - Verify stock fields: nombre, precio, stock (quantity), codigoBarras (optional), fechaIngreso, fechaEgreso, requiereControlDeStock (optional), activo
  - Verify GET /stocks retrieves all stock items with infinite scroll pagination
  - Implement stock reduction on sale: when detallePago with tipo=STOCK_VENTA references stock, decrement quantity and set fechaEgreso
  - Verify inactive stock or quantity=0 prevents new sales (validation on detallePago creation)
  - Implement GET /stocks/{id} with current quantity and entry/exit dates
  - Add integration tests for stock sales and quantity tracking
  - _Requirements: 18.1, 18.2, 18.3, 18.4, 18.5, 18.6, 18.7, 18.8_

- [ ] 20. Attendance Tracking Module Completion
  - ✅ AsistenciaMensualControlador and AsistenciaDiariaControlador exist
  - Verify asistencia_mensual fields: mes, anio, disciplina_id
  - Implement auto-generation of asistenciaAlumnoMensual: when asistencia_mensual is created, generate record for each enrolled student (active inscripciones in that discipline)
  - Verify asistencia_diaria fields: fecha, estado (PRESENTE/AUSENTE/JUSTIFICADO), asistenciaAlumnoMensual_id
  - Implement asistencia_alumno_mensual observacion field for teacher notes
  - Verify GET /asistencias-mensuales/{id} retrieves monthly sheet with all student records and daily attendance
  - Implement attendance state management: add/remove students when inscripcion estado changes (ACTIVA/INACTIVA)
  - Add integration tests for attendance sheet generation and daily recording
  - _Requirements: 19.1, 19.2, 19.3, 19.4, 19.5, 19.6, 19.7_

- [ ] 21. Notification System Implementation
  - ✅ NotificacionControlador exists
  - Verify notificacion fields: usuarioId, tipo (CUMPLEANOS/ALERTA/MENSAJE), mensaje, fechaCreacion, leida (default=false)
  - Implement notification creation on key events:
    - CUMPLEANOS: when student or professor birthday is detected
    - ALERTA: on system errors or critical events
  - Implement GET /notificaciones with optional leida filter (retrieve unread notifications)
  - Implement PUT /notificaciones/{id} to mark notification as read (update leida=true)
  - Consider scheduled task for birthday detection (optional enhancement)
  - Add integration tests for notification creation and retrieval
  - _Requirements: 20.1, 20.2, 20.3, 20.4, 20.5_

- [ ] 22. Frontend Module Alignment & Integration
  - ✅ AlumnosPagina, PagosPagina, DisciplinasPagina, etc. exist
  - Verify all Page components fetch data from correct API endpoints with proper error handling
  - Verify infinite scroll implementation on all list pages (AlumnosPagina, PagosPagina, DisciplinasPagina, StocksPagina, etc.)
  - Verify search functionality works correctly for each module (by name, ID, etc.)
  - Verify filter functionality (active/inactive, status, date range where applicable)
  - Verify sort functionality (ascending/descending by sortable columns)
  - Verify form validation on all creation/edit forms (required fields, email format, numeric ranges)
  - Verify error handling and user-friendly error messages (toasts for success/error)
  - Verify navigation between modules via Sidebar and React Router
  - Add integration tests for key frontend workflows (E2E tests with Cypress)
  - _Requirements: 21.1, 21.2, 26.1, 26.2, 26.3, 26.4, 26.5, 26.6_

- [ ] 23. Single Class (Clase Suelta) & Trial Class (Clase Prueba) Support
  - Verify disciplina.claseSuelta and disciplina.clasePrueba pricing fields exist
  - Implement single class payment: allow recording detallePago with tipo=CLASE_SUELTA linked to specific student and amount
  - Implement credit accumulation: when clase suelta is paid, increment alumno.creditoAcumulado
  - Implement credit deduction: when student attends clase suelta, decrement alumno.creditoAcumulado
  - Implement trial class: allow recording detallePago with tipo=CLASE_PRUEBA (typically no charge or reduced price)
  - Verify alumno.creditoAcumulado is properly initialized and tracked
  - Add integration tests for single class and trial class payment accounting
  - _Requirements: 24.1, 24.2, 24.3, 24.4, 24.5_

- [ ] 24. Receipt & Invoice Generation (Frontend & Backend)
  - Implement receipt generation logic in PagoControlador: receipt should include payment date, student name, discipline(s), amount, method, receipt number
  - Implement receipt view endpoint: GET /pagos/{id}/recibo that returns printable/downloadable data
  - Implement receipt template on frontend: PagosPagina should provide "View Receipt" or "Print Receipt" action button
  - Implement receipt PDF export (optional: use library like iText or similar for backend PDF generation)
  - Verify receipt includes all detallePagos items with descriptions and amounts
  - Add integration tests for receipt generation and validation
  - _Requirements: 25.1, 25.2, 25.3_

- [ ] 25. Database & ORM Validation
  - Verify Flyway migrations have created all required tables with correct schema
  - Verify all foreign key relationships are properly defined with cascade rules (ON DELETE CASCADE where appropriate)
  - Verify unique constraints are in place (e.g., usuario.nombreUsuario unique, specific detallePago combinations)
  - Verify indexes are created on frequently queried fields (alumno_id, disciplina_id, fecha, estado)
  - Verify Hibernatelisteners execute correctly: @PrePersist for initialization, @PreUpdate for modifications
  - Verify orphanRemoval=true is set correctly on cascading relationships (e.g., Alumno.inscripciones)
  - Test database operations with various data volumes to ensure no N+1 query problems
  - Add database integration tests for all entity relationships
  - _Requirements: 29.1, 29.2, 29.3, 29.4_

- [ ] 26. Docker Containerization & Deployment Configuration
  - Verify backend Dockerfile is correct: FROM openjdk:17-slim, COPY target/gestudio*.jar, ENTRYPOINT for Spring Boot
  - Verify frontend Dockerfile is correct: multi-stage build (npm install, npm run build, nginx serving dist)
  - Verify docker-compose.yml orchestrates backend, frontend, and database services correctly
  - Configure environment variables for dev and prod profiles (SPRING_DATASOURCE_URL, SPRING_DATASOURCE_USERNAME, JWT_SECRET, etc.)
  - Test full docker-compose up workflow: services start, dependencies connect, API responds on :8080, frontend on :80
  - Implement health check endpoints: GET /health should return 200 OK
  - Document Docker quickstart in README.md (how to run docker-compose, expected ports, etc.)
  - _Requirements: 30.1, 30.2, 30.3, 30.4_

- [ ] 27. Comprehensive Testing Suite Implementation
  - Unit Tests:
    - Test PagoService: saldoRestante calculation, montoPagado invariant
    - Test InscripcionService: bonificacion application, mensualidad generation
    - Test MensualidadService: estado transitions, balance calculations
    - Target: ≥80% coverage on all service classes
  - Integration Tests:
    - Test Alumno CRUD with database: create, read, update, logical delete
    - Test Pago with related entities: create with detallePagos, balance updates
    - Test Inscripcion with auto-generated mensualidades and bonificacion application
    - Target: ≥70% coverage on repositories
  - End-to-End Tests (Cypress):
    - Payment recording workflow: create payment, verify balances updated, display receipt
    - Student enrollment workflow: create student, enroll in discipline, verify fees generated
    - Attendance recording: create monthly sheet, mark attendance, verify roll
    - Discount application: apply bonificacion, verify reduced fees
    - Target: ≥50% coverage on critical workflows
  - Security Tests:
    - Invalid JWT: verify 401 Unauthorized
    - Unauthorized access: CAJA user attempts DELETE /alumnos/{id}, verify 403 Forbidden
    - SQL injection: submit malicious input in search, verify no vulnerability
    - XSS prevention: submit HTML/JS in text fields, verify proper escaping
  - Performance Tests:
    - Load test: 100 concurrent users accessing /pagos, verify ≤2sec response
    - Infinite scroll: load 1000+ alumnos, verify ≤200MB memory
    - Report generation: export 1-year payment history for 500+ students, verify ≤30sec
  - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5_

- [ ] 28. Code Quality & Documentation
  - Add JavaDoc comments to all public methods in Services and Controllers
  - Add TypeScript JSDoc comments to all React components and custom hooks
  - Implement consistent code style across backend (Java) and frontend (TypeScript/React)
  - Run static analysis: SpotBugs (backend), ESLint (frontend) to identify code smells
  - Address all critical and high-priority findings
  - Add README.md sections for:
    - Backend setup (requirements, build, run, configuration)
    - Frontend setup (requirements, build, run)
    - Architecture overview and design decisions
    - API documentation (link to postman collection or Swagger)
    - Testing guide (how to run unit, integration, E2E tests)
  - Create API documentation (Swagger/OpenAPI if not already present)
  - _Requirements: None (quality assurance task)_

- [ ] 29. Data Migration & Seeding (Optional)
  - Implement data seeding scripts for development:
    - Seed initial roles (ADMIN, CAJA, CONSULTA, PROFESOR)
    - Seed test users with different roles
    - Seed sample disciplines, professors, students, enrollments
  - Document seeding process in README.md
  - Ensure Flyway migrations don't conflict with seeding
  - _Requirements: None (dev convenience task)_

- [ ] 30. Production Readiness Checklist
  - Verify all environment variables are properly configured for production
  - Verify database connections use parameterized queries (no SQL injection)
  - Verify passwords are hashed (BCryptPasswordEncoder) before storage
  - Verify JWT tokens have appropriate expiration times
  - Verify CORS is configured to allow only production frontend origin
  - Verify HTTPS/TLS is enforced in production (if hosted publicly)
  - Verify logging is configured (not too verbose, sensitive data excluded)
  - Verify error messages don't expose internal system details to clients
  - Verify rate limiting is enabled on authentication endpoints
  - Verify backup and disaster recovery procedures are documented
  - Perform final smoke tests on production-like environment
  - _Requirements: None (deployment task)_

---

## Notes

**Completed Work:**
- Spring Boot 3.x with Spring Data JPA and Spring Security foundation
- 25+ REST Controllers and Services for all major modules
- Domain entity model (Alumno, Disciplina, Inscripcion, Pago, Mensualidad, and 20+ related entities)
- React frontend with 20+ functional component pages
- Flyway database migrations and schema setup
- Basic CRUD operations for most entities

**Key Dependencies:**
- Tasks 1-2 (Auth & Validation) enable all other tasks
- Tasks 3-7 (core modules) can progress in parallel
- Task 8 (Payment) depends on Tasks 5-7 (enrollments and fees)
- Task 9 (Payment Details) depends on Task 8
- Task 22 (Frontend) depends on completion of Tasks 1-21 (backend)
- Task 23-25 can progress in parallel after Task 9
- Tasks 26-30 (deployment, testing, documentation) can begin after Tasks 1-25

**Testing Strategy:**
- Start with unit tests on critical business logic (payment calculations, balance tracking)
- Follow with integration tests on entity relationships and persistence
- Conclude with E2E tests on complete workflows (payment recording to receipt generation)
- Security tests should be run throughout development, especially before each release

**Expected Timeline (relative to current state):**
- Weeks 1-2: Tasks 1-2 (Auth & Validation) + verify existing implementations
- Weeks 2-4: Tasks 3-9 (Core modules) + parallel frontend alignment (Task 22)
- Weeks 4-5: Tasks 10-21 (Remaining modules) + feature completion
- Weeks 5-6: Tasks 23-25 (Advanced features) + comprehensive testing (Task 27)
- Weeks 6-7: Tasks 26-30 (Deployment, documentation, production readiness)
