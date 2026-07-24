# Troubleshooting

> Estado: PARCIAL  
> Última revisión: 2026-07-24  
> Fuentes principales: `README.md`, scripts demo/ops/manual

## Demo `Status` falla

Revisar imagen faltante, image ID, metadata commit/Compose/Flyway, health, frontend, historial Flyway y seed del día comercial.

## Backend no inicia

Revisar PostgreSQL, variables requeridas, secretos, migraciones y readiness. No omitir migraciones ni degradar fail-closed.

## Prometheus 401

Verificar token independiente y un único `X-Gestudio-Metrics-Token`; no reutilizar JWT.

## Rollback rechazado

La imagen no contiene todas las migraciones aplicadas. Usar imagen compatible; no alterar Flyway.

## Manual visual incompleto

Revisar `MANUAL_BASE_URL`, directorio y `MANUAL_RESUME_FROM`; capturas anteriores requeridas deben existir.