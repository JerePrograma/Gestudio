# Build, despliegue y operaciones

> Estado: CONFIRMADO  
> Última revisión: 2026-07-24  
> Fuentes principales: Dockerfiles, Compose, workflows y runbooks

## Build

Backend: Maven Wrapper produce artefacto Spring Boot. Frontend: TypeScript + Vite + generación de `_headers`. Imágenes Docker backend/frontend se construyen non-root y contienen metadata de revisión, hash Compose, hash de fuente y versión Flyway.

## CI principal

Disparadores: PR, push a `main` y manual. Permisos `contents: read`, timeouts y acciones fijadas a SHA.

Gates:

1. backend `clean verify`;
2. Node 22, `npm ci`, audits, lint, tests y build;
3. Compose local y productivo;
4. contratos demo remota en Linux, Windows PowerShell 5.1 y PowerShell 7;
5. imágenes y metadata;
6. smoke aislado.

## Configuraciones Compose

- `docker-compose.yml`: local/base.
- `docker-compose.prod.yml`: overlay productivo.
- `docker-compose.remote-demo.yml`: demo remota.
- demo persistente usa proyecto aislado `gestudio-demo-local`.

## Entornos

| Entorno | Estado |
|---|---|
| Dev local | soportado |
| Demo local | soportada y validada |
| Demo remota | contratos y runbooks presentes |
| Staging | PENDIENTE |
| Producción | PENDIENTE |

El repositorio preparado no acredita TLS, DNS, secret manager, almacenamiento persistente, correo, monitoreo, alertas ni responsables.

## Health y métricas

- liveness/readiness públicos.
- Prometheus protegido por token.
- correlación `X-Request-ID`.
- logs sanitizados.

## Backup/restore

Scripts generan backup PostgreSQL y recibos, manifiesto v2 y SHA-256. Restore valida todo antes de modificar datos, exige destino/confirmaciones y se prueba sobre base alternativa y activa protegida.

## Rollback

Rollback de aplicación:

1. valida imagen objetivo;
2. exige confirmación;
3. crea backup previo;
4. comprueba que la imagen contiene todas las migraciones aplicadas;
5. cambia backend;
6. verifica salud;
7. permite volver al artefacto actual.

No hace down migration. Base V7 rechaza imagen que sólo conoce V6.

## Artefactos y retención

CI produce evidencia con retención limitada. Manual, capturas, certificaciones, backups, dumps y recibos no deben versionarse.

## Migraciones durante despliegue

Flyway es forward-only. La aplicación debe correr sólo si conoce el esquema. Rollback DB requiere restore, no una migración inversa improvisada.

## Runbooks

- [`../operations/local-runbook.md`](../operations/local-runbook.md)
- [`../operations/backup-restore.md`](../operations/backup-restore.md)
- [`../operations/rollback.md`](../operations/rollback.md)
- [`../operations/observability.md`](../operations/observability.md)

## Riesgos operativos

Promover sin pruebas de restore, secretos gestionados, almacenamiento persistente, TLS/CORS reales o monitoreo externo. Consultar [18-known-risks-and-technical-debt.md](18-known-risks-and-technical-debt.md).
