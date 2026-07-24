# Base de autoreferencia técnica de Gestudio

> Estado: PARCIAL  
> Última revisión: 2026-07-24  
> Fuentes principales: `README.md`, `backend/pom.xml`, `frontend/package.json`, documentación bajo `docs/`

## Propósito

Índice de contexto técnico verificable para asistentes de IA y desarrolladores. El código y las configuraciones reales siguen siendo la fuente definitiva.

## Resumen ejecutivo

Gestudio es un monorepo de gestión de alumnos, inscripciones, disciplinas, asistencias, mensualidades, pagos, inventario, caja, recibos y reportes. Usa Java 21/Spring Boot 3.5.16/PostgreSQL/Flyway en backend y React 18/TypeScript/Vite en frontend.

## Orden de lectura

1. [23-ai-working-context.md](23-ai-working-context.md)
2. [01-project-overview.md](01-project-overview.md)
3. [02-repository-map.md](02-repository-map.md)
4. Documento temático aplicable
5. [22-source-index.md](22-source-index.md)
6. Código real

## Navegación por tarea

| Tipo de tarea | Documentos |
|---|---|
| Corregir backend | arquitectura, backend, API, pruebas, impacto |
| Modificar frontend | frontend, flujos, API, convenciones |
| Cambiar persistencia | dominio, datos, impacto, pruebas |
| Revisar seguridad | seguridad, API, riesgos |
| Preparar despliegue | build/operaciones, troubleshooting |
| Crear megaprompt para Codex | contexto IA, impacto, pruebas, riesgos |

Documentos: [01](01-project-overview.md), [02](02-repository-map.md), [03](03-architecture.md), [04](04-domain-model.md), [05](05-functional-flows.md), [06](06-backend-reference.md), [07](07-frontend-reference.md), [08](08-api-reference.md), [09](09-data-and-persistence.md), [10](10-security.md), [11](11-integrations.md), [12](12-development-guide.md), [13](13-testing-strategy.md), [14](14-build-deployment-operations.md), [15](15-coding-conventions.md), [16](16-change-impact-guide.md), [17](17-troubleshooting.md), [18](18-known-risks-and-technical-debt.md), [19](19-decisions-and-rationale.md), [20](20-glossary.md), [21](21-open-questions.md), [22](22-source-index.md), [23](23-ai-working-context.md), [24](24-documentation-maintenance.md).

## Advertencias

- No versionar `.env`, secretos, backups, dumps, recibos ni artefactos sensibles.
- Migraciones Flyway V1–V7: forward-only e inmutables.
- No describir staging o producción como desplegados.
- No usar `-SkipTests`.

## Mantenimiento

Actualizar documentos temáticos y `22-source-index.md` en el mismo cambio funcional. Resolver contradicciones contra código/configuración vigente y registrar incertidumbre en `21-open-questions.md`.