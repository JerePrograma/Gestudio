# Plan de pruebas

Estado documental histórico: este plan precede a la integración final. El
resultado vigente de las partes A-D se consolidó en el informe 23.

Referencias: [tablero](./00_INDEX.md), [baseline](./01_BASELINE_Y_HALLAZGOS.md), [matriz RBAC](./02_MATRIZ_RBAC.md), [Etapa 1](./03_ETAPA_1_SEGURIDAD_RBAC.md), [Etapa 1B](./04_ETAPA_1B_LIQUIDACION_FINANCIERA.md), [Etapa 2](./05_ETAPA_2_UX_OPERATIVA.md), [bitácora](./09_BITACORA_IMPLEMENTACION.md), [decisiones](./10_DECISIONES_Y_BLOQUEOS.md) y [checklist de release](./11_CHECKLIST_RELEASE.md).

## Objetivo y reglas de evidencia

Este plan convierte cada gate en pruebas reproducibles. No sustituye los criterios de aceptación de cada tarea ni declara resultados que aún no existen.

- `PASS`: el comando terminó en código 0 y se registraron fecha, alcance y conteos.
- `FAIL`: el comando terminó distinto de 0; se registra la causa concreta y si el fallo es preexistente o introducido.
- `BLOCKED`: una dependencia o decisión impide ejecutar el caso; debe enlazar un `BLK-*`.
- `NO_VERIFICADO`: la prueba está definida, pero todavía no se ejecutó o no existe su implementación.
- Un test focalizado sirve durante una tarea; no reemplaza `clean verify`, lint, build, validación `All`, Flyway ni smoke exigidos por el gate.
- PostgreSQL/Testcontainers es obligatorio para migraciones, constraints, locking, concurrencia y SQL. H2 no es evidencia válida.
- Los datos destructivos se prueban sólo en contenedores o bases descartables; nunca en `localhost:5432` ni sobre datos reales.
- No se corrige una prueba para esconder un defecto. Toda falla se clasifica antes de avanzar.

## Baseline histórico ejecutado

| Alcance | Comando | Resultado registrado | Estado |
|---|---|---|---|
| Frontend completo | `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Frontend` | lint `PASS`, tests 33/36, build `PASS` | `FAIL` clasificado: tres fallos preexistentes |
| Backend completo | `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Backend` | `clean verify`, 115/115, PostgreSQL 15 por Testcontainers, `BUILD SUCCESS` | `PASS` |
| Frontend RBAC focalizado | seis archivos de auth/navegación/rutas/Usuarios/Roles | 15/15 | `PASS` |
| Validación `All` | frontend + backend + `docker compose config --quiet` | no ejecutada en el baseline documentado | `NO_VERIFICADO` |
| Smoke aislado | `scripts/smoke-local.ps1` | no ejecutado en esta etapa | `NO_VERIFICADO` |

Los tres fallos frontend históricos están detallados en [01_BASELINE_Y_HALLAZGOS.md](./01_BASELINE_Y_HALLAZGOS.md#validación-inicial). Ya no se reproducen en la suite actual 140/140.

## Resultados GATE-1 — 2026-07-14

| Alcance | Comando | Resultado | Estado |
|---|---|---|---|
| Focalizado RBAC/PostgreSQL | `mvnw.cmd -Dtest=... test` | 51/51 | `PASS` |
| Backend | `validate.ps1 -Scope Backend` | 129/129; 0 fallos/errores/skips | `PASS` |
| Frontend | `validate.ps1 -Scope Frontend` | lint; 21 archivos/140 tests; build 2337 módulos | `PASS` |
| Integrado | `validate.ps1 -Scope All` | backend, frontend y Compose | `PASS` |
| Smoke canónico | `scripts/smoke-local.ps1` | 20/20; base limpia V1–V6; imágenes reconstruidas; limpieza completa; 00:03:20 | `PASS` |
| Compose aislado | `docker compose config --quiet` | exit 0 | `PASS` |

La primera corrida completa del smoke terminó `FAIL` en registro de usuario porque `AuditService` clasificó el valor legítimo `SECRETARIA` como secreto. Se agregó una regresión PostgreSQL, se ajustó la detección por delimitadores y se repitieron backend, All y smoke hasta obtener exit 0. El fallo no se reclasificó como aceptable.

## Trazabilidad mínima por riesgo

| Riesgo / hallazgo | Prueba obligatoria | Gate |
|---|---|---|
| `P0-SEC-001..005` catálogo, V5, bootstrap y base limpia | Flyway limpia + upgrade desde V5 + bootstrap → login → perfil → primer GET sin seed demo | GATE-1 |
| `P0-SEC-006..009` granularidad y 401/403/409 | matriz HTTP parametrizada por método, ruta y permiso; test del handler de autorización | GATE-1 |
| `P0-SEC-010..013` contrato frontend | constantes, menú, ruta, acción, `/unauthorized`, 401/403 y refresh concurrente | GATE-1 |
| `P0-SEC-014` Profesor | dos profesores, recursos propios y acceso cruzado denegado en backend | GATE-1 o rol deshabilitado |
| `P0-SEC-015` WebSocket | canal ausente si se deshabilita, o handshake/origen/destino/aislamiento si se habilita | GATE-1 |
| `P0-FIN-001..006` doble fuente financiera | vigencias, huecos, límites, snapshot atómico, fórmula exacta e idempotencia en PostgreSQL | GATE-1B |
| `P1-UX-001..022` UX operativa | utilidades/componentes, contratos HTTP y recorrido Secretaría responsive | GATE-2 |
| Contratos reutilizables | suite de consumidores, rutas/permisos y búsquedas de duplicados/callers | GATE-3 |
| Demo/publicación | E2E por rol, smoke limpio, Docker, backup/restore y rollback | GATE-4 / release |

## Unitarios frontend

### Cobertura existente a conservar

- `utils/money.test.ts`: normalización, precisión por string, comparación y formato.
- `api/apiError.test.ts`: categorías HTTP, mensajes y errores de campo.
- `hooks/context/auth-context.test.ts`: roles múltiples y permisos efectivos.
- `api/axiosConfig.test.ts`: un refresh serializado ante 401, 403 sin refresh ni pérdida de sesión, limpieza sólo de claves propias y ausencia de loop.
- `config/navigation.test.ts`: visibilidad por permisos.
- `rutas/ProtectedRoute.test.tsx`: anónimo, loading, permiso permitido/denegado.
- `componentes/comunes/MoneyInput.test.tsx`: decimal como string y error accesible.

### Casos a agregar por etapa

| Tarea | Caso mínimo | Resultado esperado |
|---|---|---|
| `E1-007` | catálogo tipado y metadata de rutas | toda ruta protegida usa un `PermissionCode` existente; `/unauthorized` no exige `PERM_APP_ACCESO` |
| `E1-008` | `PermissionGate` y acciones sensibles | acción visible sólo con permiso; el contenido denegado no se monta |
| `E1-009` | notificaciones | hook deshabilitado no conecta, o URL/protocolo/origen se resuelven por ambiente |
| `E2-001..002` | comboboxes | debounce cancelable, teclado, loading/error/empty, valor controlado e ID sólo interno |
| `E2-003..010` | páginas operativas | referencias humanas, estados, ARS, fecha local, acciones por estado/permiso y errores accionables |
| `E3-002..006` | formatters, diálogo y metadata | límites de fecha/moneda, foco, cancelación, una sola confirmación y contrato ruta-menú-acción |

Comando focalizado actual:

```powershell
Push-Location .\frontend
try {
    npm test -- src/config/navigation.test.ts src/rutas/ProtectedRoute.test.tsx src/hooks/context/auth-context.test.ts src/api/axiosConfig.test.ts src/funcionalidades/usuarios/UsuariosPagina.test.tsx src/funcionalidades/roles/RolesPagina.test.tsx
}
finally {
    Pop-Location
}
```

## Integración frontend

Se prueban componentes públicos con Testing Library y los providers reales mínimos; no métodos privados ni snapshots extensos.

| Flujo | Aserciones obligatorias | Estado |
|---|---|---|
| Sesión y rutas | carga, anónimo → login, autenticado sin permiso → `/unauthorized`, permitido → contenido | parcial existente; ampliar en `E1-007` |
| Menú/ruta/acción | el mismo permiso gobierna las tres capas y acceso directo no muestra una acción prohibida | `NO_VERIFICADO` |
| 401/403 | 401 dispara un solo refresh; 403 conserva usuario y muestra insuficiencia | `VALIDADO` en interceptor; falta recorrido de página |
| Secretaría | alumno → inscripción → cargo → pago → recibo/caja, sin IDs visibles | `NO_VERIFICADO`, `E2-010` |
| Profesor | sólo disciplinas/asistencias propias, si el rol queda habilitado | `BLOCKED` por ownership |
| Responsive | representación desktop/mobile mantiene el mismo contenido y acciones sin queries ambiguas | un fallo baseline, `E2-010` |

Al terminar una tarea frontend:

```powershell
Push-Location .\frontend
try {
    npm test
    npm run lint
    npm run build
}
finally {
    Pop-Location
}
```

## Unitarios backend

Priorizar servicios y estados puros; usar mocks sólo alrededor de repositorios o límites externos.

| Área | Casos obligatorios |
|---|---|
| RBAC | permiso activo, rol activo, suma de roles, delegación sin escalamiento, último SUPERADMIN y excepción de autorización distinta de conflicto |
| Tokens/sesión | access/refresh no intercambiables, firma/issuer/expiración, `authVersion`, usuario/rol inactivo y reuse de refresh |
| Liquidación | `BigDecimal`, escala/redondeo, prioridad aprobada, ausencia de tarifa y `formula_version` |
| Estados de negocio | baja/reactivación/finalización/anulación/reversión e idempotencia |
| Fechas | `Clock`/zona Buenos Aires y límites de vigencia; no depender de la hora de la máquina |

Ejemplo focalizado, reemplazando las clases por las afectadas por la tarea:

```powershell
Push-Location .\backend
try {
    .\mvnw.cmd -Dtest="TokenServiceTest,AutenticacionServiceTest,RolServicioTest,UsuarioServicioTest" test
}
finally {
    Pop-Location
}
```

## MockMvc / contrato HTTP

`SecurityHttpIntegrationTest` ya cubre autenticación, tokens, actividad, `authVersion`, algunos permisos y sanitización de 500. En `E1-004`, `E1-005` y `E1-010` debe transformarse o complementarse con una matriz parametrizada.

Cada fila de [02_MATRIZ_RBAC.md](./02_MATRIZ_RBAC.md) debe probar:

1. sin credencial: 401 con cuerpo estable `UNAUTHORIZED`;
2. credencial válida sin el permiso requerido: 403, sin refresh ni mutación;
3. permiso requerido activo: status funcional esperado;
4. rol o permiso inactivo: 403;
5. conflicto real de dominio con autoridad suficiente: 409;
6. write forzado por URL/API: misma denegación que la UI;
7. operaciones financieras sensibles: matcher/controller y defensa de servicio.

Casos adicionales: CORS/origen de refresh y logout, error 500 sin detalles internos, escalamiento, último SUPERADMIN, ownership cruzado y WebSocket según la opción aprobada.

```powershell
Push-Location .\backend
try {
    .\mvnw.cmd -Dtest="SecurityHttpIntegrationTest" test
}
finally {
    Pop-Location
}
```

## PostgreSQL y Testcontainers

Cobertura existente relevante: `PostgreSqlSchemaValidationTest`, `SuperadminBootstrapPostgreSqlTest`, `RefreshSessionPostgreSqlTest`, `PagoCanonicoPostgreSqlTest`, `CargoSaldoPostgreSqlTest`, `TarifaDisciplinaPostgreSqlTest`, `CondicionEconomicaPostgreSqlTest`, `CargoLiquidacionMigrationPostgreSqlTest`, pruebas de caja, idempotencia, schedulers y auditorías SQL.

Casos obligatorios de hardening:

- unicidad y reconciliación de catálogo/roles/asignaciones RBAC;
- base limpia y upgrade desde la versión inmediatamente anterior;
- dos profesores con datos propios y acceso cruzado denegado desde query/servicio;
- vigencia exacta, anterior más reciente, tarifa futura, hueco y solapamiento rechazado;
- cargo + snapshot atómicos; retry y concurrencia sin duplicado;
- pagos, crédito, caja, egresos y stock conservan exactitud y reversión;
- schedulers/manual comparten ruta e idempotencia respaldada por constraints;
- consultas de huérfanos e inconsistencias devuelven cero o un reporte explícito.

```powershell
Push-Location .\backend
try {
    .\mvnw.cmd -Dtest="PostgreSqlSchemaValidationTest,SuperadminBootstrapPostgreSqlTest,RefreshSessionPostgreSqlTest,PagoCanonicoPostgreSqlTest,CargoSaldoPostgreSqlTest,TarifaDisciplinaPostgreSqlTest,CondicionEconomicaPostgreSqlTest,CargoLiquidacionMigrationPostgreSqlTest" test
}
finally {
    Pop-Location
}
```

Docker Engine debe estar disponible. Un fallo `Could not find a valid Docker environment` es bloqueo de entorno, no aprobación ni defecto funcional clasificado.

## Flyway: base limpia y upgrade

### Etapa 1

- V1–V5 se mantuvieron sin cambios.
- Una base limpia migró a V6 y JPA validó el esquema.
- Otra base migró con `target("5")`, recibió casos representativos permitidos por V5 y actualizó a V6.
- Se verificaron checksum/orden, catálogo completo, matrices determinísticas, IDs, usuarios, roles personalizados, `usuario_roles`, datos de negocio y actualización selectiva de `auth_version`.
- Los asserts de catálogo/matriz se actualizaron sin debilitar los contratos estructurales de V5 ni depender del seed demo.

### Etapa 1B y posteriores

Repetir el patrón desde la versión inmediatamente anterior. Toda migración con datos incluye precondiciones, conteos de reconciliación, filas ambiguas reportadas y recovery forward-only.

Comando soportado para ambas variantes, implementadas dentro del test Testcontainers:

```powershell
Push-Location .\backend
try {
    .\mvnw.cmd -Dtest="PostgreSqlSchemaValidationTest,*MigrationPostgreSqlTest" test
}
finally {
    Pop-Location
}
```

## Contratos de permisos, rutas y seeds

Debe existir una comparación automatizada entre:

- constantes backend utilizadas por matchers, anotaciones y servicios;
- catálogo Flyway activo;
- asignaciones de roles aprobadas;
- `frontend/src/config/permissions.ts`;
- metadata de `routes.ts` y `navigation.ts`;
- permisos de acciones sensibles.

El contrato falla ante permiso usado pero no sembrado, sembrado pero desconocido, string ad hoc, ruta protegida sin política, write sin permiso granular o rol que recibe un permiso no delegable. Una allowlist temporal sólo es válida con ID de decisión, razón y condición de retiro.

Pruebas mínimas:

- backend: contrato del catálogo más matriz HTTP;
- frontend: metadata/navegación/rutas/acciones;
- integración: bootstrap SUPERADMIN puede hacer el primer GET sin seed demo;
- búsqueda `rg` como evidencia auxiliar, nunca como sustituto de la prueba HTTP.

## E2E por rol

No hay un E2E de navegador por rol validado en el baseline. En Etapa 4 se reutiliza primero el stack/smoke existente y una herramienta ya disponible; no se agrega dependencia hasta demostrar que hace falta.

| Rol | Recorrido permitido mínimo | Intento denegado obligatorio |
|---|---|---|
| SUPERADMIN | recuperación/bootstrap y administración técnica | no se usa como cuenta operativa de demo |
| DIRECCION | configuración, negocio y reportes según matriz aprobada | acción de seguridad no delegada, si corresponde |
| SECRETARIA | alumno → inscripción → cargo → pago → recibo → caja; asistencia operativa | anular pago o administrar seguridad por defecto |
| CAJA | buscar alumno, registrar pago y consultar caja | editar configuración o anular pago por defecto |
| PROFESOR | rol inactivo, cero permisos, no asignable y sin rutas | cualquier acceso operativo |

Profesor no entra a un recorrido permitido en esta release: se prueba que el rol permanece deshabilitado. Un E2E de ownership con dos profesores es condición de una release futura.

## Smoke local aislado

`scripts/smoke-local.ps1` crea proyecto Compose, puertos y secretos efímeros, migra V1–V6, hace bootstrap, prueba HTTP/SQL y elimina contenedores, volúmenes y redes. Valida 32 permisos, matrices exactas, actores negativos y ausencia de dependencia del seed demo.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\smoke-local.ps1
```

Diagnóstico consciente, sólo si hace falta conservar el stack efímero:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\smoke-local.ps1 -KeepStack -VerboseHttp
```

El smoke de GATE-1 demostró migración limpia, SUPERADMIN/catálogo operativo, login, perfil, primer GET, 401/403/409, integridad básica, persistencia tras reinicio y cero seed demo. El smoke de release deberá ampliarse nuevamente al integrar Partes B, C y D.

## Checklist responsive y accesibilidad

Revisar al menos el recorrido crítico en 375×812, 768×1024 y 1440×900:

- [ ] navegación y acciones alcanzables sin scroll horizontal accidental;
- [ ] contenido desktop/mobile equivalente sin controles duplicados activos;
- [ ] foco visible y orden lógico con teclado;
- [ ] comboboxes operables con flechas, Enter y Escape;
- [ ] label/nombre accesible en inputs, icon buttons y acciones;
- [ ] errores vinculados al campo y resumen accionable;
- [ ] dialogs conservan foco, bloquean doble submit y lo devuelven al cerrar;
- [ ] loading, success y error se anuncian sin depender sólo de color;
- [ ] botones deshabilitados explican la condición cuando corresponde;
- [ ] zoom 200 % no oculta acciones críticas;
- [ ] fechas, moneda, estados y referencias son humanos y consistentes;
- [ ] un permiso denegado no destruye la sesión ni deja una pantalla en loop.

Registrar navegador/versión, viewport, rol, recorrido y resultado. Una captura apoya la evidencia visual, pero no reemplaza las aserciones funcionales.

## Comandos de gate desde PowerShell

Desde la raíz del checkout:

```powershell
git status --short --branch
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Frontend
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Backend
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope All
```

Después de Etapa 1 y al preparar release:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\smoke-local.ps1
```

`-Scope All` incluye `docker compose config --quiet`; no inicia el stack. El smoke sí inicia recursos aislados de forma consciente y los elimina por defecto.

## Evidencia requerida en bitácora

Por cada tarea terminada registrar:

1. SHA/branch y archivos probados;
2. comando exacto;
3. status final y conteos;
4. fallos preexistentes, introducidos, de entorno o skips por separado;
5. base/imagen/versiones relevantes sin secretos;
6. decisión o bloqueo asociado;
7. riesgo residual y próxima única tarea.

GATE-1 está cerrado localmente porque todas sus pruebas obligatorias terminaron en exit 0. Permanece abierto para integración hasta que el PR tenga checks remotos verdes y el merge a `main` esté confirmado.
