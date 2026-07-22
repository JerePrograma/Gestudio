# Gestudio project instructions

These instructions supplement the host-wide Codex policy.

## Project identity

Gestudio is a monolithic business application for managing students,
enrollments, disciplines, attendance, monthly fees, payments, inventory,
cash movements, expenses, users, notifications, receipts, and reports.

Current stack:

- Java 21.
- Spring Boot 3.5.x.
- Spring Data JPA and Hibernate.
- PostgreSQL.
- Flyway.
- Maven.
- React 18.
- TypeScript.
- Vite.
- Formik and Yup.
- Docker Compose.

Treat the repository as a monorepo:

- `backend/`: Spring Boot backend.
- `frontend/`: React frontend.
- `backend/src/main/resources/db/migration/`: Flyway migrations.
- `.github/workflows/`: CI/CD.
- `.kiro/`: historical architecture and project guidance.

## Initial inspection

Before making changes:

1. Read this file and any more specific `AGENTS.md` files.
2. Inspect `git status --short --branch`.
3. Inspect the current commit and branch.
4. Inspect the relevant backend, frontend, migration, configuration, and test
   files.
5. Identify whether the task changes:
   - API contracts;
   - persisted data;
   - financial calculations;
   - authentication or authorization;
   - scheduled jobs;
   - Docker or deployment;
   - frontend and backend simultaneously.
6. Distinguish implemented architecture from aspirational documentation.

Do not assume `.kiro/steering/ARCHITECTURE.md` describes the current code.
The current implementation is primarily a layered Spring monolith, not a
complete hexagonal or Clean Architecture implementation.

## Architectural direction

Preserve the application as a modular monolith.

Prefer organization by business capability:

- alumnos;
- inscripciones;
- disciplinas;
- asistencias;
- facturacion;
- pagos;
- caja;
- inventario;
- seguridad;
- notificaciones;
- shared infrastructure.

Do not introduce:

- microservices;
- distributed messaging;
- CQRS for the whole application;
- event sourcing;
- duplicate domain and JPA models for every entity;
- one interface per service without a real boundary;
- speculative infrastructure or future scaffolding.

Interfaces are appropriate for actual external boundaries such as:

- email delivery;
- receipt storage;
- external payment providers;
- clock and time abstractions;
- external APIs.

For ordinary application services with one implementation, prefer a concrete
class unless an interface provides measurable value.

## Database and Flyway safety

PostgreSQL and Flyway migrations are the persisted source of truth.

The canonical baseline is `V1__canonical_schema.sql`; the retired V1-V060
history is not a supported upgrade source and must not be restored to the
active migration directory. V1 and every migration already applied by Flyway
are immutable. Schema evolution uses the next numeric, forward-only migration.

- Keep exactly one canonical V1 and preserve the checksums of all published
  migrations.
- Add the next contiguous migration for schema changes and validate both a
  clean database and the supported upgrade path.
- Derive the current migration count and latest version from the repository;
  never hardcode V7 or another latest version in operational validators.
- Inspect all existing migrations before choosing a version.
- Never use `ddl-auto=update` as a replacement for Flyway.
- Prefer `ddl-auto=validate`.
- Every schema change must include:
  - data preconditions;
  - handling for existing rows;
  - indexes and constraints where required;
  - rollback or recovery considerations;
  - verification SQL.
- Never discard ambiguous production data automatically.
- Generate a report for duplicates or inconsistent rows before normalizing
  them.
- Do not issue broad dynamic SQL against every table in the schema unless the
  task explicitly requires it and the affected tables are proven.

Do not physically delete historical:

- payments;
- payment details;
- monthly fees;
- enrollments;
- attendance;
- cash movements;
- expenses;
- audit-relevant users.

Prefer status transitions, deactivation, or explicit reversal records.

Do not use `clear()` on a managed JPA collection as a way to hide data from a
JSON response.

Treat `cascade = ALL`, `orphanRemoval = true`, and database
`ON DELETE CASCADE` as destructive behavior. Inspect all affected relations
before changing or clearing a collection.

## Financial integrity

Financial calculations are high-risk.

- Use `BigDecimal` for every monetary value.
- Do not introduce new `double`, `Double`, `float`, or `Float` monetary fields.
- Do not convert `BigDecimal` to `double` during calculations.
- Use explicit scale and rounding.
- Compare monetary values with `compareTo`.
- Keep one authoritative source for each financial value.
- Do not silently clamp negative balances to zero.
- Reject or explicitly model overpayments.
- Do not mutate an original amount when calculating a remaining amount.
- Do not represent partial payment by cloning debt records unless the existing
  behavior is being preserved temporarily under characterization tests.
- A payment, monthly fee, discount, surcharge, stock movement, and cash
  movement must remain transactionally consistent.

Before changing payment behavior, document these invariants:

- original amount;
- amount paid;
- remaining amount;
- status transitions;
- overpayment policy;
- reversal policy;
- stock effect;
- cash effect;
- receipt effect.

Do not infer an entity ID or financial source by parsing a human-readable
description. Requests and persisted relationships must use explicit IDs.

Descriptions may be stored as immutable snapshots for display, but they must
not act as foreign keys.

## Transactions and side effects

Define transaction boundaries at application use-case level.

A use case should not mix unrelated responsibilities such as:

- persistence;
- monetary calculation;
- PDF generation;
- email delivery;
- stock lookup;
- response serialization.

Email or receipt delivery failure must not leave a valid payment partially
persisted.

Prefer after-commit side effects when consistency requires the main
transaction to succeed first.

Scheduled processes must be idempotent through database constraints, not only
through an application flag.

Use a configurable `Clock` and explicit time zone for business dates.
Do not scatter `LocalDate.now()` through domain logic.

## JPA entities and DTOs

Do not expose JPA entities directly from controllers.

Use explicit request and response DTOs.

Prefer immutable Java records for public DTOs.

Mapping must never mutate the persisted entity merely to shape a response.

Avoid Lombok `@Data` on entities with bidirectional relationships unless all
generated equality, hash code, and string behavior has been reviewed.

Use entity equality based on stable identity where appropriate.

Do not include large graphs, passwords, personal information, or financial
collections in generated `toString()` output.

Use constructor injection.

Do not mix Spring Data repositories and direct `EntityManager` operations in
the same use case without a documented reason.

## Security

Authentication and authorization changes require tests.

- Public self-registration must never allow the caller to choose an
  administrative role.
- Administrative endpoints must enforce roles in the backend.
- Frontend route hiding is not authorization.
- Access tokens and refresh tokens must not be interchangeable.
- Invalid, malformed, or expired credentials must return 401.
- Authenticated users without permission must receive 403.
- Inactive users must not remain authorized merely because an old JWT is
  structurally valid.
- Never log credentials, JWT values, passwords, secrets, or complete
  authentication payloads.
- Do not expose internal exception details in 500 responses.

Secrets must come from environment or external configuration.
Never commit real credentials.

## Logging and personal data

Prefer one meaningful log event per business operation.

Use IDs, states, and outcomes rather than complete entities or request bodies.

Do not log:

- passwords;
- tokens;
- complete student records;
- private notes;
- full payment payloads;
- email bodies;
- database credentials.

Detailed calculation steps belong at `DEBUG`, not `INFO`.

## Frontend

Use the backend as the authority for business and financial calculations.

The frontend may present provisional totals for usability, but submitted
values must be validated and recalculated by the backend.

Use:

- `import.meta.env` for Vite environment variables;
- the shared Axios client;
- generated or centrally maintained API types;
- strict TypeScript types;
- existing React Query patterns where applicable.

Do not:

- hardcode production IP addresses;
- use `process.env` in Vite browser code;
- use `localStorage.clear()`;
- interpret every 403 as an expired token;
- hide type errors with `as unknown as`;
- duplicate backend financial formulas across components;
- introduce another state or form library without a concrete requirement.

For HTTP authentication behavior:

- 401 may trigger one serialized refresh attempt;
- 403 must preserve the session and show insufficient permissions;
- failed refresh must remove only application-owned authentication keys;
- concurrent 401 responses must not produce multiple refresh requests.

Do not perform broad visual redesigns while fixing backend or data issues.

## Dependency management

Do not add or upgrade dependencies to bypass a code or configuration problem.

Backend:

- keep Spring dependency versions managed by the Spring Boot BOM;
- do not override an individual Spring starter version without evidence;
- configure annotation processors through Maven correctly;
- prefer the Maven wrapper once it is added and versioned.

Frontend:

- version `package-lock.json`;
- use `npm ci` when the lockfile exists;
- do not retain self-referencing `file:` dependencies;
- runtime imports belong in `dependencies`, not `devDependencies`.

## Testing strategy

For bug fixes, first add a regression test that demonstrates the defect when
practical.

For legacy financial refactors, add characterization tests before replacing
behavior.

Backend testing priority:

1. Pure unit tests for calculations and state transitions.
2. Repository tests with PostgreSQL-compatible behavior.
3. Service integration tests.
4. MockMvc tests for API and security.
5. End-to-end tests for critical payment flows.

Use Testcontainers for behavior that depends on PostgreSQL semantics when
available in the repository.

Do not use H2 as proof that PostgreSQL migrations, constraints, locking, or SQL
work correctly.

Frontend testing priority:

1. Pure mapper and utility tests.
2. Hook tests.
3. Component tests.
4. Critical user-flow tests.

Do not test private methods through reflection when behavior can be tested
through a public contract.

## Required validation

After backend changes, run from the repository root:

```powershell
Push-Location backend
try {
    if (Test-Path ".\mvnw.cmd") {
        .\mvnw.cmd clean verify
    }
    else {
        mvn clean verify
    }
}
finally {
    Pop-Location
}

After frontend changes:

Push-Location frontend
try {
    npm run lint
    npm run build
}
finally {
    Pop-Location
}

After dependency, Docker, or deployment changes, also run the relevant clean
Docker builds.

After migration changes:

validate the complete Flyway history on a clean PostgreSQL database;
validate upgrade from the previous schema state;
run reconciliation queries;
report row counts and inconsistencies.

Do not report the application as validated based only on:

IDE compilation;
compiling a subset of classes;
temporary stubs;
improvised classpaths;
a frontend development server starting;
a Dockerfile parse check;
an H2-only test.
Repository-wide refactors

For a large refactor:

Establish the baseline.
Record pre-existing failures.
Add characterization tests.
Fix critical defects.
Introduce migrations and compatibility layers.
Reconcile old and new data.
Switch reads and writes incrementally.
Remove obsolete code only after equivalent behavior is proven.
Run full validation after every material phase.

Create focused commits only when explicitly requested.

Do not combine all of the following in one uncontrolled change:

schema replacement;
package relocation;
public API changes;
frontend rewrite;
security rewrite;
Docker rewrite;
mass formatting.

For each phase, report:

scope;
changed files;
invariants affected;
migration impact;
exact validation commands;
final command results;
unresolved risks.
Known high-risk areas

Treat these areas as requiring evidence and regression coverage:

PagoServicio;
AplicacionPago;
MovimientoCaja, MovimientoCredito y MovimientoStock;
Recibo y ReciboPendiente;
MensualidadServicio;
JPA collections using orphanRemoval;
JWT validation and refresh;
public user and role endpoints;
Docker Java version alignment;
Flyway migrations;
frontend authentication interceptors;
scheduled monthly-fee, enrollment, attendance, and surcharge processes.

Do not assume an existing method is correct because its comment says it was
refactored or unified. Verify its actual behavior.


# Contraargumentos serios

## No conviene compilar todo durante el setup

El setup debe preparar el worktree, no decidir que el repositorio completo está sano. El build actual puede tener fallos preexistentes y hacer que Codex ni siquiera pueda abrir un entorno para repararlos.

Por eso:

- el setup sólo resuelve dependencias;
- las acciones ejecutan `clean verify`, lint y build;
- los errores quedan visibles y atribuibles.

## No conviene iniciar Docker automáticamente

El Compose actual evita `container_name` fijos y permite configurar puertos,
pero el host Docker sigue siendo compartido. Docker debe iniciarse mediante una
acción consciente, con nombre de proyecto aislado y limpieza limitada a los
recursos etiquetados de ese proyecto.

# Contrato operativo

La configuración correcta es:

- **Windows PowerShell**, no el script predeterminado Unix.
- Setup limitado a herramientas y dependencias.
- Sin Docker automático.
- Acciones separadas para validar, ejecutar y detener servicios.
- `AGENTS.md` concentrado en integridad financiera, Flyway, seguridad, JPA y compatibilidad.
- Ningún “refactor masivo” ejecutado como una única edición indiscriminada.
