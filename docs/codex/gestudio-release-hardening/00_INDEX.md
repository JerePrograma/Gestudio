# Gestudio release hardening — tablero maestro

Última actualización: 2026-07-14 (America/Argentina/Buenos_Aires).

## Estado ejecutivo

| Campo | Estado |
|---|---|
| Baseline Git | `VALIDADO`: rama fuente `fix/ci-frontend-baseline`, HEAD `f6493a3b`; `origin/main` `644e044b` |
| Working tree inicial | `VALIDADO`: limpio, sin cambios staged ni unstaged |
| Etapa actual | Etapa 1 — Seguridad y RBAC mínimo publicable |
| Trabajo activo | GATE-1: cierre de PR RBAC en `feat/rbac-production-hardening` |
| Último gate cerrado | `GATE-0` — baseline y documentación |
| Gate actual | `GATE-1` — validación local completa; publicación/checks/merge remotos pendientes |
| Decisión RBAC | `DEC-RBAC-001 TOMADA`; `BLK-001 CERRADO` |
| Próximo paso exacto | Crear commits temáticos, publicar el PR reemplazante, cerrar #11 como superseded y esperar checks remotos |

## Baseline de validación

| Alcance | Comando | Resultado |
|---|---|---|
| PR #11 / CI | checks del SHA `f6493a3b` | `validate PASS`, `build-images PASS`, `GitGuardian PASS`, `smoke FAIL` por Salones 403 |
| Backend focalizado inicial | seis clases RBAC/PostgreSQL | `PASS`: 36/36, 0 fallos/errores/skips |
| Smoke local inicial | `.\scripts\smoke-local.ps1` | `FAIL`: 6 PASS, 1 FAIL por reemplazo duplicado de cookie refresh en Windows |
| Git remoto | protocolo completo con `git fetch --prune origin` | `PASS`: refs y árbol limpio coinciden con el baseline esperado |

Estos resultados son el baseline histórico que motivó el cambio. El cierre local post-cambio está registrado en la [bitácora](./09_BITACORA_IMPLEMENTACION.md): backend 129/129, frontend 140/140, lint, build, Compose y smoke 20/20 terminaron en exit 0. GATE-1 no se considera integrado hasta que el PR reemplazante tenga checks remotos verdes y sea mergeado a `main`.

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
| 1 — Seguridad y RBAC | `LOCAL-VALIDATED` | `GATE-1 REMOTE-PENDING` | Implementación y evidencia local completas; faltan PR, checks y merge |
| 1B — Liquidación por vigencia | `PENDING` | gate de merge RBAC | Autorizada funcionalmente, pero sólo desde `main` actualizado después del PR RBAC verde |
| 2 — UX operativa | `PENDING` | gate de merge financiero | Sólo desde `main` actualizado después del PR financiero verde |
| 3 — Componentes/contratos | `PENDING` | subordinada a UX | Sin refactor general; sólo contratos necesarios para la release |
| 4 — Operación/publicación | `PENDING` | gate de merge UX | Preparación autorizada; despliegue externo sigue sin host, secretos ni autorización |

## Definición de estados

- `PENDING`: definida pero todavía no iniciada.
- `IN_PROGRESS`: única tarea activa; no puede coexistir con otra tarea en ese estado.
- `BLOCKED`: no puede continuar sin autoridad, dato o cambio de entorno identificado.
- `DONE`: criterios de aceptación y evidencia requeridos completos.
- `DEFERRED`: fuera del alcance autorizado, con razón y condición de reapertura.

## Reglas operativas vigentes

- V1–V5 permanecen byte-identical. V6 agrega el catálogo y las matrices RBAC de forma forward-only; una corrección futura requiere otra migración.
- No se usa el seed demo como catálogo productivo.
- No se habilita `PROFESOR` hasta probar ownership backend o dejarlo expresamente inactivo.
- Sin token = 401; token válido sin permiso = 403; conflicto de negocio = 409.
- No se avanza a Etapa 1B sin merge verde de GATE-1 a `main`; las ramas siguientes siempre nacen del `main` actualizado.
- Se preservan `.env.*.local`, backups y otros artefactos locales ignorados; no se leen ni se incluyen.

## GATE-0 — evidencia de cierre

- [x] 12 documentos existen y se enlazan desde este índice.
- [x] Git, stack, frontend y backend están clasificados.
- [x] La matriz RBAC cubre módulos, rutas, endpoints, permisos y ownership.
- [x] Cada P0 tiene tarea, aceptación y prueba prevista.
- [x] Las decisiones financieras abiertas están registradas para Etapa 1B.
- [x] Etapa actual = 1; única tarea activa = `E1-001`.

El cierre de GATE-0 no declara el producto listo ni la seguridad resuelta. Sólo habilita el comienzo controlado de Etapa 1.
