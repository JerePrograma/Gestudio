# Base de autoreferencia técnica de Gestudio

> Estado: PARCIAL  
> Última revisión: 2026-07-24  
> Fuentes principales: `../../AGENTS.md`, `../../README.md`, `../project-status-and-handoff.md`, código y configuración de `main`

## Propósito

Esta carpeta condensa el estado funcional, técnico y operativo de Gestudio para asistentes de IA y desarrolladores. No reemplaza el código: reduce el costo de orientación y obliga a distinguir evidencia de inferencia.

La base fue reconstruida contra el `main` remoto cuyo HEAD inspeccionado antes de esta actualización era `af099c880b1f18db018111e8720fb5c2bcd9280a`. El SHA del commit que contiene esta revisión no se auto-incrusta; se registra en el informe externo de publicación y en el historial Git.

## Fuentes de verdad

Orden de autoridad:

1. Código, migraciones, configuraciones y pruebas del `main` remoto.
2. [`AGENTS.md`](../../AGENTS.md), que define restricciones vigentes.
3. Documentación operativa y de release actual.
4. Esta base de autoreferencia.
5. `.kiro/`, que contiene material histórico o aspiracional y no describe por sí solo la implementación.

Etiquetas:

- **CONFIRMADO**: inspeccionado directamente.
- **INFERIDO**: deducción apoyada por evidencia.
- **PENDIENTE**: requiere inspección o decisión adicional.

## Resumen ejecutivo

Gestudio es un monolito modular cliente-servidor para administrar alumnos, inscripciones, disciplinas, profesores, asistencias, tarifas, condiciones económicas, matrículas, mensualidades, cargos, pagos, créditos, caja, egresos, inventario, recibos, reportes, notificaciones y usuarios/RBAC.

- Backend: Java 21, Spring Boot 3.5.16, PostgreSQL, JPA, Flyway y Maven Wrapper.
- Frontend: React 18, TypeScript 5.6, Vite 6 y React Router.
- Seguridad: JWT de acceso, refresh cookie `HttpOnly`, 32 permisos y autorización fail-closed.
- Operación: Docker Compose, PowerShell, Actuator/Prometheus, backup/restore y rollback forward-compatible.
- API: 146 mappings reales inventariados dinámicamente por prueba.
- UI: 32 rutas declaradas con matriz central de permisos.
- Release: existe evidencia local de validación del árbol de release del 22-07-2026; staging y producción no están acreditados.

## Mapa documental

| Documento | Finalidad |
|---|---|
| [01-project-overview.md](01-project-overview.md) | Propósito, actores y alcance |
| [02-repository-map.md](02-repository-map.md) | Estructura y puntos de entrada |
| [03-architecture.md](03-architecture.md) | Arquitectura y dependencias |
| [04-domain-model.md](04-domain-model.md) | Entidades, relaciones e invariantes |
| [05-functional-flows.md](05-functional-flows.md) | Flujos extremo a extremo |
| [06-backend-reference.md](06-backend-reference.md) | Backend Spring |
| [07-frontend-reference.md](07-frontend-reference.md) | Frontend React |
| [08-api-reference.md](08-api-reference.md) | Contratos REST |
| [09-data-and-persistence.md](09-data-and-persistence.md) | PostgreSQL, JPA y Flyway |
| [10-security.md](10-security.md) | Autenticación, autorización y secretos |
| [11-integrations.md](11-integrations.md) | Jere Platform, email y observabilidad |
| [12-development-guide.md](12-development-guide.md) | Preparación, ejecución y validación |
| [13-testing-strategy.md](13-testing-strategy.md) | Estrategia y gates |
| [14-build-deployment-operations.md](14-build-deployment-operations.md) | Build, CI, despliegue y recuperación |
| [15-coding-conventions.md](15-coding-conventions.md) | Convenciones reales |
| [16-change-impact-guide.md](16-change-impact-guide.md) | Análisis de impacto |
| [17-troubleshooting.md](17-troubleshooting.md) | Diagnóstico operativo |
| [18-known-risks-and-technical-debt.md](18-known-risks-and-technical-debt.md) | Riesgos y deuda |
| [19-decisions-and-rationale.md](19-decisions-and-rationale.md) | Decisiones y razones |
| [20-glossary.md](20-glossary.md) | Vocabulario |
| [21-open-questions.md](21-open-questions.md) | Preguntas pendientes |
| [22-source-index.md](22-source-index.md) | Trazabilidad |
| [23-ai-working-context.md](23-ai-working-context.md) | Contexto compacto para IA |
| [24-documentation-maintenance.md](24-documentation-maintenance.md) | Mantenimiento |
| [25-rbac-and-route-matrix.md](25-rbac-and-route-matrix.md) | Permisos, API y rutas UI |
| [26-scheduled-jobs.md](26-scheduled-jobs.md) | Tareas programadas |
| [27-remote-state-and-release-evidence.md](27-remote-state-and-release-evidence.md) | Estado remoto y evidencia |
| [28-demo-manual-and-certification.md](28-demo-manual-and-certification.md) | Demo, manual y certificación |

## Orden recomendado de lectura

1. Este índice.
2. [23-ai-working-context.md](23-ai-working-context.md).
3. Documento temático de la tarea.
4. [16-change-impact-guide.md](16-change-impact-guide.md).
5. [22-source-index.md](22-source-index.md).
6. Código real.

## Selección por tarea

| Tipo de tarea | Documentos mínimos |
|---|---|
| Corregir backend | 03, 06, 08, 13, 16, 18 |
| Modificar frontend | 05, 07, 08, 10, 15, 25 |
| Cambiar persistencia | 04, 09, 13, 16, 18 |
| Revisar seguridad | 08, 10, 13, 18, 25 |
| Preparar despliegue | 12, 14, 17, 27 |
| Operar demo/manual | 12, 17, 28 |
| Cambiar jobs | 04, 05, 09, 13, 26 |
| Integrar Jere Platform | 08, 10, 11, 14, 16 |
| Crear megaprompt para Codex | 23, 16, 13, 18, 21 |

## Advertencias críticas

- No tratar `.kiro/steering/ARCHITECTURE.md` como arquitectura actual.
- No modificar migraciones publicadas; la evolución es forward-only.
- No borrar físicamente historia financiera, asistencia, inscripciones o usuarios auditables.
- No duplicar cálculos financieros en frontend.
- Toda ruta `/api/**` no declarada queda denegada.
- La UI oculta rutas, pero la autoridad es Spring Security.
- No afirmar staging o producción por una validación local.
- No versionar `.env`, credenciales, dumps, backups, recibos ni artefactos de prueba.

## Pendientes principales

Los pendientes accionables están centralizados en [21-open-questions.md](21-open-questions.md). Los más relevantes son infraestructura productiva, transporte real a Jere Platform, entrega SMTP desplegada, política de retención, estabilización de respuestas legacy y cobertura cuantitativa actualizada.

## Protocolo de mantenimiento

Actualizar primero el documento temático y luego `22-source-index.md`, `23-ai-working-context.md` y este índice si cambian navegación o reglas críticas. No copiar código completo; referenciar rutas y símbolos. Las comprobaciones obligatorias están en [24-documentation-maintenance.md](24-documentation-maintenance.md).
