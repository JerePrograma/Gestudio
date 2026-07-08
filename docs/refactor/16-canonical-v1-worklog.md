# Canonical V1 completion worklog

## Initial state

- Started: 2026-06-30 (America/Buenos_Aires).
- Required branch: `main`.
- Initial HEAD: `8519ef3996b5edb3f16379cf1da99f0b6e36ce7d`.
- Expected remote SHA: `8519ef3996b5edb3f16379cf1da99f0b6e36ce7d`.
- `origin/main` after `git fetch origin main --prune`: `8519ef3996b5edb3f16379cf1da99f0b6e36ce7d`.
- Initial worktree: clean; no unstaged or staged changes.
- Remote: `https://github.com/JerePrograma/gestudio`.
- PostgreSQL rule: Testcontainers PostgreSQL 15 only; no connection to `localhost:5432`.
- Git rule: no branch creation, commit, push, merge, tag, deploy, reset, rebase, restore, clean, or history rewrite.

## Commands executed

| Phase | Command | Result |
| --- | --- | --- |
| Git safety | `git status --short --branch` | PASS: `## main...origin/main` |
| Git safety | `git branch --show-current` | PASS: `main` |
| Git safety | `git rev-parse HEAD` | PASS: expected SHA |
| Git safety | `git log -10 --oneline` | PASS: checkpoint is current HEAD |
| Git safety | `git diff` | PASS: empty |
| Git safety | `git diff --cached` | PASS: empty |
| Git safety | `git rev-parse origin/main` | PASS: expected SHA |
| Git safety | `git remote -v` | PASS: expected GitHub remote |
| Git safety | `git fetch origin main --prune` | PASS: remote reference refreshed |

## Phase status

### Phase 0 - safety and inspection

- Gate: GREEN.
- Applicable repository instructions: root `AGENTS.md`; no more specific `AGENTS.md` files exist.
- Root cause findings: none yet; baseline validation has not started.
- Decisions: preserve the canonical checkpoint; do not restore removed legacy APIs or financial classes.
- Files affected: `docs/refactor/16-canonical-v1-worklog.md`.
- Last coherent unit completed: Git safety verification and worklog initialization.

### Phase 1 - checkpoint baseline

- Gate: RED.
- Production backend compilation: PASS, 277 source files, 21.339 s.
- Backend test compilation: PASS, 12 test source files, 20.511 s.
- Backend `clean verify`: FAIL, 50 tests, 0 failures, 1 error, 0 skipped, 1:08 min.
- Frontend `npm ci`: PASS, 560 packages installed.
- Frontend lint: PASS.
- Frontend Vitest: PASS, 3 files and 8 tests, 4.40 s.
- Frontend TypeScript and Vite build: PASS, 2,275 modules, 11.29 s.
- `status.ps1`: PASS; Docker Desktop 29.3.1 available. Port 5432 was observed as occupied but was not accessed.
- `setup.ps1`: PASS; dependencies only, no services started.
- `validate.ps1`: FAIL because backend verify failed; frontend lint/test/build and local Compose passed.
- Local `docker compose config`: PASS.
- Production Compose with non-sensitive placeholders: PASS.
- Testcontainers: PASS; PostgreSQL `15.12-alpine3.21` used on random host ports.
- Flyway: PASS; exactly one migration validated and applied, schema at V1.
- Hibernate `ddl-auto=validate`: PASS against the isolated V1 database.
- Canonical payment PostgreSQL tests: PASS, 5 tests including concurrent idempotency.
- Security HTTP integration tests: PASS, 12 tests.
- JaCoCo: report/coverage gate NOT REACHED because Surefire failed first.
- Root cause: `docs/refactor/sql/04-financial-inconsistencies.sql` contains an unqualified `alumno_id` in a query that joins two CTEs exposing that column; PostgreSQL reports `column reference "alumno_id" is ambiguous`.
- Baseline changed no implementation files.
- Last coherent unit completed: exact checkpoint baseline captured.

## Errors and root causes

1. Baseline backend error: `DataAuditSqlPostgreSqlTest.ejecutaLasAuditoriasCanonicasComoConsultasDeSoloLectura` fails at line 39 with PostgreSQL error `column reference "alumno_id" is ambiguous` at position 637. The SQL audit predates the canonical query shape and does not qualify the shared column.

## Baseline command results

| Command | Result |
| --- | --- |
| `backend\.\mvnw.cmd -DskipTests compile` | PASS |
| `backend\.\mvnw.cmd -DskipTests test-compile` | PASS |
| `backend\.\mvnw.cmd clean verify` | FAIL: 50 tests, 1 error |
| `frontend\npm ci` | PASS |
| `frontend\npm run lint` | PASS |
| `frontend\npm test -- --run` | PASS: 8/8 |
| `frontend\npm run build` | PASS |
| `scripts\codex\status.ps1` | PASS |
| `scripts\codex\setup.ps1` | PASS |
| `scripts\codex\validate.ps1` | FAIL: backend only |
| `docker compose config` | PASS |
| production Compose with placeholders | PASS |

## Pending work

1. Correct the stale SQL audit and rerun the backend gates.
2. Audit endpoint security, Docker, and CI after convergence is green.
3. Complete information-economy, redundancy, and process-map documents from the implemented model.
4. Audit and simplify persisted information, processes, queries, payloads, DTOs, entities, dependencies, and frontend state where evidence supports a change.
5. Run structural contracts, performance evidence, final gates, Docker builds, and final searches.

## Phase 2 - checkpoint convergence

- Gate: GREEN.
- Change: qualified the credit-ledger columns in `docs/refactor/sql/04-financial-inconsistencies.sql`; no schema or product behavior changed.
- Root cause fixed at the shared audit query instead of weakening `DataAuditSqlPostgreSqlTest`.
- Targeted `backend\.\mvnw.cmd '-Dtest=DataAuditSqlPostgreSqlTest' test`: PASS, 1 test, 40.597 s.
- `backend\.\mvnw.cmd clean verify`: PASS, 50 tests, 0 failures, 0 errors, 0 skipped, 1:01 min.
- Flyway V1, Hibernate validate, Testcontainers PostgreSQL 15.12, financial concurrency/idempotency, security, packaging, and JaCoCo report all completed.
- Frontend gate after the coherent fix: lint PASS; 8/8 tests PASS; TypeScript/Vite build PASS, 2,275 modules, 7.07 s.
- Files affected in this phase: `docs/refactor/sql/04-financial-inconsistencies.sql`, this worklog.
- Last coherent unit completed: checkpoint baseline is fully converged and all pre-optimization code gates are green.

## Phase 3 - demonstrated simplification and contract convergence

- Gate: GREEN.
- Removed five one-implementation/unused service interfaces; retained `IEmailService` because it is an actual external boundary with prod and non-prod implementations.
- Removed empty `EmailControlador` and `MatriculaScheduler` classes.
- Removed unused direct npm dependencies `@faker-js/faker`, `lodash`, `@types/lodash`, and `react-paginate`; transitive lodash packages remain owned by installed dependencies.
- Removed `cargos.updated_at`, which had a default but no update path and therefore did not represent an actual timestamp.
- Replaced entity-side `Instant.now()` in `Pago.createdAt` with Hibernate creation timestamp handling; `PagoServicio` still supplies the configured clock on the business write path.
- Removed the explicit application `flush`; the following aggregate query already triggers JPA AUTO flush in the same transaction.
- Consolidated receipt state: `recibos` now stores only historical document facts (`pago_id`, storage key, generated/sent timestamps); `recibos_pendientes` alone owns technical state, retries and errors.
- Reduced `GET /api/pagos/alumno/{id}` from full payment details to `PagoResumenResponse` (`id`, date, received amount, state). This removes per-payment application, cargo-balance, and credit queries from the list path.
- Aligned frontend stock requests/responses with the canonical backend: decimal price string, no removed date/version fields, and required idempotency key.
- Removed dead navigation links and the full-page reload on every route change.
- Canonical payment/egress screens now use React Query as remote-state authority with centralized query keys; only form/UI state remains local.
- Added a decimal-string regression test that includes a value above JavaScript's safe integer range.
- Introduced failure during this phase: first backend compile failed at `Cargo.java:78` because removing `updatedAt` left its `@UpdateTimestamp/@Column` annotations. Cause was an incomplete mechanical field deletion; both annotations and the import were removed immediately.
- Backend `-DskipTests compile`: PASS after fix, 270 source files, 16.493 s.
- Backend `-DskipTests test-compile`: PASS, 12 test source files, 23.696 s.
- Backend `clean verify`: PASS, 50 tests, 0 failures/errors/skipped, 1:23 min; Flyway exactly V1 and Hibernate validate pass on Testcontainers PostgreSQL 15.12.
- Frontend lint: PASS.
- Frontend tests: PASS, 4 files and 9 tests, 5.43 s.
- Frontend build: PASS, 2,276 modules, 9.89 s.
- Last coherent unit completed: canonical information and frontend/backend contract reductions validated.

## Phase 4 - frontend canonical contract completion

- Gate: GREEN.
- A deliberate decimal-contract pass changed catalog and business monetary fields from TypeScript `number` to decimal `string`.
- Introduced failure: the first `npm run build` after that type change failed in the legacy alumno, inscripción, disciplina, bonificación, concepto, método de pago and recargo forms.
- Root cause: those screens still implemented the removed nested DTO shape and performed monetary arithmetic with browser numbers. The type errors exposed stale frontend behavior rather than a backend incompatibility.
- Resolution: replaced the 1,154-line alumno form, 618-line inscripción form, 286-line inscripción list and 503-line disciplina form with small forms/listing bound to the canonical scalar-ID contracts. Removed frontend tuition/discount totals; the backend remains authoritative for charges and balances.
- Consolidated the discipline contract, removed duplicate TypeScript interfaces, and retained schedule editing with explicit IDs.
- Converted remaining catalog money form values to decimal strings and added the inscripción query key.
- `frontend\npm run lint`: PASS.
- `frontend\npm test -- --run`: PASS, 4 files and 9 tests, 4.08 s.
- `frontend\npm run build`: PASS, 2,272 modules; the focused preceding run completed in 10.20 s.
- Files affected: `frontend/src/types/types.ts`, alumno/inscripción/disciplina forms, inscripción list, catalog forms and `frontend/src/hooks/queryKeys.ts`.
- Last coherent unit completed: frontend DTOs and forms compile against the canonical backend without duplicated monetary calculations.

## Phase 5 - structural contracts, security, performance and CI image gate

- Gate: GREEN for targeted checks; full gates remain pending.
- Added `CanonicalArchitectureContractTest`: exactly one V1 migration; removed financial model tokens stay absent; product time uses `Clock`; no product `printStackTrace`/`@Data`; monetary TypeScript properties cannot regress to `number`.
- The architecture test initially failed because `PdfService` legitimately uses primitive `float[]` for PDF column widths. The contract now permits that one non-monetary file explicitly and still rejects floating point elsewhere.
- A second architecture-test failure found a stale comment suggesting bare `LocalDate.now()`; the comment was corrected to describe the implemented Clock-driven contract. Final targeted result: 2 tests PASS.
- Added a schema assertion that `recibos` cannot regain technical outbox state columns.
- Added an explicit administrator policy group for cargos, pagos, crédito, caja, egresos, stock, matrículas, mensualidades and reportes; all other API endpoints remain administrator-only, and non-API requests are denied.
- `SecurityHttpIntegrationTest`: PASS, 14 tests, 0 skipped, 37.773 s. It now covers the financial endpoint matrix and invalid payment idempotency keys.
- Added deterministic performance test with 500 students and 20,000 charges on Testcontainers PostgreSQL 15.
- Initial query plan: bitmap heap scan plus sort, 39 buffers, 0.174 ms. The first test assertion also used an incorrect literal (`actual rows=32`) and failed despite returning 32 rows.
- Replaced the charge pending index with a partial `(alumno_id, fecha_vencimiento, id)` index. The first repeat still chose bitmap+sort before vacuum visibility and correctly kept the gate red.
- Final measured plan after deterministic `VACUUM ANALYZE`: index-only scan, 0 heap fetches, 6 buffers, 0.064 ms, 32 rows. Targeted performance test PASS in 34.368 s.
- Backend Docker packaging now uses `-DskipTests` only inside BuildKit. CI keeps `clean verify` as the required prior job with Docker/Testcontainers access, then builds SHA-tagged images in a dependent job; no Docker socket mount is used.
- Local development documentation records the validation-before-image contract.
- Last coherent unit completed: enforceable canonical regression contracts and measured pending-charge plan.

## Phase 6 - paginated reads and database-side caja aggregation

- Gate: GREEN.
- Added the stable generic `PageResponse` and a global server maximum of 200 rows per page.
- Paginated the growing alumno, inscripción, pending/overdue cargo, payment-by-student, egreso, stock and caja-movement contracts; corresponding React Query keys include page state.
- Removed local “infinite scroll” that downloaded complete alumno/stock datasets.
- Removed unconsumed duplicate endpoints and code: inscripción bulk, statistics, discipline filter and singular-active route; alumno simplified and graph-style `/{id}/datos`; two DTOs and unused repository/service methods.
- Payment and enrollment forms now request an explicit alumno ID instead of preloading every student.
- Caja totals are now one PostgreSQL aggregate over the ledger; only the requested movement page is hydrated. `PagoCanonicoPostgreSqlTest` executes this native projection after payment reversal.
- Introduced failure: the first backend compile after inscription method removal had duplicate `@Transactional` annotations. Annotation processing stopped, causing many secondary missing-Lombok-method errors. Removing the two orphan annotations restored compilation; no domain code was changed to chase the cascade.
- Introduced frontend failure: the first caja/cargo pagination build passed a click event to a numeric function and kept the old cargo-array query generic. Explicit callback and `Page<CargoResponse>` fixed both.
- Backend `-DskipTests compile`: PASS, 267 production sources, 17.096 s.
- Backend `-DskipTests test-compile`: PASS, 15 test sources, 21.295 s.
- Frontend lint: PASS; 9/9 tests PASS; build PASS, 2,272 modules.
- Backend `clean verify`: PASS, 57 tests, 0 failures/errors/skipped, 1:46 min. Flyway exactly V1, Hibernate validate, schema/data audits, security, finance, concurrency, performance and receipt worker passed on Testcontainers PostgreSQL 15.
- Targeted payment/caja integration test after the native aggregate assertion: PASS, 5 tests, 1:25 min.
- Last coherent unit completed: bounded list payloads and ledger-side caja summary validated end to end.

## Continuación posterior a c53f754c

### Estado inicial - 2026-07-01 09:47 ART

- SHA local: `c53f754c1738e7877c7819a701125888797510d4` (`main`).
- SHA remoto después de `git fetch origin`: `8519ef3996b5edb3f16379cf1da99f0b6e36ce7d`.
- Ahead/behind (`origin/main...HEAD`): `0 1`; el commit canónico local sigue exactamente uno adelante y no fue descartado ni publicado desde esta sesión.
- Estado inicial: worktree y staging limpios; no se creó otra rama y no se ejecutó pull, rebase, reset, commit, push, merge, tag ni deploy.
- Docker: Docker Desktop estaba instalado pero detenido; se inició sin borrar imágenes, volúmenes, contenedores ni caches. Engine `29.3.1` disponible.
- `JAVA_HOME` usado por proceso: `C:\Program Files\Java\corretto-21.0.7`; `java 21.0.7` y `javac 21.0.7`.
- PostgreSQL: sólo Testcontainers `15.12-alpine3.21`, con puertos host aleatorios (`51770` y `51924` observados). No se abrió conexión a `localhost:5432`; `status.ps1` únicamente informó que ese puerto estaba ocupado.

### Baseline posterior al commit

| Gate | Resultado |
| --- | --- |
| `backend\mvnw.cmd -DskipTests compile` | PASS; 267 fuentes; Maven 14.511 s, pared 16.776 s |
| `backend\mvnw.cmd -DskipTests test-compile` | PASS; 267 fuentes y 15 fuentes de test; Maven 14.437 s, pared 16.107 s |
| `backend\mvnw.cmd clean verify` | PASS; 57 tests, 0 failures, 0 errors, 0 skipped; Maven 1:10 min, pared 1:12.639 |
| Flyway/Hibernate/PostgreSQL | PASS; una migración, versión V1, Hibernate validate, PostgreSQL 15.12 Testcontainers |
| JaCoCo | PASS; reporte generado sobre 222 clases |
| `frontend\npm ci` | PASS; 557 paquetes; 23.426 s |
| `frontend\npm run lint` | PASS sin warnings; 5.077 s |
| `frontend\npm test -- --run` | PASS; 4 archivos, 9 tests, 0 omitidos; 4.646 s |
| `frontend\npm run build` | PASS; TypeScript y Vite, 2.272 módulos; Vite 7.44 s, pared 14.257 s |
| `scripts\codex\status.ps1` | PASS; 6.065 s |
| `scripts\codex\setup.ps1` | PASS; dependencias solamente, sin servicios; 37.854 s |
| `scripts\codex\validate.ps1` | PASS completo; 1:26.826 |
| `docker compose config` | PASS; 0.130 s |
| Compose productivo con placeholders no sensibles | PASS; 0.154 s |

- Plan representativo de cargos: `Index Only Scan using ix_cargos_alumno_pendientes`, 32 filas reales, 0 heap fetches, 6 buffers; tiempos observados 0.065 ms y 0.057 ms en las dos ejecuciones baseline.
- Advertencias no bloqueantes observadas: auto-attach de Mockito/Byte Buddy y dialecto PostgreSQL configurado explícitamente. No hubo SQLState de error ni stack trace de fallo; los stack traces de `SecurityHttpIntegrationTest` corresponden al escenario deliberado que verifica sanitización de errores 500.
- Primer gate rojo: ninguno en el baseline posterior a `c53f754c`.
- Último gate verde: Compose productivo con placeholders.
- Siguiente acción concreta: auditar los contratos exigidos que no están demostrados por los 57 tests actuales, empezando por paginación, agregación de caja, seguridad y outbox, y agregar únicamente la cobertura o corrección faltante.

### Bloque 1 - contratos de paginación

- Gate dirigido backend: GREEN.
- La prueba nueva `CanonicalPaginationPostgreSqlTest` reprodujo primero 3 fallos: `PageResponse` no exponía `first/last` y `page=-1` se normalizaba a 0 con HTTP 200.
- Corrección: `page >= 0`, `1 <= size <= 200` se validan en el borde HTTP; cada endpoint canónico usa orden fijo con ID como desempate; `PageResponse.totalElements` y `totalPages` son `long` y expone `first/last` sin serializar `Page`.
- Endpoints ajustados: alumnos, inscripciones, cargos pendientes/vencidos, pagos por alumno, egresos, stock y movimientos del resumen de caja.
- Inscripciones dejó de filtrar sólo la página visible: el filtro alumno/disciplina se ejecuta en la consulta paginada PostgreSQL y vuelve a página 0 en frontend.
- Frontend: las query keys canónicas incluyen recurso, página, tamaño, filtro y orden; Caja usa React Query como estado remoto y ya no copia la respuesta completa a estado local.
- Rutas residuales corregidas: baja de alumno ahora llama `DELETE /api/alumnos/{id}`; se eliminó el cliente sin consumidor para el inexistente `/api/stocks/conceptos`.
- `backend\.\mvnw.cmd -DskipTests test-compile`: PASS, 267 fuentes y 16 fuentes de test.
- Primera ejecución dirigida de paginación: FAIL esperado, 4 tests, 3 failures; confirmó el contrato faltante.
- Ejecución dirigida final: PASS, 4 tests, 0 failures/errors/skipped, 52.955 s. Cubre primera/intermedia/última/fuera de rango, vacío, orden estable, límite 200, parámetros inválidos, 401 y máximo dos sentencias preparadas para la página consultada.
- Frontend: lint PASS; primera ejecución de tests FAIL sólo por dos selectores de la prueba nueva; causa: estado de carga intermedio y tabla responsive duplicada. Selectores corregidos.
- Frontend final del bloque: 6 archivos, 12 tests PASS, 0 omitidos; build PASS, 2.272 módulos, 8.88 s.
- Primer gate pendiente: `backend\.\mvnw.cmd clean verify` completo con la nueva cobertura.

### Bloque 2 - cierre de paginación y agregación canónica de caja

- `backend\.\mvnw.cmd clean verify`: PASS después del bloque de paginación; 61 tests, 0 failures, 0 errors, 0 skipped; Maven 1:42 min, pared 1:44.535.
- La agregación de caja se ejecuta en PostgreSQL con `FILTER`, sin cargar el ledger para sumar. La ecuación implementada es `ingresos efectivos = INGRESO + AJUSTE_INGRESO + reversos de EGRESO/AJUSTE_EGRESO`, `egresos efectivos = EGRESO + AJUSTE_EGRESO + reversos de INGRESO/AJUSTE_INGRESO`, `neto = ingresos efectivos - egresos efectivos`.
- `CajaCanonicaPostgreSqlTest` usa orígenes financieros válidos y cubre ingreso, egreso, ambos ajustes, ambos reversos, dos métodos, rango inclusivo, movimientos fuera del rango, día vacío y rechazo de idempotency key duplicada.
- Primer gate dirigido de caja: FAIL del fixture porque intentó insertar movimientos de ingreso/egreso sin `Pago`/`Egreso`, violando las precondiciones deliberadas de V1. Se corrigió el fixture; no se relajó el catálogo.
- Gate dirigido final de caja: PASS, 2 tests, 0 failures/errors/skipped, Maven 1:01 min.
- Frontend después del cambio de caja: lint PASS; 6 archivos y 12 tests PASS; build PASS, 2.272 módulos, 13.57 s.
- Último gate verde del bloque: frontend build.

### Bloque 3 - recibos y outbox recuperable

- Se eliminó la transacción larga del worker: el claim, las renovaciones de lease y el cierre/error usan transacciones cortas; PDF, filesystem y email se ejecutan sin retener locks de base.
- `recibos_pendientes` es la única fuente de estado técnico y ahora tiene idempotency key única, token de claim, timestamps de claim/lease, constraint de coherencia e índice de trabajo. `recibos` conserva sólo hechos históricos del documento.
- El claim usa PostgreSQL `FOR UPDATE SKIP LOCKED`; un lease vencido permite recuperación. El archivo existente y `enviado_at` evitan repetir efectos ya confirmados.
- El pago crea `Recibo`, `ReciboPendiente` y su key determinista dentro de la misma transacción financiera; el rollback de pago no deja trabajo pendiente.
- Primer gate dirigido del grupo: FAIL, 11 tests, 1 error. Causa: el fixture JDBC enlazó `Instant` sin tipo SQL explícito al preparar `TIMESTAMPTZ`; PostgreSQL informó que no podía inferir el tipo. Corrección: el fixture usa `OffsetDateTime` UTC.
- Test mínimo `ReciboOutboxPostgreSqlTest`: PASS, 2 tests, 0 failures/errors/skipped, pared 50.324 s.
- Grupo final `ReciboStorageServiceTest,ReciboOutboxPostgreSqlTest,PagoCanonicoPostgreSqlTest,PostgreSqlSchemaValidationTest`: PASS, 11 tests, 0 failures/errors/skipped, Maven 1:08 min, pared 70.935 s; PostgreSQL 15.12 en puerto aleatorio, Flyway exactamente V1 y Hibernate validate verdes.
- Riesgo externo explícito: SMTP no ofrece en este código una clave idempotente confirmable; el worker evita duplicados concurrentes y reintentos después de confirmación local, pero una caída entre aceptación SMTP y persistencia de `enviado_at` no puede demostrar entrega exactamente una vez. No se oculta este límite como garantía transaccional.
- Último gate verde: grupo completo de recibos/Flyway/finanzas.
- Primer gate pendiente: contratos uniformes de request hash e idempotencia para operaciones financieras restantes.

### Bloque 4 - seguridad, errores, idempotencia y schedulers

- `RequestHash` centraliza SHA-256 UTF-8 con encuadre por longitud. Pago, egreso, venta de stock y movimientos de crédito almacenan hash; las reversiones de pago/egreso/venta almacenan hash separado. V1 exige las combinaciones key/hash coherentes.
- Se cerraron ventanas concurrentes con una segunda lectura de key después del lock estable: alumno para venta/crédito, usuario para egreso y venta bloqueada para reversión.
- Primer gate de la prueba outbox anterior: FAIL sólo por binding JDBC de `Instant`; ya documentado en bloque 3. En este bloque, `RequestHashTest,PagoCanonicoPostgreSqlTest,PostgreSqlSchemaValidationTest`: PASS, 7 tests, 0 failures/errors/skipped, Maven 1:02 min.
- `IdempotenciaCanonicaPostgreSqlTest,PostgreSqlSchemaValidationTest`: PASS, 2 tests, 0 failures/errors/skipped, Maven 52.648 s. Dos llamadas simultáneas de egreso, venta, ajuste de crédito y reversiones retornan el mismo resultado sin duplicar; misma key/payload distinto produce conflicto.
- Seguridad usa sólo tres reglas: login/refresh/preflight públicos, perfil autenticado y catch-all `/api/**` administrador. Se eliminaron matchers parciales susceptibles de quedar obsoletos.
- `ApiErrorResponse` unifica timestamp/status/code/message/fieldErrors. Los handlers de la cadena de seguridad también devuelven JSON; constraints e optimistic lock se traducen sin SQL, clases internas ni stack trace. Frontend puede categorizar 400/401/403/404/409/5xx.
- `SecurityHttpIntegrationTest`: PASS, 14 tests. El grupo final scheduler/arquitectura/seguridad pasó 18 tests, 0 failures/errors/skipped, Maven 1:39 min.
- El primer intento de ese grupo falló al compilar porque la refactorización de matrícula reutilizó el nombre local `activas`; se renombró, sin cambio funcional.
- Mensualidades y matrículas bloquean IDs activos ordenados mediante una consulta PostgreSQL y cargan detalles en batch. `SchedulerIdempotencyPostgreSqlTest` ejecuta dos workers simultáneos y una repetición posterior: una mensualidad/cargo por inscripción/período y una matrícula/cargo por alumno/año.
- `MatriculaScheduler` no se restauró: la capacidad real está en `ScheduledTasks` y en el caso de uso manual.
- Último gate verde: idempotencia PostgreSQL + schema validate.

### Bloque 5 - contrato frontend, dependencias y CI

- Salones dejó de concatenar páginas y ahora reemplaza la página visible. Reportes dejó de llamar endpoints retirados y usa `GET /reportes/mensualidades` y `POST /reportes/mensualidades/exportar`.
- Se eliminaron `IntersectionObserver` y los componentes de infinite scroll; las listas locales restantes exigen botón `Mostrar más`. No existe request automático para reconstruir una colección completa.
- `money.ts` valida, normaliza coma/punto, compara importes grandes y formatea sin `Number`; 0, 0.01, inválidos, negativos, más de dos decimales, ceros finales, vacío, coma y valores fuera del safe integer están cubiertos.
- Dependencias eliminadas por falta de consumidores: Chart.js, react-chartjs-2, file-saver, sus tipos, dos plugins Tailwind 4 no configurados, user-event, parser/plugin TypeScript duplicados, eslint-plugin-react y picomatch.
- DTOs/código eliminados por ausencia confirmada de ruta/servicio/consumidor: mapper/request de matrícula, dos requests de reporte heredados, cliente frontend de matrícula y tipos asociados.
- Frontend tras el primer lote: `npm ci` PASS, lint PASS, 6 archivos/15 tests PASS, build PASS, 2.264 módulos, Vite 9.52 s, pared total 65.862 s. Falta repetir después del último lote de dependencias y `apiError.test`.
- CI ya no contiene job de deploy/push: valida backend/frontend/Compose y sólo construye imágenes SHA después de gates verdes.
- Primer gate pendiente: `clean verify` integral después de todos estos cambios.

## Cierre de reproducibilidad CI y Docker - 2026-07-01

### Estado inicial

- Rama obligatoria: `main`.
- HEAD inicial y `origin/main`: `041a27fd74d9b73876da561e553b6c0a78487fd7`.
- Ahead/behind: `0/0`; worktree inicial limpio.
- Alcance: contrato no interactivo de Vitest, ejecución manual de CI, gates locales, Compose e imágenes; sin cambios de negocio, API, entidades ni Flyway V1.
- Causa del gate frontend no reproducible: `npm test` resolvía a `vitest`, cuyo modo predeterminado queda observando archivos. Reenviar `--run` desde consumidores dejaba el contrato repartido y permitió una ejecución manual en modo watch.
- Corrección: `test` pasa a `vitest run`, se agrega `test:watch` para uso interactivo y CI/`validate.ps1` ejecutan sólo `npm test`. El workflow agrega `workflow_dispatch` y conserva la validación con Docker disponible antes de construir imágenes.

### Resultado final

| Gate | Resultado |
| --- | --- |
| `backend\.\mvnw.cmd clean verify` | PASS; 70 tests, 0 failures, 0 errors, 0 skipped; PostgreSQL 15.12 Testcontainers, Flyway V1, Hibernate validate, JaCoCo sobre 221 clases y JAR generado |
| `frontend\npm ci` | PASS; 434 paquetes |
| `frontend\npm run lint` | PASS sin warnings |
| `frontend\npm test` | PASS; `vitest run`, 7 archivos y 16 tests, 0 omitidos, código 0, sin `Waiting for file changes` |
| `frontend\npm run build` | PASS; TypeScript y Vite, 2.264 módulos |
| `scripts\codex\status.ps1` | PASS; JDK 21, Node 22.14.0, npm 10.9.2, Docker Engine 29.3.1 y Compose v5.1.1 |
| `scripts\codex\setup.ps1` | PASS; dependencias solamente, sin iniciar servicios |
| `scripts\codex\validate.ps1` | PASS; backend, frontend y Compose local |
| `docker compose config --quiet` | PASS |
| Compose productivo con placeholders no sensibles | PASS; PostgreSQL sin puertos host y aplicaciones sin `build` |
| `docker build --pull -t gestudio-backend:canonical-ci-check .\backend` | PASS; tests omitidos dentro de BuildKit, sin Testcontainers; runtime de 132.203.461 bytes |
| `docker build --pull ... -t gestudio-frontend:canonical-ci-check .\frontend` | PASS; `npm ci`, 0 vulnerabilidades y runtime estático de 21.077.547 bytes |

- Testcontainers accedió al daemon por el socket del host y usó `postgres:15.12-alpine3.21` en puertos efímeros. No se conectó ni inspeccionó `localhost:5432`; `status.ps1` sólo informó que el puerto estaba ocupado.
- El workflow conserva push a `main`, pull requests, Java 21, Node 22.14.0, caches Maven/npm, los gates backend/frontend/Compose, imágenes posteriores a `validate`, tags por SHA y ausencia de deploy; agrega ejecución manual con `workflow_dispatch`.
- El runtime backend contiene sólo `app.jar`, el recurso de firma y directorios de recibos, y ejecuta como usuario `gestudio`. El runtime frontend no contiene fuentes, `package.json`, `/app` ni `node_modules`.
- No se encontraron los placeholders sensibles de CI en configuración, historial ni filesystem de las imágenes.
- Advertencias no bloqueantes observadas: auto-attach de Mockito/Byte Buddy, dialecto PostgreSQL explícito, `open-in-view` predeterminado, aviso futuro de annotation processing de `javac`, puerto host 5432 ocupado y actualización mayor de npm disponible.
- Archivos modificados: `.github/workflows/github.-actions-demo.yml`, `frontend/package.json`, `scripts/codex/validate.ps1`, `docs/refactor/15-performance-and-integrity-gates.md`, este worklog y `docs/development/local-development.md`.
- Confirmación remota posterior: `CI Le Dance` run `28544656047`, commit `33c03bbd7cadaa1342134156bc7cb8c9de22e795`; `validate` y `build-images` finalizaron `SUCCESS`.

## Aislamiento PostgreSQL y cierre acotado de concurrencia - 2026-07-01

- Estado inicial: rama `main`, HEAD y `origin/main` en `01000e53eb92afc9e1a1371858d4e5e1e607aac5`, ahead/behind `0/0` y worktree limpio.
- Evidencia remota: run `28539600117`, job `84609701111`, agotó 30 minutos en `Verify backend`.
- Causa FK: `PostgreSqlIntegrationTest` comparte un contenedor/base entre clases; `CanonicalPaginationPostgreSqlTest.seed()` ejecutaba `alumnos.deleteAll()`, pero datos persistidos por pruebas anteriores incluían `cargos.alumno_id`, protegidos por `fk_cargos_alumno`. El test dependía del orden de clases.
- Corrección de aislamiento: paginación ejecuta `TRUNCATE TABLE alumnos RESTART IDENTITY CASCADE` antes del seed, dentro de su transacción, conserva `roles` y crea exactamente 205 alumnos. Outbox trunca `recibos_pendientes` antes de crear su única fila identificable.
- Causa del bloqueo: el primer claim retenía el lock esperando un latch sin timeout; si el segundo claim encontraba una fila antigua, la aserción fallaba antes de `release.countDown()` y el cierre implícito del executor esperaba indefinidamente al primer hilo.
- Corrección de concurrencia: `release.countDown()` está en `finally`; latch, futures y terminación del executor tienen límites; ante fallo se cancelan los futures y se usa `shutdownNow`; el camino normal usa `shutdown`. El test outbox tiene `@Timeout(15)`. Se aplicó el mismo cierre acotado a los tres tests concurrentes equivalentes encontrados en la revisión focalizada.
- No cambiaron código productivo, API, entidades, Flyway V1, lógica financiera, `findClaimableForUpdate` ni `timeout-minutes`.

| Gate | Resultado |
| --- | --- |
| `mvnw.cmd -Dtest=CanonicalPaginationPostgreSqlTest test` | PASS; 4 tests, 0 failures/errors/skipped; Maven 01:24 |
| `mvnw.cmd -Dtest=ReciboOutboxPostgreSqlTest test` | PASS; 2 tests, 0 failures/errors/skipped; Maven 01:03 |
| `mvnw.cmd "-Dtest=PagoCanonicoPostgreSqlTest,CanonicalPaginationPostgreSqlTest,ReciboOutboxPostgreSqlTest" test` | PASS; 11 tests, 0 failures/errors/skipped; Maven 01:10 |
| Primer `mvnw.cmd clean verify` | PASS; 70 tests, 0 failures/errors/skipped; PostgreSQL 15.12 Testcontainers, Flyway V1, JaCoCo sobre 221 clases y JAR; Maven 01:33 |
| Segundo `mvnw.cmd clean verify` consecutivo | PASS; 70 tests, 0 failures/errors/skipped; PostgreSQL 15.12 Testcontainers, Flyway V1, JaCoCo sobre 221 clases y JAR; Maven 01:36 |

- Confirmación remota posterior: `CI Le Dance` run `28544656047`, commit `33c03bbd7cadaa1342134156bc7cb8c9de22e795`; `validate` y `build-images` finalizaron `SUCCESS`.

## Smoke integrado de baseline canónica - 2026-07-02

### Estado inicial

- Rama obligatoria: `main`.
- HEAD inicial y `origin/main`: `33c03bbd7cadaa1342134156bc7cb8c9de22e795`.
- Ahead/behind: `0/0`; worktree inicial limpio.
- CI remoto anterior confirmado: workflow `CI Le Dance`, run `28544656047`, commit `33c03bbd7cadaa1342134156bc7cb8c9de22e795`; `validate` y `build-images` finalizaron `SUCCESS`.
- Alcance: bootstrap administrativo de único uso y smoke Docker/API/SQL aislado; sin nueva rama, commit, push, tag, deploy, datos reales, secretos reales, conexión a `localhost:5432` ni cambios en Flyway V1.
- `ADMINISTRADOR` sigue siendo el rol máximo del modelo y el exigido por `SecurityConfigurations`; no se agrega `SUPER_ADMIN` ni un bypass por usuario.
- Primer gate pendiente: prueba focalizada del bootstrap después de completar únicamente la cobertura contractual faltante.

### Implementación y validación

- El initializer productivo ya satisfacía el contrato: bean condicional sólo con `APP_BOOTSTRAP_ADMIN_ENABLED=true`, default `false`, tabla `usuarios` vacía, rol activo `ADMINISTRADOR` buscado sin distinguir mayúsculas, `PasswordEncoder`, usuario activo y log limitado al ID/instrucción de apagar la bandera. No se cambió código productivo, V1, roles ni seguridad.
- `AdminBootstrapRunnerTest` quedó con 8 tests para creación única/codificada, usernames inválidos, passwords ausente/corta/>72 bytes, usuario preexistente, rol ausente/inactivo, condición Spring deshabilitada y reinicio accidental sin mutación.
- Gate focalizado: PASS, 8 tests, 0 failures/errors/skipped, Maven 26.867 s.
- Primer `clean verify`: FAIL ambiental, 66 tests alcanzados y 9 errors porque Docker Desktop estaba detenido (`Could not find a valid Docker environment`). Se inició Docker Desktop sin borrar recursos y se repitió el mismo gate.
- `clean verify` final: PASS, 75 tests, 0 failures/errors/skipped, 01:18 min; PostgreSQL 15.12 Testcontainers, Flyway exactamente V1, Hibernate validate, JaCoCo sobre 221 clases y JAR generado.
- Frontend: primer `npm ci` FAIL con `EPERM` porque un Vite/esbuild preexistente retenía `node_modules`. Sin detener el proceso del usuario, se apartó/restauró ese árbol y una instalación limpia pasó `npm ci`, lint sin warnings, 7 archivos/16 tests sin omitidos y build TypeScript/Vite de 2.264 módulos.
- Compose local y productivo con placeholders no sensibles: PASS.
- Imágenes `gestudio-backend:smoke-check` y `gestudio-frontend:smoke-check` con `--pull`: PASS.
- El smoke corrige dos diferencias reales de PowerShell/host descubiertas antes de las corridas verdes: decide comandos nativos por exit code en PowerShell 5.1 y aísla variables Compose frente a un `SPRING_PROFILES_ACTIVE` heredado. Cada intento fallido limpió su proyecto completo.

| Ejecución verde | Proyecto | Puertos PostgreSQL/backend/frontend | Duración | Resultado |
| --- | --- | --- | --- | --- |
| 1 | `gestudio-smoke-21692-e608c2c9` | `60745` / `60746` / `60747` | `00:01:51` | 19 PASS, 0 fallos, sin recursos residuales |
| 2 | `gestudio-smoke-20344-716ba129` | `61952` / `61953` / `61954` | `00:01:37` | 19 PASS, 0 fallos, sin recursos residuales |

- Ambas corridas construyeron imágenes, comenzaron con base vacía, aplicaron sólo Flyway V1, crearon un único usuario BCrypt `ADMINISTRADOR`, validaron 401/login/perfil/refresh y rechazo cruzado de tokens, apagaron el bootstrap y recrearon backend preservando la base.
- El recorrido API cubrió catálogos mínimos, alumno/listado/búsqueda, inscripción sin duplicado y matrícula automática, cargo por concepto, pago parcial, retry idéntico, conflicto por payload distinto, pago restante, recibo/outbox, caja, egreso y reversión, stock/venta/retry/reversión y persistencia después de otro reinicio.
- SQL fue sólo lectura dentro de `db`: historial Flyway, bootstrap/hash, ID de venta no expuesto por la respuesta del endpoint, unicidad, saldos, stock, outbox y auditorías canónicas de huérfanos/finanzas/estados.
- Límite real: no existe un disparador HTTP/worker operativo de recibos en runtime. El smoke valida creación/unicidad del outbox y `ReciboOutboxPostgreSqlTest` valida claim/lease; no declara entrega SMTP exactly-once y R31 sigue abierto.
- Integración CI: se agrega un job `smoke` separado, dependiente de `validate`, sin secretos ni servicios externos. La cobertura remota de este job queda pendiente hasta que exista un commit y un run futuros; esta sesión no hace commit ni push.
- Compatibilidad del comando del job: `pwsh -NoProfile -File .\scripts\smoke-local.ps1` pasó localmente con proyecto `gestudio-smoke-12072-da8f19ee`, puertos `55510/55511/55512`, 19 pasos, 0 fallos, cleanup completo y duración `00:01:39`.
