# Bitácora de implementación

Zona horaria: America/Argentina/Buenos_Aires (`-03:00`). Las horas de esta primera entrada son horas de registro de la evidencia; los comandos y resultados exactos prevalecen sobre la marca temporal. Ver [tablero](./00_INDEX.md), [baseline](./01_BASELINE_Y_HALLAZGOS.md) y [decisiones/bloqueos](./10_DECISIONES_Y_BLOQUEOS.md).

## 2026-07-10

### 14:00 — `E0-001` verificar Git y AGENTS

- Estado: `DONE`.
- Archivos inspeccionados: `AGENTS.md`; metadata Git.
- Decisión: trabajar sobre `main` sin mover refs y preservar ignorados locales.
- Pruebas/comandos: `git status --short --branch`, `git branch --show-current`, `git rev-parse HEAD`, `git fetch origin --prune`, `git rev-parse origin/main`, `git log -1 --oneline`, `git diff --exit-code`, `git diff --cached --exit-code`.
- Resultado: `HEAD = origin/main = b833f6741cf614c508666e8a121701e8db2fcf9a`; árbol inicial limpio.
- Deuda/seguimiento: ninguna de Git. Se preservan `.env.*.local`, `basebackup/` y caches ignoradas.

### 14:05 — `E0-002` baseline frontend

- Estado: `DONE` con suite clasificada roja.
- Archivos de evidencia: `scripts/codex/validate.ps1`, `frontend/package.json`, `AlumnosPagina.test.tsx`, `PagosPagina.test.tsx`.
- Decisión: no adaptar pruebas para ocultar fallos; mover su corrección a `E2-010`.
- Prueba: `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Frontend`.
- Resultado: lint `PASS`; tests 33/36; build `PASS`. Un fallo por DOM desktop/mobile duplicado y dos por `$ 100.50` frente a `$ 100,50`.
- Deuda/seguimiento: tres fallos preexistentes; frontend no se declara verde.

### 14:10 — `E0-003` baseline backend

- Estado: `DONE`.
- Archivos de evidencia: `scripts/codex/validate.ps1`, `backend/pom.xml`, `PostgreSqlIntegrationTest.java`.
- Decisión: PostgreSQL/Testcontainers es la prueba de semántica SQL; no sustituir por H2.
- Prueba: `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Backend`.
- Resultado: `clean verify` `PASS`, 115/115 tests, PostgreSQL 15 mediante Testcontainers, `BUILD SUCCESS`.
- Deuda/seguimiento: Docker es prerrequisito para repetir el gate.

### 14:14 — `E0-004` inventario de rutas, endpoints y permisos

- Estado: `DONE`.
- Archivos: controllers backend, `SecurityConfigurations.java`, `RbacService.java`, `frontend/src/rutas/`, `config/permissions.ts`, `config/navigation.ts`.
- Decisión: mantener IDs estables `P0-SEC-001..015`; no inventar permisos fuera de la matriz.
- Pruebas/inspección: búsquedas `rg` de mappings, matchers, authorities, permisos, rutas y guards.
- Resultado: matriz documentada en [02_MATRIZ_RBAC.md](./02_MATRIZ_RBAC.md); se confirmó fallback general APP_ACCESS y huecos granulares.
- Deuda/seguimiento: `DEC-RBAC-001` requiere autoridad antes de persistir la matriz.

### 14:18 — `E0-005` seeds y bootstrap

- Estado: `DONE`.
- Archivos: V1, V2, V5, `PostgreSqlSchemaValidationTest.java`, `SuperadminBootstrapService.java`, `scripts/gestudio_demo_seed_full.sql`.
- Decisión: V1-V5 forman la cadena activa; no reescribir V5; siguiente cambio RBAC será V6 forward-only.
- Pruebas/inspección: lectura completa de migraciones y asserts de schema/bootstrap.
- Resultado: V5 crea estructura sin catálogo; tests exigen cero permisos; bootstrap no garantiza matriz; seed demo no es productivo.
- Deuda/seguimiento: `P0-SEC-001..005`, tareas `E1-002` y `E1-003`.

### 14:21 — `E0-006` cálculo financiero real

- Estado: `DONE` como auditoría, no como corrección.
- Archivos: `MensualidadServicio.java`, `MatriculaServicio.java`, `LiquidacionCargoServicio.java`, `backend/src/main/java/gestudio/tarifas/`, V3, V4 y pantallas de tarifas/condiciones.
- Decisión: registrar `DEC-PRICING-001`; no cambiar importes antes de autorización y caracterización.
- Pruebas/inspección: búsqueda de callers y lectura de servicios/repositorios.
- Resultado: mensualidad/matrícula leen legacy; repositorios efectivos y tabla snapshot existen; el registrador de liquidación no está integrado.
- Deuda/seguimiento: `P0-FIN-001..006`, tareas `E1B-001..007`; Etapa 1B no autorizada.

### 14:24 — `E0-007` UX, IDs y búsquedas técnicas

- Estado: `DONE` como inventario.
- Archivos: páginas/formularios frontend y repositorios/controllers relacionados listados en [baseline](./01_BASELINE_Y_HALLAZGOS.md#hallazgos-p1-uxfuncionales).
- Decisión: asignar `P1-UX-001..022` y postergar cambios a Etapa 2, salvo guards de seguridad de Etapa 1.
- Pruebas/inspección: `rg` de IDs visibles, `idBusqueda`, acciones, fechas UTC, rutas y formatos.
- Resultado: 22 hipótesis clasificadas con ruta y tarea.
- Deuda/seguimiento: Etapa 2 no autorizada.

### 14:27 — `E0-008` documentación y cierre GATE-0

- Estado: `DONE`.
- Archivos: `docs/codex/gestudio-release-hardening/00_INDEX.md` a `11_CHECKLIST_RELEASE.md`.
- Decisión: documentación como fuente de verdad; sólo una tarea `IN_PROGRESS`.
- Pruebas: verificación de enlaces/IDs y `git diff --check` al cierre documental.
- Resultado: GATE-0 cerrado; baseline y P0/P1 clasificados; Etapa actual = 1.
- Deuda/seguimiento: el producto no está listo; cerrar GATE-0 sólo habilita Etapa 1.

### 14:28 — `E1-001` congelar contrato y matriz RBAC

- Estado: `IN_PROGRESS` (única tarea activa).
- Archivos documentales: `02_MATRIZ_RBAC.md`, `03_ETAPA_1_SEGURIDAD_RBAC.md`, `10_DECISIONES_Y_BLOQUEOS.md`.
- Decisión: proponer matriz mínima, pero no cambiar migraciones/código antes de aprobación de `DEC-RBAC-001`.
- Pruebas: suite RBAC frontend focalizada 15/15 `PASS`; no se ejecutó cambio productivo.
- Resultado: catálogo actual y propuesta trazados; `BLK-001` impide `E1-002`.
- Deuda/seguimiento: obtener confirmación explícita de `DEC-RBAC-001`.

### 18:49 — `E0-008` completar los documentos faltantes desde `088a0b33`

- Estado: `DONE` como reparación documental; no reabre GATE-0 ni cambia la tarea activa `E1-001`.
- Archivos creados: `02_MATRIZ_RBAC.md`, `03_ETAPA_1_SEGURIDAD_RBAC.md`, `08_PLAN_DE_PRUEBAS.md`, `10_DECISIONES_Y_BLOQUEOS.md`. Ajuste puntual: `11_CHECKLIST_RELEASE.md` para reconciliar resultados baseline y el estado documental ya cerrado.
- Decisión: conservar el baseline de código `b833f674`, registrar que `088a0b33` sólo agregó documentación, usar exactamente 15 permisos actuales + 17 propuestos y no inferir ninguna aprobación.
- Pruebas/comandos: `git status --short --branch`, `git show -s`, `git fetch origin --prune`, verificación automatizada de 12 archivos/enlaces/anchors/IDs/tablas/estados, cruce de 29 familias de controllers, comparación de 15 permisos usados y auditoría del seed demo, `git diff --check` y `git diff --no-index --check` para archivos nuevos.
- Resultado: 12/12 documentos presentes; enlaces y anchors válidos; 8 decisiones y 3 bloqueos definidos; catálogo actual 15/15; propuesta 17/17; E1 conserva 1 `IN_PROGRESS`, 1 `BLOCKED` y 8 `PENDING`; seed demo conserva 14 códigos y omite `PERM_TARIFAS_HISTORICAS` como estaba documentado.
- Validación no ejecutada: no se repitieron suites de aplicación porque el cambio es sólo Markdown; siguen vigentes los resultados exactos del baseline y los gates abiertos.
- Deuda/seguimiento: `BLK-001` continúa; la próxima entrada sigue siendo la respuesta explícita a `DEC-RBAC-001`.

## 2026-07-11

### 20:57 — baseline del primer bloque real de Etapa 1

- Estado: `DONE` con fallos preexistentes/ambientales clasificados.
- Git: `main = origin/main = 407e1cbcc277b4b6c385cddface2862259e87036`; árbol inicial limpio. Se ejecutaron `git status`, `git log --oneline -5`, listado de `docs/codex/gestudio-release-hardening`, protocolo Git del megaprompt y lectura completa de las instrucciones/documentos obligatorios.
- Frontend antes de cambios: `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Frontend` terminó lint `PASS`, tests 33/36 y build `PASS`. Fallaron los mismos casos ya documentados: uno de Alumnos por dos representaciones responsive de `Ana Prueba` y dos de Pagos por `$ 100.50` frente a `$ 100,50`.
- Backend antes de cambios: `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Backend` compiló y ejecutó 90 tests: 0 fallos y 16 errores de Testcontainers por `Could not find a valid Docker environment`; `BUILD FAILURE`. Las suites Java no dependientes de contenedor, incluidas Seguridad HTTP 17/17, Roles 5/5 y Usuarios 6/6, pasaron.
- Clasificación: los tres fallos frontend son preexistentes; el backend está bloqueado por Docker no disponible. Ninguno fue causado por este bloque y no se instaló ni arrancó infraestructura para ocultarlos.

### 21:00 — diagnóstico y alcance exacto Usuarios/Roles

- Estado: `DONE`.
- Inventario: backend y frontend declaran los mismos 15 códigos `PERM_*`; Flyway siembra cero y el seed demo conserva 14. Usuarios/Roles ya tenían matchers y defensas de servicio con `PERM_USUARIOS_ADMIN` / `PERM_ROLES_ADMIN`, pero las acciones frontend consultaban `USUARIOS_WRITE` / `ROLES_WRITE`.
- Hallazgos incluidos: `/unauthorized` volvía a exigir `PERM_APP_ACCESO`; `RolServicio` aceptaba códigos persistidos `ROLE_*`, que luego se convertían en `ROLE_ROLE_*`; `SecurityHttpIntegrationTest` no montaba el controller real de permisos.
- Decisión: corregir únicamente esas inconsistencias usando el catálogo actual y conservar `ADMINISTRADOR`. No tocar `SecurityConfigurations`, migraciones, seeds, asignaciones, ownership Profesor, WebSocket, Pagos/Caja ni módulos académicos.
- Fuera de alcance confirmado: semántica 403 de `RbacService`, matriz comercial, V6, permisos nuevos y las acciones sensibles de los demás módulos.

### 21:03 — regresiones rojas y cambio mínimo

- Estado: `DONE`.
- Frontend rojo primero: `npm test -- src/funcionalidades/usuarios/UsuariosPagina.test.tsx src/funcionalidades/roles/RolesPagina.test.tsx src/rutas/ProtectedRoute.test.tsx` terminó 5/8, con los tres fallos esperados por los strings incorrectos y el permiso funcional de `/unauthorized`.
- Backend rojo primero: `.\mvnw.cmd -B -ntp "-Dtest=RolServicioTest" test` terminó 5/6 y demostró que `ROLE_OPERADOR` no era rechazado.
- Código productivo: `UsuariosPagina.tsx`, `RolesPagina.tsx`, `routes.ts` y `RolServicio.java`.
- Tests: `UsuariosPagina.test.tsx`, `RolesPagina.test.tsx`, `ProtectedRoute.test.tsx`, `RolServicioTest.java` y `SecurityHttpIntegrationTest.java`.
- Cambio: las acciones consumen constantes reales; `/unauthorized` queda fuera de `routePermissions` pero continúa bajo autenticación exterior; el normalizador rechaza el prefijo técnico; el test HTTP monta `PermisoControlador` y prueba 401/403/200 contra endpoints reales.
- Integridad: no se creó permiso, dependencia, migración ni abstracción; no se cambió autoridad persistida.

### 21:06 — validación focalizada y amplia post-cambio

- Estado del bloque Usuarios/Roles: `DONE` y sin regresiones nuevas conocidas.
- Frontend focalizado: el mismo comando de tres archivos terminó 8/8, exit 0. Tras la revisión final se reforzó el caso de `/unauthorized` para montar la composición de guards, probar anónimo → login y autenticado sin APP → página de autorización sin consultar un permiso funcional; la repetición terminó nuevamente 8/8.
- Backend focalizado: `.\mvnw.cmd -B -ntp "-Dtest=SecurityHttpIntegrationTest,UsuarioServicioTest,RolServicioTest" test` terminó 29/29, 0 fallos/errores, `BUILD SUCCESS`.
- Frontend amplio: `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Frontend` terminó lint `PASS`, tests 36/39 y build `PASS`, también después de reforzar el test de ruta. Persisten exactamente los tres fallos preexistentes; las tres pruebas RBAC agregadas pasan.
- Backend amplio: `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Backend` compiló y ejecutó 91 tests: 0 fallos, 16 errores y `BUILD FAILURE`, todos por el mismo bloqueo ambiental `Could not find a valid Docker environment`. Seguridad HTTP terminó 17/17, Roles 6/6 y Usuarios 6/6.
- Documentación actualizada: `02_MATRIZ_RBAC.md`, `03_ETAPA_1_SEGURIDAD_RBAC.md`, `06_ETAPA_3_COMPONENTES_Y_CONTRATOS.md` por una única referencia que había quedado obsoleta, esta bitácora, `10_DECISIONES_Y_BLOQUEOS.md` y `11_CHECKLIST_RELEASE.md`.
- Estado de etapa: `E1-001` permanece como única tarea `IN_PROGRESS`; `E1-002` y la matriz comercial continúan bloqueadas por `DEC-RBAC-001`. El cierre de este subconjunto no cierra GATE-1.

## 2026-07-14

### Baseline verificable de `feat/rbac-production-hardening`

- Estado inicial: `fix/ci-frontend-baseline` limpio en `f6493a3b1b7988a626c0742fe88ce75c2f1c4ee5`; `origin/fix/ci-frontend-baseline` en el mismo SHA y `origin/main` en `644e044b26438516ea093513ca5651ce72fb3fb3`.
- PR #11: abierto, draft y mergeable. Checks para `f6493a3b`: `validate PASS`, `build-images PASS`, `GitGuardian PASS`, `smoke FAIL` por `POST /api/salones`, esperado 201 y actual 403.
- Comandos Git: `git fetch --prune origin`, `git status --short --branch`, `git branch --show-current`, `git rev-parse HEAD`, `git rev-parse origin/main`, `git rev-parse origin/fix/ci-frontend-baseline`, `git log --oneline --decorate -10`, `git diff --check`. Todos terminaron en exit 0 y el árbol estaba limpio.
- Herramientas: Docker client/server 29.3.1 disponible; `JAVA_HOME` apunta a Corretto 21.0.7 y Maven Wrapper usa Java 21; Node 22.14.0; npm 10.9.2; GitHub CLI autenticado. El `java` global del `PATH` aún resuelve Java 8, por lo que las validaciones fijan explícitamente `JAVA_HOME\\bin` al comienzo del `PATH`.
- Rama: `git pull --ff-only` terminó sin cambios y se creó `feat/rbac-production-hardening` desde `f6493a3b`; no se movió `main`.

### Decisiones aprobadas y auditoría previa

- `DEC-RBAC-001`, `DEC-OWNERSHIP-001`, `DEC-WS-001`, `DEC-PRICING-001` y `DEC-OBS-001` quedaron resueltas por la consigna del 2026-07-14. `BLK-001` queda cerrado.
- Inventario backend: 29 familias REST, 143 mappings HTTP y un controller STOMP. Los 143 mappings quedaron clasificados; no hay `PATCH`. Se confirmaron fallback `/api/**` con sólo APP, matcher mensual huérfano, matcher de auditoría huérfano y denegaciones de servicio convertidas hoy en 409.
- Inventario DB: V1-V5 son la cadena activa; sólo existen `ADMINISTRADOR` y `SUPERADMIN`, cero permisos productivos y cero matriz en una base limpia. V1-V5 se registraron antes de editar con blobs `ca908e2a`, `0dea6a69`, `6096175`, `2d7a74d` y `5168f43a`.
- Inventario frontend: 15 permisos, 27 rutas autorizadas sólo con APP y gates de acciones limitados a Usuarios/Roles. STOMP está activo con origin `*`; Observaciones carece de ruta visible pero su API backend queda alcanzable por fallback.
- Baseline backend focalizado: `./mvnw.cmd -Dtest=PostgreSqlSchemaValidationTest,SuperadminBootstrapPostgreSqlTest,SuperadminBootstrapRunnerTest,SecurityHttpIntegrationTest,UsuarioServicioTest,RolServicioTest test` terminó `BUILD SUCCESS`, 36/36 tests, 0 fallos/errores/skips.
- Baseline smoke local: `powershell -NoProfile -ExecutionPolicy Bypass -File .\\scripts\\smoke-local.ps1` terminó exit 1, 6 verificaciones PASS y 1 FAIL. En Windows la sustitución de la cookie refresh agregó una cookie duplicada y el servidor siguió recibiendo la válida: el caso access-token-como-refresh esperaba 401 y obtuvo 200. El smoke remoto sí supera ese punto y reproduce el 403 de Salones.

### Cierre local de implementación RBAC — `DONE_LOCAL`

- V6: `V6__rbac_permission_catalog_and_base_roles.sql`, SHA-256 `12D766F5C66FD2DA8A7A59DA5534C068DE95F45A2FBE539EDDD135F19768B04A`; checksum Flyway runtime `735784832`.
- V1–V5 permanecen byte-identical: blobs `ca908e2a`, `0dea6a69`, `6096175`, `2d7a74d` y `5168f43a`.
- PostgreSQL: base limpia V1–V6 y upgrade V5→V6 preservaron IDs, usuarios, roles personalizados, `usuario_roles` y datos. Las sesiones afectadas incrementaron `auth_version`.
- Catálogo/matrices: 32 permisos activos/sistema; SUPERADMIN 32, DIRECCION 31, ADMINISTRADOR 31, SECRETARIA 17, CAJA 8 y PROFESOR 0/inactivo/no asignable.
- Backend: catálogo tipado, bootstrap fail-fast, `AccessDeniedException` para autoridad, conflictos de negocio en 409, 144/144 mappings con APP + permiso funcional y `/api/**` desconocido en `denyAll`.
- Frontend: catálogo de 32, sesión/rutas/navegación/acciones alineadas; Profesor excluido; `/unauthorized` autenticada; STOMP y Observaciones sin superficie.
- Canales: configuración/controller/publisher/hook/dependencias STOMP retirados; REST/email conservados; datos históricos de Observaciones no se borraron.
- Seed demo: cero `PERM_*`, cero `SUPERADMIN` y ninguna matriz productiva; sólo datos ficticios y asignación a rol existente.

### Validaciones y fallos observados

| Alcance | Comando | Resultado final | Conteo |
|---|---|---|---|
| Focalizado RBAC/PostgreSQL | `.\mvnw.cmd "-Dtest=PostgreSqlSchemaValidationTest,SuperadminBootstrapPostgreSqlTest,SuperadminBootstrapRunnerTest,SecurityHttpIntegrationTest,UsuarioServicioTest,RolServicioTest,TarifaDisciplinaPostgreSqlTest,CondicionEconomicaPostgreSqlTest" test` | `PASS` | 51/51 |
| Regresión auditoría | `.\mvnw.cmd "-Dtest=AuditServicePostgreSqlTest" test` | `PASS` | 7/7 |
| Backend | `validate.ps1 -Scope Backend` | `PASS` | 129/129, 0 fallos/errores/skips |
| Frontend | `validate.ps1 -Scope Frontend` | `PASS` | lint; 21 archivos/140 tests; build 2337 módulos |
| Integrado | `validate.ps1 -Scope All` | `PASS` | backend 129; frontend 140; lint/build/Compose |
| Smoke | `scripts/smoke-local.ps1` | `PASS`, 00:03:20 | 20/20; imágenes backend/frontend reconstruidas; limpieza completa |
| Compose | `docker compose config --quiet` | `PASS` | exit 0 |

- Primera validación Backend: 126 tests, 1 fallo introducido porque `CanonicalArchitectureContractTest` conservaba la lista V1–V5. Se actualizó a V1–V6 y se repitió verde.
- Primera corrida completa del smoke: 1 fallo real en `POST /api/usuarios/registro`, status 400. El diagnóstico mostró `VALIDATION_ERROR: La auditoría no admite secretos`: `AuditService` trataba `SECRETARIA` como secreto por substring. Se cambió la detección de valores a marcadores delimitados, se agregó regresión PostgreSQL y se repitieron Backend, All y smoke hasta exit 0.
- No hubo fallos aceptados, tests deshabilitados ni sustitución por H2.

### Estado Git y remoto al cierre local

- `HEAD` continúa en `f6493a3b` porque la implementación todavía no fue commiteada; no debe citarse como SHA final RBAC.
- PR #11 continúa abierto/draft con el smoke remoto rojo del baseline. El PR reemplazante todavía no existe.
- Próxima acción: revisar diff, crear commits temáticos, push de `feat/rbac-production-hardening`, crear PR draft, cerrar #11 como superseded sólo después y esperar checks remotos. Parte B no comienza antes del merge confirmado a `main`.
