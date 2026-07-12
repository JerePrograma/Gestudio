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

## Próxima entrada requerida

Registrar la respuesta a `DEC-RBAC-001`. Si se aprueba, cerrar `E1-001`, marcar únicamente `E1-002` como `IN_PROGRESS`, anotar archivos antes de editarlos y registrar cada comando/test. Si se rechaza o corrige, actualizar primero matriz y decisión; no crear V6 hasta entonces. En cualquier caso, repetir el backend amplio con Docker disponible antes de declarar el gate verde.
