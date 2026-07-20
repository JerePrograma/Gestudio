# Gestudio release hardening — tablero maestro

Última actualización: 2026-07-20 (`America/Argentina/Buenos_Aires`).

## Estado ejecutivo

| Campo | Estado |
|---|---|
| Repositorio | `JerePrograma/Gestudio` |
| Rama operativa | `main` |
| Baseline funcional auditado | `3f314ba8cc61a71bfa434a46593cd02336ec16e5` |
| Working tree del usuario | No verificado desde la revisión remota |
| Etapa técnica disponible | Etapa 1B — liquidación financiera por vigencia |
| Último gate cerrado | `GATE-1` — Seguridad/RBAC integrado en `main` |
| Gate activo recomendado | `GATE-1B` — listo para comenzar; implementación pendiente |
| Demo interna | `BLOCKED` por evidencia ejecutada faltante |
| Staging / producción | `NO-GO` |
| Próxima tarea de código | `E1B-001` — caracterizar cálculo vigente |
| Próxima tarea de evidencia | `DEMO-VAL-001` — validar el seed sobre HEAD actual |

## Advertencia de continuidad

Las entradas históricas que hablen de:

- `feat/rbac-production-hardening` como rama activa;
- un PR RBAC reemplazante pendiente;
- `origin/main` anterior a `3f314ba8`;
- Etapa 1B bloqueada por el merge de RBAC;

representan el estado previo a la integración y no deben usarse como instrucción
operativa actual.

La fuente canónica para continuidad es
[12_ESTADO_ACTUAL_Y_BACKLOG.md](./12_ESTADO_ACTUAL_Y_BACKLOG.md).

## Fuentes de verdad

1. [Baseline y hallazgos](./01_BASELINE_Y_HALLAZGOS.md)
2. [Matriz RBAC](./02_MATRIZ_RBAC.md)
3. [Etapa 1 — Seguridad/RBAC](./03_ETAPA_1_SEGURIDAD_RBAC.md)
4. [Etapa 1B — Liquidación financiera](./04_ETAPA_1B_LIQUIDACION_FINANCIERA.md)
5. [Etapa 2 — UX operativa](./05_ETAPA_2_UX_OPERATIVA.md)
6. [Etapa 3 — Componentes y contratos](./06_ETAPA_3_COMPONENTES_Y_CONTRATOS.md)
7. [Etapa 4 — Demo y publicación](./07_ETAPA_4_DEMO_Y_PUBLICACION.md)
8. [Plan de pruebas](./08_PLAN_DE_PRUEBAS.md)
9. [Bitácora histórica](./09_BITACORA_IMPLEMENTACION.md)
10. [Decisiones y bloqueos](./10_DECISIONES_Y_BLOQUEOS.md)
11. [Checklist de release](./11_CHECKLIST_RELEASE.md)
12. [Estado actual y backlog maestro](./12_ESTADO_ACTUAL_Y_BACKLOG.md)
13. [Bitácora de continuidad](./13_BITACORA_CONTINUIDAD.md)
14. [Auditoría técnica de GATE-1B](./14_AUDITORIA_TECNICA_E1B.md)

Documentación relacionada:

- [Estrategia comercial canónica](../../comercial/estrategia-comercial.md)
- [Demo local persistente](../../testing/demo-local.md)
- [Dataset de demostración](../../testing/demo-seed.md)
- [Auditoría histórica del seed](../../../12_AUDITORIA_SEED_DEMO.md)

## Progreso por etapa

| Etapa | Estado | Gate | Condición siguiente |
|---|---|---|---|
| 0 — Baseline y documentación | `DONE` | `GATE-0 CERRADO` | Mantener documentos reconciliados |
| 1 — Seguridad y RBAC | `DONE / INTEGRADO` | `GATE-1 CERRADO` | No reabrir salvo regresión comprobada |
| 1B — Liquidación por vigencia | `READY_TO_START` | `GATE-1B ABIERTO` | Iniciar `E1B-001` con caracterización |
| 2 — UX operativa | `PARTIAL` | `GATE-2 ABIERTO` | Retomar después de estabilizar cálculo financiero |
| 3 — Componentes/contratos | `PENDING` | subordinado a 1B/2 | Extraer sólo contratos necesarios |
| 4 — Demo/publicación | `PREPARACIÓN PARCIAL` | demo interna bloqueada | Ejecutar validaciones y recorridos humanos |
| Staging | `PENDING / NO AUTORIZADO` | `NO-GO` | Ambiente, secretos, TLS, restore y rollback |
| Producción | `PENDING / NO AUTORIZADO` | `NO-GO` | Todos los gates y autorización explícita |

## Evidencia integrada conocida

| Alcance | Evidencia histórica |
|---|---|
| Backend RBAC | 129/129 tests |
| Frontend RBAC | 140/140 tests, lint y build |
| Validación integrada RBAC | `Scope All PASS` |
| Smoke RBAC | 20/20 |
| Flyway | V1-V6; V6 catálogo y matrices |
| Seed demo | Script reconstruido e integrado; 914 filas esperadas |
| Demo persistente | Lanzador y guía integrados |
| Comercial | Estrategia canónica integrada |
| UX | Mejoras parciales en tablas, búsqueda y roles |
| GATE-1B | Auditoría estática completa; código y tests pendientes |

Esta evidencia no reemplaza una repetición sobre el HEAD actual.

## Reglas operativas vigentes

- V1-V6 permanecen inmutables; toda corrección de esquema es forward-only.
- El seed demo no es migración ni catálogo productivo.
- `PROFESOR` permanece inactivo, sin permisos y no asignable.
- Sin autenticación = 401; sin permiso = 403; conflicto real = 409.
- STOMP permanece retirado; primera release usa REST/email.
- Observaciones de profesores permanece fuera de superficie.
- No hay fallback financiero a campos legacy después de cerrar GATE-1B.
- No se marca una tarea `DONE` sin evidencia ejecutada.
- No se inicia staging ni producción sin autorización explícita.
- El usuario trabaja directamente sobre `main`; la documentación no prescribe crear ramas.

## Próximo orden de ejecución

1. repetir suites, smoke y validación del seed sobre HEAD actual;
2. corregir cualquier fallo de demo;
3. iniciar `E1B-001` conforme a `14_AUDITORIA_TECNICA_E1B.md`;
4. cerrar GATE-1B;
5. completar UX crítica;
6. aprobar demo interna;
7. preparar staging con restore y rollback;
8. evaluar producción.

## Decisión actual

**`NO-GO` para staging y producción.**

El repositorio está habilitado para continuar desarrollo y validación local. No
está autorizado para declarar operación productiva.

<!-- GATE1B-INDEX-2026-07-20 -->
## Cierre de Etapa 1B

- [`15_CIERRE_GATE_1B_2026-07-20.md`](15_CIERRE_GATE_1B_2026-07-20.md): evidencia consolidada, contrato implementado, pruebas, demo, riesgos y decisión global.
