# Refactor integral worklog

## Baseline

- Started: 2026-07-03 (America/Buenos_Aires).
- Branch and HEAD: `main` at `6139cfdb046fea05494dfdbf2a7b55258e8385bf`.
- Versioned worktree: clean; preserved untracked `backend/backup-auth-20260703-100925/` and `backend/backup-final-auth-20260703-110922/`.
- Database rule: PostgreSQL 15 Testcontainers on random ports; no use of `localhost:5432`.
- Migration decision: freeze `V1__canonical_schema.sql`; new persisted changes start at V2 by explicit task requirement.
- Git rule: no commit, push, branch, merge, tag, reset, clean, or history rewrite was authorized.

## Phase status

### Phase 0 - characterization

- Status: complete; expected red evidence captured before the fix.
- Existing coverage reused: payment and credit application/reversal, concurrent over-application, current HTTP permission matrix, scheduler idempotency.
- Missing behavior found: monthly fee and report balances omit applied credit; monthly fee and enrollment-fee cancellation only inspect payment applications; past-period generation reads the current mutable price.
- Baseline `backend\mvnw.cmd -B -ntp clean verify`: PASS, 75 tests, 0 failures/errors/skips; PostgreSQL 15.12 Testcontainers, Flyway V1, packaging and JaCoCo completed.
- Characterization `backend\mvnw.cmd -B -ntp "-Dtest=CargoSaldoPostgreSqlTest" test`: expected FAIL, 4 tests, 3 failures. Exact defects: monthly response returned `100.00` instead of canonical `70.00`; monthly fee cancellation accepted applied credit; enrollment-fee cancellation accepted applied credit. The past-period current-price characterization passed.

### Phase 1 - canonical cargo balance

- Status: complete; gate GREEN.
- Added concrete `CargoSaldoServicio` and immutable `SaldoCargo`; no interface or schema change.
- Single and batch calculations use active payment applications plus net credit consumption/reversal.
- `CargoServicio`, `MensualidadServicio`, `MatriculaServicio`, and `ReporteServicio` delegate to the canonical calculation; report balances use three aggregate queries independent of row count.
- Cancellation now rejects either payment or credit application.
- Targeted `CargoSaldoPostgreSqlTest,PagoCanonicoPostgreSqlTest`: PASS, 9 tests.
- Batch query-count check after correcting the metric from JDBC prepared statements to Hibernate query executions: PASS, exactly 3 queries for two charges.
- Full `backend\mvnw.cmd -B -ntp clean verify`: PASS, 81 tests, 0 failures/errors/skips; Flyway V1, Hibernate validate, PostgreSQL 15.12 Testcontainers, JaCoCo and packaging completed.

### Phase 2 - SUPERADMIN minimum

- Status: complete; gate GREEN.
- Added forward-only V2 while leaving V1 byte-unchanged: `SUPERADMIN`, user auth/version columns, refresh sessions, bootstrap claim, append-only audit table and indexes.
- Added explicit `ROLE_SUPERADMIN > ROLE_ADMINISTRADOR` hierarchy and reserved endpoint matrix.
- Replaced the table-empty ADMINISTRADOR bootstrap with a transactional one-time
  SUPERADMIN claim. The temporary compatibility aliases mentioned in this
  historical step were removed before the current release.
- Bootstrap validates normalized username, 16-72 UTF-8 password bytes, active reserved role, case-insensitive uniqueness, concurrency and audit without secrets.
- User mutations now receive/reload the actor, require SUPERADMIN, lock active superadmins before last-user checks, increment `auth_version` on password/role/state changes and keep logical deletion.
- Removed arbitrary role creation and its unused request mappers.
- Directed migration/bootstrap/service/security suite: first run FAIL, 28 tests with 1 failure because the existing 500-sanitization test still used ADMINISTRADOR on the now-reserved user endpoint. Test actor corrected to SUPERADMIN.
- Focused `SecurityHttpIntegrationTest`: PASS, 14 tests.
- Full `backend\mvnw.cmd -B -ntp clean verify`: PASS, 82 tests, 0 failures/errors/skips; Flyway V1 -> V2, Hibernate validate, PostgreSQL 15.12 Testcontainers and packaging completed.

### Phase 3 - persistent refresh sessions

- Status: complete; gate GREEN.
- Access tokens now include issuer, audience, type, `auth_version` and `jti`; TTL configuration uses `Duration`.
- Refresh tokens are persisted only by SHA-256 hash, rotate under a PostgreSQL row lock, link replacements, detect reuse and revoke the complete family.
- Logout revokes the family and clears the cookie; password, role and active-state changes invalidate old tokens through `auth_version`.
- The refresh token is delivered only in an `HttpOnly` cookie with configurable `Secure`, `SameSite`, domain and path attributes. Cookie-backed refresh/logout reject unapproved origins.
- Frontend access state is process memory only; startup refresh is cookie-based, concurrent 401 responses share one refresh request, and 403 does not terminate the session. Legacy application-owned auth keys are removed without calling `localStorage.clear()`.
- Focused `PostgreSqlSchemaValidationTest`: PASS, 1 test. PostgreSQL `CHAR(64)` mappings validate through Hibernate.
- First focused `RefreshSessionPostgreSqlTest`: FAIL, 2 tests with 1 error. Root cause: an assigned-UUID entity returned from `JpaRepository.save` was ignored, leaving a transient `replacedBy` reference. The service now keeps the managed return value.
- Repeated `RefreshSessionPostgreSqlTest`: PASS, 2 tests.
- Full backend `backend\mvnw.cmd -B -ntp clean verify`: PASS, 84 tests, 0 failures/errors/skips; JAR generated.
- Frontend `npm ci`: PASS, 434 packages installed from the lockfile.
- Frontend `npm run lint`: PASS.
- Frontend `npm test -- --run`: PASS, 7 files and 16 tests.
- Frontend `npm run build`: PASS, TypeScript project build and Vite production bundle completed.

### Phase 4 - append-only audit

- Status: complete; gate GREEN.
- `AuditService` writes explicit snapshots through JDBC so events join the caller transaction; rejected authentication/escalation events use a dedicated `REQUIRES_NEW` boundary.
- Security events cover successful/rejected login, successful/rejected refresh, refresh reuse, logout and initial SUPERADMIN bootstrap.
- Administrative events cover user creation, password change, role change, activation/deactivation and rejected privilege escalation.
- Audit payload validation rejects password/token/secret/JWT/authorization keys recursively before persistence.
- Focused `AuditServicePostgreSqlTest,RefreshSessionPostgreSqlTest,UsuarioServicioTest`: PASS, 10 tests. It proves rollback leaves no event, PostgreSQL rejects audit update/delete, idempotency is unique and secret-bearing metadata is rejected.
- Full `backend\mvnw.cmd -B -ntp clean verify`: PASS, 87 tests, 0 failures/errors/skips; JAR generated.

### Phase 5 - effective-dated discipline tariffs

- Status: complete; gate GREEN.
- Added forward-only V3 with tariff and enrollment-condition structures, complete FK indexes and no data backfill, `CURRENT_DATE`, inferred dates or mutation of V1.
- Tariff selection uses the latest `vigente_desde <= effectiveDate`; absent history raises `HISTORICAL_PRICING_NOT_DEFINED`.
- ADMINISTRADOR can schedule current/future tariffs; only SUPERADMIN can enter documented historical tariffs. Every creation stores author, reason and audit event.
- New API and `/disciplinas/:id/tarifas` frontend use decimal strings and expose history without an edit operation.
- Focused schema/architecture/tariff suite: PASS, 7 tests. It covers exact/prior selection, future exclusion, duplicate dates, negative values, role rules and audit.
- Full `backend\mvnw.cmd -B -ntp clean verify`: PASS, 90 tests, 0 failures/errors/skips; Flyway V1 -> V2 -> V3, Hibernate validate and JAR packaging completed.
- Frontend `npm run lint`: PASS.
- Frontend `npm test -- --run`: PASS, 7 files and 16 tests.
- Frontend `npm run build`: PASS, including the lazy-loaded tariff screen.

### Phase 6 - effective-dated enrollment conditions

- Status: complete; gate GREEN.
- Added creation/list/selection APIs and `/inscripciones/:id/condiciones-economicas` without adding another migration: the structure was already isolated in V3.
- Each row snapshots bonus description, percentage and fixed amount; later catalog edits do not alter historical calculation inputs.
- ADMINISTRADOR can schedule current/future conditions; SUPERADMIN is required for documented historical entry. Creations are audited.
- Focused schema/condition suite: PASS, 3 tests. It covers particular cost, bonus snapshots, condition changes between periods, missing history, role rules and audit.
- Full `backend\mvnw.cmd -B -ntp clean verify`: PASS, 92 tests, 0 failures/errors/skips; JAR generated.
- Frontend `npm run lint`: PASS.
- Frontend `npm test -- --run`: PASS, 7 files and 16 tests.
- Frontend `npm run build`: PASS, including the lazy-loaded economic-condition screen.
