# Guía de impacto de cambios

> Estado: CONFIRMADO  
> Última revisión: 2026-07-24  
> Fuentes principales: `../../AGENTS.md`, contratos ejecutables y arquitectura

## Cambiar un endpoint

1. Localizar controlador, servicio, DTO, mapper y repositorio.
2. Buscar consumidores frontend, scripts, tests y documentación.
3. Revisar `SecurityConfigurations`.
4. Actualizar `SecurityHttpIntegrationTest`.
5. Revisar status, error code, paginación y compatibilidad.
6. Ejecutar backend, frontend y smoke según alcance.

## Cambiar DTO

- Buscar construcción/serialización/deserialización.
- Revisar records, mappers, Axios types, formularios y fixtures.
- Tratar nombre, tipo, nullability y formato como contrato.
- Versionar si rompe consumidores.

## Cambiar entidad/esquema

- Inspeccionar todas las migraciones y relaciones.
- Revisar cascadas, constraints, índices y datos existentes.
- Crear migración contigua.
- Probar limpia + upgrade + reconciliación.
- Revisar backup/restore y rollback de aplicación.

## Cambiar finanzas

Documentar monto original, pagado, restante, estado, sobrepago, reversión, crédito, caja, stock y recibo. Revisar `PagoServicio`, `AplicacionPago`, movimientos y constraints. Añadir caracterización PostgreSQL.

## Cambiar permisos

- Código en `PermissionCodes`.
- Seed/migración y matrices base.
- `SecurityConfigurations`.
- test dinámico de 146 mappings.
- `frontend/src/config/permissions`.
- `routePermissions`, navegación y tests.
- recorrido por roles.

## Cambiar una ruta frontend

Revisar `routes.ts`, `AppRouter`, navegación, permisos, enlaces, lazy imports, tests, manual visual y redirecciones.

## Cambiar jobs

Revisar flag, cron, timezone, idempotencia DB, servicio manual equivalente, concurrencia, logging y pruebas. Consultar [26-scheduled-jobs.md](26-scheduled-jobs.md).

## Cambiar integración externa

Revisar contrato versionado, minimización, autenticación/firma, timeouts, reintentos, idempotencia, degradación, auditoría, secretos, mocks y runbook.

## Cambiar configuración/Compose

Revisar `.env*.example`, properties, perfiles, Compose local/prod/demo, CI, Docker metadata y fail-closed productivo. No editar valores reales.

## Validación mínima por impacto

| Impacto | Validación |
|---|---|
| Backend | `validate -Scope Backend` |
| Frontend | lint + test + build |
| Ambos/API | `validate -Scope All` + smoke |
| Migración | limpia + upgrade + SQL reconciliación |
| Seguridad | test dinámico + roles |
| Docker | builds limpios + Compose |
| Operación | drill específico |

## Checklist antes de commit

- Sólo archivos de la tarea.
- Sin secretos/artefactos.
- Tests reales registrados.
- Diff revisado.
- Documentación y source index actualizados.
- Inferencias marcadas.
- `main` no avanzó desde la base o el commit se rehízo sobre HEAD.
