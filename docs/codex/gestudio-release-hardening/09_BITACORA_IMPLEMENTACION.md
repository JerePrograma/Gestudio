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

## Próxima entrada requerida

Registrar la respuesta a `DEC-RBAC-001`. Si se aprueba, cerrar `E1-001`, marcar únicamente `E1-002` como `IN_PROGRESS`, anotar archivos antes de editarlos y registrar cada comando/test. Si se rechaza o corrige, actualizar primero matriz y decisión; no crear V6 hasta entonces.
