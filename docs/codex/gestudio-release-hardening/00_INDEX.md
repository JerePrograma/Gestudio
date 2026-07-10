# Gestudio release hardening — tablero maestro

Última actualización: 2026-07-10 (America/Argentina/Buenos_Aires).

## Estado ejecutivo

| Campo | Estado |
|---|---|
| Baseline Git | `VALIDADO`: `main` y `origin/main` en `b833f6741cf614c508666e8a121701e8db2fcf9a` |
| Working tree inicial | `VALIDADO`: limpio, sin cambios staged ni unstaged |
| Etapa actual | Etapa 1 — Seguridad y RBAC mínimo publicable |
| Única tarea activa | `E1-001` — congelar contrato y matriz RBAC (`IN_PROGRESS`) |
| Último gate cerrado | `GATE-0` — baseline y documentación |
| Gate actual | `GATE-1` — abierto |
| Bloqueo de autoridad | `BLK-001`: confirmar `DEC-RBAC-001`, la matriz de roles/permisos |
| Próximo paso exacto | Confirmar o corregir `DEC-RBAC-001`; luego ejecutar `E1-002` sin modificar V1–V5 |

## Baseline de validación

| Alcance | Comando | Resultado |
|---|---|---|
| Frontend | `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Frontend` | `CLASIFICADO`: lint `PASS`, tests `FAIL` con 33/36 y tres fallos preexistentes, build `PASS` |
| Backend | `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Backend` | `PASS`: `clean verify`, 115/115 tests, PostgreSQL 15 vía Testcontainers, `BUILD SUCCESS` |
| Git remoto | protocolo de la consigna, incluido `git fetch origin --prune` | `PASS`: HEAD = `origin/main` = commit auditado |

Los tres fallos frontend y su clasificación están detallados en [01_BASELINE_Y_HALLAZGOS.md](./01_BASELINE_Y_HALLAZGOS.md). No se considera verde la suite frontend.

## Documentos fuente de verdad

1. [Baseline y hallazgos](./01_BASELINE_Y_HALLAZGOS.md)
2. [Matriz RBAC](./02_MATRIZ_RBAC.md)
3. [Etapa 1 — Seguridad/RBAC](./03_ETAPA_1_SEGURIDAD_RBAC.md)
4. [Etapa 1B — Liquidación financiera](./04_ETAPA_1B_LIQUIDACION_FINANCIERA.md)
5. [Etapa 2 — UX operativa](./05_ETAPA_2_UX_OPERATIVA.md)
6. [Etapa 3 — Componentes y contratos](./06_ETAPA_3_COMPONENTES_Y_CONTRATOS.md)
7. [Etapa 4 — Demo y publicación](./07_ETAPA_4_DEMO_Y_PUBLICACION.md)
8. [Plan de pruebas](./08_PLAN_DE_PRUEBAS.md)
9. [Bitácora de implementación](./09_BITACORA_IMPLEMENTACION.md)
10. [Decisiones y bloqueos](./10_DECISIONES_Y_BLOQUEOS.md)
11. [Checklist de release](./11_CHECKLIST_RELEASE.md)

## Progreso por etapa

| Etapa | Estado | Gate | Evidencia / condición siguiente |
|---|---|---|---|
| 0 — Baseline y documentación | `DONE` | `GATE-0 CERRADO` | 12 documentos cruzados; Git y validaciones clasificados; P0 con tareas/pruebas |
| 1 — Seguridad y RBAC | `IN_PROGRESS` | `GATE-1 ABIERTO` | `E1-001` espera decisión de matriz antes de cambiar autoridad persistida |
| 1B — Liquidación por vigencia | `PENDING` | no autorizado | Sólo después de GATE-1 y autorización explícita |
| 2 — UX operativa | `PENDING` | no autorizado | Sólo después de GATE-1B y autorización explícita |
| 3 — Componentes/contratos | `PENDING` | no autorizado | Sólo después de GATE-2 y autorización explícita |
| 4 — Demo/publicación | `PENDING` | no autorizado | Sólo después de GATE-3 y autorización explícita |

## Definición de estados

- `PENDING`: definida pero todavía no iniciada.
- `IN_PROGRESS`: única tarea activa; no puede coexistir con otra tarea en ese estado.
- `BLOCKED`: no puede continuar sin autoridad, dato o cambio de entorno identificado.
- `DONE`: criterios de aceptación y evidencia requeridos completos.
- `DEFERRED`: fuera del alcance autorizado, con razón y condición de reapertura.

## Reglas operativas vigentes

- V1–V5 forman la cadena Flyway activa observada. V1 queda congelada y no se reescribe V5; el próximo cambio aprobado será forward-only.
- No se usa el seed demo como catálogo productivo.
- No se habilita `PROFESOR` hasta probar ownership backend o dejarlo expresamente inactivo.
- Sin token = 401; token válido sin permiso = 403; conflicto de negocio = 409.
- No se avanza a Etapa 1B sin cerrar GATE-1 y obtener autorización explícita.
- Se preservan `.env.*.local`, backups y otros artefactos locales ignorados; no se leen ni se incluyen.

## GATE-0 — evidencia de cierre

- [x] 12 documentos existen y se enlazan desde este índice.
- [x] Git, stack, frontend y backend están clasificados.
- [x] La matriz RBAC cubre módulos, rutas, endpoints, permisos y ownership.
- [x] Cada P0 tiene tarea, aceptación y prueba prevista.
- [x] Las decisiones financieras abiertas están registradas para Etapa 1B.
- [x] Etapa actual = 1; única tarea activa = `E1-001`.

El cierre de GATE-0 no declara el producto listo ni la seguridad resuelta. Sólo habilita el comienzo controlado de Etapa 1.
