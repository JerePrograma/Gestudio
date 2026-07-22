# Historical requirements: Gestudio membership management system

> Non-authoritative historical product notes. Current contracts live in the
> code, Flyway migrations, tests, and maintained project documentation.

## Introduction

Gestudio is a comprehensive membership and enrollment management system designed for sports facilities, dance academies, music schools, and similar organizations that operate on a subscription-based model. The system enables administrators to manage student/member records, track disciplinary enrollments, monitor payment status, issue receipts, and maintain daily cash flow records. The platform supports complex concepts such as discounts (bonificaciones), surcharges (recargos), attendance tracking, multiple payment methods, and detailed financial reporting.

---

## Requirements

### Requirement 1: Student/Member Management

**User Story:** As an administrator, I want to manage student/member records with personal information and status tracking, so that I maintain an updated directory of all current and former members.

**Acceptance Criteria:**

1. WHEN a user navigates to the Alumnos (Students) module, THEN the system SHALL display a paginated list of all students with infinite scroll capability.
2. WHEN filtering students by status, THEN the system SHALL show "Activos" (Active), "Inactivos" (Inactive), or "Todos" (All) students.
3. WHEN searching for a student, THEN the system SHALL filter by full name (nombre and apellido) in real-time.
4. WHEN creating a new student, THEN the system SHALL accept: nombre (required), apellido, fechaNacimiento, edad, celular1, celular2, email, documento, cuit, fechaIncorporacion (required), nombrePadres, autorizadoParaSalirSolo, otrasNotas, and initialize activo=true.
5. WHEN a student is created, THEN the system SHALL initialize creditoAcumulado to 0.0 for tracking "clase suelta" (single class) credits.
6. WHEN a student is registered, THEN the system SHALL track deudaPendiente (pending debt) status automatically.
7. WHEN editing a student record, THEN the system SHALL allow modification of all non-critical fields and update cuotaTotal (total fee) if enrolled in multiple disciplines.
8. WHEN a user requests to delete a student, THEN the system SHALL perform logical deletion (mark activo=false) rather than physical deletion to preserve historical records.
9. WHEN marking a student as inactive, THEN the system SHALL set fechaDeBaja and maintain all related inscriptions and payment history.
10. WHEN viewing student details, THEN the system SHALL display: current enrollments, total fee amount (cuotaTotal), pending debt status, accumulated credit, and enrollment history.

---

### Requirement 2: Discipline/Class Management

**User Story:** As an administrator, I want to define and manage disciplines (classes/courses) with pricing, schedules, and instructor assignments, so that I can organize the academy's offerings and track enrollment capacity.

**Acceptance Criteria:**

1. WHEN navigating to Disciplinas, THEN the system SHALL display a searchable, sortable list of all disciplines with infinite scroll.
2. WHEN creating a discipline, THEN the system SHALL require: nombre (required), profesor (required), and valorCuota (required).
3. WHEN defining a discipline, THEN the system SHALL accept optional fields: salon (classroom), claseSuelta price (single class rate), clasePrueba price (trial class rate).
4. WHEN a discipline is created, THEN the system SHALL initialize activo=true.
5. WHEN managing class schedules, THEN the system SHALL allow specification of disciplinaHorarios (day of week, start time, duration).
6. WHEN creating discipline schedules, THEN the system SHALL support diaSemana enum values (Monday through Sunday) with horarioInicio (LocalTime) and duracion (duration in hours).
7. WHEN displaying a discipline, THEN the system SHALL show: assigned professor, current enrollment count, active status, and associated class schedules.
8. WHEN updating valorCuota, THEN the system SHALL preserve historical pricing for previously generated monthlyFees (mensualidades).
9. WHEN a user deletes a discipline, THEN the system SHALL perform logical deletion (activo=false) unless no enrollments reference it.
10. WHEN searching disciplines, THEN the system SHALL filter by nombre and sort in ascending or descending order.

---

### Requirement 3: Professor Management

**User Story:** As a facility manager, I want to register professors, track their information, and monitor their teaching assignments, so that I can manage staff and ensure classes are covered.

**Acceptance Criteria:**

1. WHEN navigating to Profesores, THEN the system SHALL display a list of all professors.
2. WHEN creating a professor profile, THEN the system SHALL require: nombre (required), apellido (required), and assign to discipline(s).
3. WHEN registering a professor, THEN the system SHALL accept: fechaNacimiento, telefono, and edad (auto-calculated).
4. WHEN a professor profile is created, THEN the system SHALL optionally link a Usuario account (one-to-one relationship) for system access.
5. WHEN a professor is assigned to a discipline, THEN the system SHALL establish a one-to-many relationship (profesor ↔ disciplinas).
6. WHEN creating an ObservacionProfesor (observation/note), THEN the system SHALL record: profesor, fecha, and observacion text.
7. WHEN viewing a professor record, THEN the system SHALL display: assigned disciplines, personal information, linked user account (if any), and observation history.
8. WHEN marking a professor as inactive, THEN the system SHALL set activo=false and preserve all historical teaching records.

---

### Requirement 4: Student Enrollment Management

**User Story:** As an enrollment officer, I want to enroll students in disciplines, manage active and inactive enrollments, and track enrollment dates, so that I can maintain accurate class rosters and manage billing for each enrollment.

**Acceptance Criteria:**

1. WHEN navigating to Inscripciones, THEN the system SHALL display all enrollments grouped by student with infinite scroll.
2. WHEN creating an enrollment, THEN the system SHALL require: alumno (required), disciplina (required), and fechaInscripcion (required).
3. WHEN enrolling a student, THEN the system SHALL support optional bonificacion (discount) assignment.
4. WHEN an enrollment is created, THEN the system SHALL initialize estado to ACTIVA.
5. WHEN an enrollment becomes inactive, THEN the system SHALL set fechaBaja and update estado to INACTIVA.
6. WHEN an enrollment is finalized, THEN the system SHALL update estado to FINALIZADA and preserve complete enrollment history.
7. WHEN viewing student enrollments grouped view, THEN the system SHALL display: student name, each discipline enrolled in, monthly fee per discipline, applied discount/bonus, and total cost for all enrollments.
8. WHEN calculating total cost per enrollment, THEN the system SHALL compute: disciplina.valorCuota minus (bonificacion.valorFijo or bonificacion.porcentajeDescuento applied).
9. WHEN enrolling a student in a discipline, THEN the system SHALL auto-generate pending mensualidades (monthly fees) for future billing periods.
10. WHEN searching enrollments, THEN the system SHALL filter by student name and allow sorting.

---

### Requirement 5: Monthly Fee (Mensualidad) Management

**User Story:** As a billing manager, I want to generate, track, and manage monthly fees for each active enrollment, so that I can maintain accurate billing records and identify outstanding balances.

**Acceptance Criteria:**

1. WHEN navigating to Mensualidades, THEN the system SHALL display all monthly fee records.
2. WHEN a mensualidad is generated or manually created, THEN the system SHALL record: fechaGeneracion, fechaCuota (the month/year the fee applies to), and importeInicial.
3. WHEN generating monthly fees, THEN the system SHALL copy the current valorCuota from the related discipline's pricing history.
4. WHEN creating a mensualidad, THEN the system SHALL require: inscripcion, fechaCuota, and estado initialization.
5. WHEN a monthly fee is created, THEN the system SHALL initialize: estado=PENDIENTE, montoAbonado=0.0, and importePendiente=importeInicial.
6. WHEN a payment is applied to a mensualidad, THEN the system SHALL update: montoAbonado (total collected), importePendiente (remaining balance), and fechaPago.
7. WHEN importePendiente reaches 0, THEN the system SHALL update estado to PAGADO.
8. WHEN a monthly fee remains unpaid past its due date, THEN the system SHALL maintain estado=PENDIENTE with appropriate age tracking.
9. WHEN viewing monthly fees for a student, THEN the system SHALL display: enrollment details, fee amount, payment status, overdue indicators, and accumulated balance.
10. WHEN searching monthly fees, THEN the system SHALL filter by student, enrollment, period (month/year), and status (PENDIENTE/PAGADO/OMITIDO).

---

### Requirement 6: Payment and Collection Management

**User Story:** As a cashier, I want to record student payments, issue receipts, track remaining balances, and monitor payment methods, so that I can accurately account for all received funds and identify collection patterns.

**Acceptance Criteria:**

1. WHEN navigating to Pagos, THEN the system SHALL display all payment records with infinite scroll sorted by most recent first.
2. WHEN creating a payment record, THEN the system SHALL require: alumno, fecha (required), monto, importeInicial, and assign a metodoPago (payment method).
3. WHEN registering a payment, THEN the system SHALL initialize: estadoPago=ACTIVO, saldoRestante=importeInicial, montoPagado=0.0.
4. WHEN a payment is recorded, THEN the system SHALL optionally assign a Usuario (cashier/user who processed it).
5. WHEN recording a payment, THEN the system SHALL support optional recargoMetodoPagoAplicado flag to track surcharge application.
6. WHEN a payment is applied, THEN the system SHALL update montoPagado and saldoRestante such that montoPagado + saldoRestante = importeInicial (invariant validation).
7. WHEN saldoRestante equals 0, THEN the system SHALL automatically update estadoPago to HISTORICO.
8. WHEN viewing payment details, THEN the system SHALL display: student name, payment date, amount, method, remaining balance, status, and associated detallePagos (payment detail items).
9. WHEN a payment record is amended, THEN the system SHALL allow updates to fecha, monto, metodoPago, and observaciones until it is marked as ANULADO (cancelled).
10. WHEN cancelling a payment, THEN the system SHALL update estadoPago to ANULADO and preserve original transaction details.

---

### Requirement 7: Payment Detail Line Items

**User Story:** As a billing officer, I want to track detailed line items within each payment, itemizing charges, discounts, surcharges, and stock sales, so that I can generate itemized receipts and understand payment composition.

**Acceptance Criteria:**

1. WHEN a payment is recorded, THEN the system SHALL support multiple detallePagos line items (one-to-many relationship).
2. WHEN creating a detalle pago, THEN the system SHALL require: pago, alumno, descripcionConcepto, and aCobrar (amount to collect).
3. WHEN adding a line item to a payment, THEN the system SHALL support optional references to: concepto, subConcepto, mensualidad, matricula, stock, bonificacion, or recargo.
4. WHEN a line item involves a concepto, THEN the system SHALL record: concepto (required), subConcepto (nested under concepto), and precio.
5. WHEN a line item is a monthly fee charge, THEN the system SHALL link mensualidad and auto-populate: valorBase, importeInicial, importePendiente.
6. WHEN a line item is a yearly matricula charge, THEN the system SHALL link matricula, track payment date (fechaPago), and update matricula.pagada=true.
7. WHEN a line item applies a bonificacion (discount), THEN the system SHALL record the discount and ensure importeInicial is reduced accordingly.
8. WHEN a line item applies a recargo (surcharge), THEN the system SHALL record the surcharge and increase importeInicial accordingly.
9. WHEN a line item includes a stock item, THEN the system SHALL link stock, reduce stock quantity, and update stock.fechaEgreso.
10. WHEN a line item is created, THEN the system SHALL initialize: tipo (TipoDetallePago enum), cobrado=false, and fecha_registro as current timestamp.
11. WHEN tipo=CLASE_SUELTA, THEN the system SHALL deduct from alumno.creditoAcumulado.
12. WHEN viewing a payment's detail items, THEN the system SHALL show: line item description, base values, applied discount/surcharge/rec, final amount due, and collection status.

---

### Requirement 8: Discounts (Bonificaciones)

**User Story:** As a facility manager, I want to define and apply discount programs (partial scholarships, family plans, etc.), so that I can offer flexible pricing and track which students receive discounts.

**Acceptance Criteria:**

1. WHEN navigating to Bonificaciones, THEN the system SHALL display all active and inactive discounts with infinite scroll.
2. WHEN creating a bonificacion, THEN the system SHALL require: descripcion (e.g., "1/2 BECA") and porcentajeDescuento (percentage, e.g., 50 for 50%).
3. WHEN defining a bonificacion, THEN the system SHALL support optional valorFijo (fixed discount amount in currency).
4. WHEN a bonificacion is created, THEN the system SHALL initialize activo=true and optionally capture observaciones.
5. WHEN applying a bonificacion to an inscripcion (enrollment), THEN the system SHALL reduce the inscripcion's effective fee: by porcentajeDescuento percent OR by valorFijo amount, whichever applies.
6. WHEN a bonificacion is used in a detallePago line item, THEN the system SHALL apply the discount to that specific charge.
7. WHEN updating a bonificacion, THEN the system SHALL NOT retroactively modify already-applied discounts to historical enrollments or payments.
8. WHEN a bonificacion is marked inactive, THEN the system SHALL prevent new assignments to new enrollments.
9. WHEN viewing bonificaciones, THEN the system SHALL display: description, discount type/amount, active status, and count of students currently using it.

---

### Requirement 9: Surcharges (Recargos)

**User Story:** As a finance manager, I want to apply payment method surcharges (e.g., credit card fees) and manage penalty charges, so that I can account for additional costs incurred by certain payment methods or late payments.

**Acceptance Criteria:**

1. WHEN navigating to Recargos, THEN the system SHALL display all surcharge definitions.
2. WHEN creating a recargo, THEN the system SHALL require: descripcion, porcentaje (surcharge percentage), and diaDelMesAplicacion (day of month when it applies).
3. WHEN defining a recargo, THEN the system SHALL optionally capture valorFijo (fixed surcharge amount).
4. WHEN a recargo is applied to a payment or mensualidad, THEN the system SHALL increase the amount due by: (porcentaje * base) OR valorFijo.
5. WHEN a recargo's diaDelMesAplicacion arrives, THEN the system SHALL auto-apply to applicable pending fees (if implemented as scheduled task).
6. WHEN viewing recargos, THEN the system SHALL display: description, percentage/fixed amount, application day, and active status.

---

### Requirement 10: Annual Registration/Matrícula Management

**User Story:** As an enrollment manager, I want to track annual registration fees (matrícula) separately from monthly fees, so that I can distinguish between recurring monthly charges and one-time annual registrations.

**Acceptance Criteria:**

1. WHEN a student is enrolled at the beginning of an academic year, THEN the system SHALL create a Matricula record with: alumno, anio, and pagada=false.
2. WHEN a matricula payment is received, THEN the system SHALL update pagada=true and record fechaPago.
3. WHEN viewing a student's record, THEN the system SHALL display matricula status and payment history by year.
4. WHEN generating a billing statement, THEN the system SHALL itemize matricula fees separately from monthly fees.

---

### Requirement 11: Daily Cash Management (Caja)

**User Story:** As a cashier, I want to record daily cash transactions (ingresos from payments and egresos for expenses), track payment methods, and calculate daily balances, so that I can reconcile cash flow and detect discrepancies.

**Acceptance Criteria:**

1. WHEN navigating to Caja, THEN the system SHALL display daily cash records (ingresos - revenue entries).
2. WHEN recording a daily caja entry, THEN the system SHALL capture: fecha (date), totalEfectivo (cash amount), totalTransferencia (bank transfer amount), and observaciones.
3. WHEN a payment is recorded via cash (metodoPago.descripcion includes "Efectivo"), THEN the system SHALL automatically contribute to that day's totalEfectivo.
4. WHEN a payment is recorded via bank transfer (metodoPago.descripcion includes "Transferencia"), THEN the system SHALL automatically contribute to that day's totalTransferencia.
5. WHEN viewing a specific caja day record, THEN the system SHALL display: date, total inflow, payment method breakdown, and linked payment records.
6. WHEN calculating caja balance, THEN the system SHALL sum all ingresos and subtract all egresos for the specified period.

---

### Requirement 12: Expense Management (Egresos)

**User Story:** As a facility manager, I want to record operational expenses, track expense types and amounts, and manage expense documentation, so that I can monitor outflows and maintain financial records.

**Acceptance Criteria:**

1. WHEN navigating to Egresos, THEN the system SHALL display all expense records.
2. WHEN creating an egreso, THEN the system SHALL require: fecha (required) and monto (required).
3. WHEN recording an expense, THEN the system SHALL optionally capture: metodoPago (payment method used), observaciones (description/notes).
4. WHEN an expense is created, THEN the system SHALL initialize activo=true.
5. WHEN viewing egresos, THEN the system SHALL display: date, amount, method, notes, and active status.
6. WHEN calculating cash flow for a period, THEN the system SHALL include all active expenses in calculations.
7. WHEN an expense is marked inactive, THEN the system SHALL exclude it from future cash flow calculations.

---

### Requirement 13: Payment Methods Management

**User Story:** As an administrator, I want to define and manage payment methods, including associated surcharges, so that I can control accepted payment types and track surcharge application.

**Acceptance Criteria:**

1. WHEN navigating to Métodos de Pago, THEN the system SHALL display all payment method definitions.
2. WHEN creating a metodo pago, THEN the system SHALL require: descripcion (e.g., "Efectivo", "Transferencia", "Tarjeta Crédito").
3. WHEN defining a payment method, THEN the system SHALL optionally capture recargo (surcharge percentage or amount).
4. WHEN a payment is recorded with a specific metodoPago, THEN the system SHALL apply the associated recargo (if defined).
5. WHEN updating a metodo pago, THEN the system SHALL NOT retroactively modify historical payments already recorded with the previous surcharge.
6. WHEN marking a metodo pago as inactive, THEN the system SHALL prevent new payments from using that method.

---

### Requirement 14: User and Role Management

**User Story:** As a system administrator, I want to manage user accounts, assign roles with appropriate permissions, and control system access, so that I can ensure security and appropriate access levels for staff.

**Acceptance Criteria:**

1. WHEN navigating to Usuarios, THEN the system SHALL display all user accounts with filtering and sorting.
2. WHEN creating a usuario, THEN the system SHALL require: nombreUsuario (username, required) and contrasena (password, required).
3. WHEN a user account is created, THEN the system SHALL assign a rol (required relationship) and initialize activo=true.
4. WHEN a user logs in, THEN the system SHALL validate: nombreUsuario and contrasena AND retrieve rol-based authorities.
5. WHEN a user is assigned a rol, THEN the system SHALL grant GrantedAuthority permissions with "ROLE_{rol.descripcion}" pattern.
6. WHEN marking a user as inactive, THEN the system SHALL set activo=false and prevent login.

---

### Requirement 15: Role Definitions

**User Story:** As a system administrator, I want to define roles with meaningful descriptions and control permissions by role, so that I can manage access control and ensure staff have appropriate system capabilities.

**Acceptance Criteria:**

1. WHEN navigating to Roles, THEN the system SHALL display all role definitions.
2. WHEN creating a rol, THEN the system SHALL require: descripcion (e.g., "ADMIN", "CAJA", "CONSULTA", "PROFESOR").
3. WHEN a role is created, THEN the system SHALL initialize activo=true.
4. WHEN a role is assigned to a usuario, THEN the system SHALL use its descripcion to generate Spring Security GrantedAuthority.
5. WHEN marking a role as inactive, THEN the system SHALL prevent assignment to new users.

---

### Requirement 16: Classroom (Salón) Management

**User Story:** As a facility manager, I want to register and manage classrooms/studios, so that I can assign classes to specific spaces and track facility usage.

**Acceptance Criteria:**

1. WHEN navigating to Salones, THEN the system SHALL display all classroom records.
2. WHEN creating a salon, THEN the system SHALL require: nombre (required).
3. WHEN defining a classroom, THEN the system SHALL optionally capture descripcion.
4. WHEN assigning a disciplina to a salon, THEN the system SHALL establish many-to-many relationship (one salon can host multiple classes, one class can use multiple salons across time).
5. WHEN viewing a salon, THEN the system SHALL display: name, description, and list of disciplines currently using it.

---

### Requirement 17: Concept and Subconcepto Management

**User Story:** As a billing configuration manager, I want to define billing concepts (categories) and subconcepts, so that I can itemize charges in detallePagos and organize billing categories.

**Acceptance Criteria:**

1. WHEN navigating to Conceptos, THEN the system SHALL display all concept definitions.
2. WHEN creating a concepto, THEN the system SHALL allow: descripcion and reference to subConcepto.
3. WHEN creating a subConcepto, THEN the system SHALL require: descripcion.
4. WHEN a concepto is used in a detallePago line item, THEN the system SHALL reference both concepto and its nested subConcepto.
5. WHEN viewing conceptos, THEN the system SHALL display hierarchical structure: subConcepto > concepto.

---

### Requirement 18: Stock Management

**User Story:** As a facility manager, I want to manage physical inventory such as merchandise, uniforms, or supplies, track stock quantities, and record inflow and outflow dates, so that I can monitor inventory levels and sell items to students.

**Acceptance Criteria:**

1. WHEN navigating to Stocks, THEN the system SHALL display all stock items with infinite scroll.
2. WHEN creating a stock item, THEN the system SHALL require: nombre (required), precio (required), and stock quantity (required).
3. WHEN registering stock, THEN the system SHALL optionally capture: codigoBarras (barcode), requiereControlDeStock (whether it needs tracking), fechaIngreso (entry date).
4. WHEN stock is received, THEN the system SHALL update stock quantity and set fechaIngreso.
5. WHEN stock is sold via a detallePago item, THEN the system SHALL link the stock item, reduce quantity, and set fechaEgreso.
6. WHEN a stock item is created, THEN the system SHALL initialize activo=true.
7. WHEN stock quantity reaches 0 or is marked inactive, THEN the system SHALL prevent new sales of that item.
8. WHEN viewing stock details, THEN the system SHALL display: current quantity, price, entry/exit dates, and control requirements.

---

### Requirement 19: Attendance Tracking (Asistencias)

**User Story:** As an instructor, I want to record daily attendance for each student in a class and generate monthly attendance summaries, so that I can track participation and identify students with poor attendance.

**Acceptance Criteria:**

1. WHEN navigating to Asistencias-Mensuales, THEN the system SHALL display monthly attendance sheets (AsistenciaMensual) grouped by discipline.
2. WHEN creating an asistencia mensual (monthly attendance sheet) for a discipline, THEN the system SHALL capture: mes (month), anio (year), disciplina.
3. WHEN an attendance sheet is created, THEN the system SHALL auto-generate asistenciaAlumnoMensual records for all currently enrolled students (inscripciones in that discipline).
4. WHEN recording daily attendance, THEN the system SHALL create AsistenciaDiaria records with: fecha, estado (PRESENTE, AUSENTE, JUSTIFICADO enum), and link to asistenciaAlumnoMensual.
5. WHEN adding a note for a student's attendance, THEN the system SHALL capture observacion text in the asistenciaAlumnoMensual record.
6. WHEN viewing a monthly attendance sheet, THEN the system SHALL display: discipline name, month/year, and grid of students with attendance status per day.
7. WHEN a student's inscripcion changes estado (from/to ACTIVA), THEN the system SHALL add/remove that student from the monthly attendance sheet.

---

### Requirement 20: Notifications System

**User Story:** As an administrator, I want to receive notifications about important events such as birthdays, alerts, or system messages, so that I can stay informed of key activities.

**Acceptance Criteria:**

1. WHEN the system detects a student or professor birthday, THEN it SHALL create a Notificacion with tipo="CUMPLEANOS".
2. WHEN the system creates a notification, THEN it SHALL record: usuarioId, tipo, mensaje, fechaCreacion, and initialize leida=false.
3. WHEN a user views notifications, THEN the system SHALL display unread notifications (leida=false) with timestamps.
4. WHEN a user reads a notification, THEN the system SHALL update leida=true.
5. WHEN the system encounters an error or exception, THEN it MAY create a Notificacion with tipo="ALERTA" for administrative notification.

---

### Requirement 21: Data Filtering and Search Functionality

**User Story:** As a user, I want powerful search and filtering capabilities across all modules, so that I can quickly find relevant records without scrolling through entire lists.

**Acceptance Criteria:**

1. WHEN searching on any list page (students, disciplines, payments, etc.), THEN the system SHALL provide real-time search by primary identifiers (name, number, etc.).
2. WHEN filtering records, THEN the system SHALL support: status filter (active/inactive), date range filter, and amount range filter where applicable.
3. WHEN sorting columns in a table, THEN the system SHALL sort by selected column in ascending or descending order.
4. WHEN performing searches multiple times, THEN the system SHALL reset pagination/infinite scroll to the first page.

---

### Requirement 22: Data Persistence and Logical Deletion

**User Story:** As an organization, I want to maintain complete audit trails and historical records, so that I can comply with regulatory requirements and analyze historical trends.

**Acceptance Criteria:**

1. WHEN a user deletes any record (student, enrollment, payment, etc.), THEN the system SHALL perform logical deletion (set activo=false) rather than physical deletion.
2. WHEN a record is logically deleted, THEN the system SHALL preserve all associated relationships and historical data.
3. WHEN filtering by status, THEN inactive records shall be excluded from default views unless explicitly filtered.
4. WHEN generating financial reports, THEN the system SHALL include historical records of deleted enrollments and payments for complete accounting.

---

### Requirement 23: Multi-Step Payment Application

**User Story:** As a cashier, I want to apply partial payments to multiple outstanding charges, so that I can flexibly handle payment distributions and partial settlements.

**Acceptance Criteria:**

1. WHEN recording a payment that exceeds a single mensualidad amount, THEN the system SHALL allow selection of multiple mensualidades or charges to partially or fully settle.
2. WHEN applying a payment to multiple detallePagos, THEN the system SHALL create linked detallePago items and update saldoRestante on parent Pago.
3. WHEN a payment montoPagado < saldoRestante, THEN the system SHALL maintain estadoPago=ACTIVO.
4. WHEN a payment montoPagado = importeInicial, THEN the system SHALL update estadoPago=HISTORICO.

---

### Requirement 24: Single Class (Clase Suelta) and Trial Class (Clase Prueba) Support

**User Story:** As a student, I want to attend single classes or take trial classes without a full enrollment, so that I can explore disciplines before committing to a full enrollment.

**Acceptance Criteria:**

1. WHEN a discipline defines claseSuelta pricing, THEN the system SHALL allow recording single-class charges separate from the main inscription.
2. WHEN a student purchases a clase suelta, THEN the system SHALL increment alumno.creditoAcumulado by the paid amount.
3. WHEN a student attends a clase suelta, THEN the system SHALL decrement creditoAcumulado.
4. WHEN a discipline defines clasePrueba pricing, THEN the system SHALL allow recording trial classes (typically free or reduced price).
5. WHEN recording a clase suelta or clasePrueba charge, THEN the system SHALL create a detallePago with tipo=CLASE_SUELTA or tipo=CLASE_PRUEBA.

---

### Requirement 25: Receipt and Invoice Generation

**User Story:** As a cashier, I want to issue receipts/invoices when payments are recorded, so that students have proof of payment and the organization has documentation.

**Acceptance Criteria:**

1. WHEN a payment is finalized, THEN the system SHALL generate a printable/exportable receipt with: payment date, student name, discipline, amount, method, and receipt number.
2. WHEN displaying a payment, THEN the system SHALL provide an action to view or print the receipt.
3. WHEN a receipt is generated, THEN it SHALL include all detallePagos items with descriptions and amounts.

---

### Requirement 26: Frontend User Interface Requirements

**User Story:** As a user, I want an intuitive, responsive web interface for desktop and tablet use, so that I can easily navigate and enter data.

**Acceptance Criteria:**

1. WHEN accessing the system, THEN the web interface SHALL load without errors using React with TypeScript.
2. WHEN using the application on different screen sizes, THEN the layout SHALL be responsive and usable (mobile support is out of scope; focus is desktop/tablet).
3. WHEN performing CRUD operations, THEN the system SHALL provide form validation and user-friendly error messages.
4. WHEN submitting a form, THEN the system SHALL provide visual feedback (loading indicators, success/error toasts).
5. WHEN navigating between modules, THEN the system SHALL use React Router with a clear sidebar navigation structure.
6. WHEN displaying tables/lists, THEN the system SHALL use consistent styling, pagination controls, and action buttons (Edit, Delete, View Details).

---

### Requirement 27: API and Data Validation

**User Story:** As a backend developer, I want a robust REST API with proper validation and error handling, so that the frontend receives consistent, validated data and meaningful error messages.

**Acceptance Criteria:**

1. WHEN a request is made to the API, THEN all required fields SHALL be validated using Jakarta Validation annotations (@NotNull, @NotBlank, @Email, etc.).
2. WHEN invalid data is submitted, THEN the system SHALL return a 400 Bad Request with detailed error messages.
3. WHEN a requested resource does not exist, THEN the system SHALL return a 404 Not Found.
4. WHEN an unauthorized access is attempted, THEN the system SHALL return a 401 Unauthorized or 403 Forbidden depending on context.
5. WHEN an unexpected error occurs, THEN the system SHALL return a 500 Internal Server Error with appropriate logging.
6. WHEN creating or updating records via API, THEN the system SHALL enforce referential integrity (e.g., alumno exists before creating inscripcion).

---

### Requirement 28: Authentication and Authorization

**User Story:** As an administrator, I want to secure the system with authentication and role-based authorization, so that only authenticated users with appropriate roles can access sensitive functionality.

**Acceptance Criteria:**

1. WHEN a user logs in, THEN the system SHALL validate username and password against Usuario records.
2. WHEN authentication succeeds, THEN the system SHALL issue a JWT token (or session token) containing user id and role.
3. WHEN a user makes an API request, THEN the system SHALL validate the JWT token and extract the user's role.
4. WHEN a user attempts to access an endpoint, THEN the system SHALL check if their role has permission for that endpoint.
5. WHEN a user's role is "ADMIN", THEN they SHALL have access to all modules and operations.
6. WHEN a user's role is "CAJA", THEN they SHALL have access to payment, caja, and egresos modules only.
7. WHEN a user's role is "CONSULTA", THEN they SHALL have read-only access to dashboards and reports without edit/delete rights.
8. WHEN a user's role is "PROFESOR", THEN they SHALL have access to attendance and student observation modules only.

---

### Requirement 29: Database Persistence with JPA

**User Story:** As a system architect, I want the application to persist all data to a relational database using JPA, so that data is durable and queryable.

**Acceptance Criteria:**

1. WHEN the application starts, THEN the Spring Data JPA and Hibernate repositories SHALL automatically create/update database schema based on entity annotations.
2. WHEN data is created/updated via the API, THEN it SHALL be persisted to the database atomically.
3. WHEN reading data from the API, THEN the system SHALL retrieve it from the database and return in JSON format.
4. WHEN deleting a record, THEN the system SHALL perform logical deletion (update activo or equivalent status flag) unless extraordinary circumstances require physical deletion.

---

### Requirement 30: Docker Containerization

**User Story:** As a DevOps engineer, I want the application to be containerized and deployable via Docker, so that development, testing, and production environments are consistent.

**Acceptance Criteria:**

1. WHEN building the application, THEN Dockerfiles SHALL be provided for both backend (Java/Spring Boot) and frontend (Node.js/React).
2. WHEN running docker-compose, THEN backend, frontend, and database services SHALL start and communicate correctly.
3. WHEN environment variables are configured, THEN the application SHALL respect dev and prod profiles (application-dev.properties, application-prod.properties).
4. WHEN the backend container starts, THEN it SHALL initialize the database schema and be ready to serve API requests.

---

## Additional Notes

- **Language:** The system is implemented in Spanish (student records, module names, notifications), with UI elements primarily in Spanish.
- **Database:** PostgreSQL or MySQL compatible (entity DDL auto-generation via Hibernate).
- **Frontend State Management:** Component-level state with React hooks (useState, useCallback, useMemo).
- **Async Operations:** Payment reconciliation (saldoRestante calculation), monthly fee generation, and attendance sheet creation may require background task support in future iterations.
- **Extensibility:** The system is designed to support future features such as automated SMS/email collection reminders, multi-branch support, and advanced financial reporting modules.
