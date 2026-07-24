# Build, despliegue y operaciones

> Estado: PARCIAL  
> Última revisión: 2026-07-24  
> Fuentes principales: `README.md`, `scripts/ops`, `docs/operations`

## Build

Backend con Spring Boot Maven Plugin. Frontend compila TypeScript, bundle Vite y headers. Imágenes backend/frontend documentadas como no-root.

## Local/demo

Docker Compose v2. Demo persistente con `scripts/demo-local.ps1`: `Start`, `Status`, `Stop`, `Reset` acotado a `gestudio-demo-local`.

## Recuperación

Runbooks `backup-restore.md`, `rollback.md`, `observability.md`. Rollback exige backup y correspondencia Flyway.

## Estado

CONFIRMADO local. PENDIENTE staging, producción, TLS/CORS/cookies, monitoreo externo, retención y aprobaciones.

## Health

Liveness/readiness públicos; Prometheus con token independiente.