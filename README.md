# Gestudio

Monorepo de gestión para alumnos, inscripciones, disciplinas, asistencias, mensualidades, pagos, inventario, caja y reportes.

## Estado

El producto está en etapa pre-productiva. Seguridad/RBAC y Flyway V1-V6 están
integrados; la liquidación financiera por vigencia, la demo interna, staging,
backup/restore y rollback permanecen abiertos. No debe interpretarse el estado
del repositorio como autorización de producción.

Estado y backlog vigentes:

- [Tablero maestro](docs/codex/gestudio-release-hardening/00_INDEX.md)
- [Estado actual y backlog](docs/codex/gestudio-release-hardening/12_ESTADO_ACTUAL_Y_BACKLOG.md)
- [Checklist de release](docs/codex/gestudio-release-hardening/11_CHECKLIST_RELEASE.md)
- [Bitácora de continuidad](docs/codex/gestudio-release-hardening/13_BITACORA_CONTINUIDAD.md)

## Stack

- Backend: Java 21, Spring Boot 3.4.1, Maven 3.9.10 Wrapper, PostgreSQL y Flyway.
- Frontend: React 18, TypeScript, Vite 6, Node 22.14.0 y npm.
- Desarrollo local: Windows PowerShell y Docker Compose.

Flyway parte de `V1__canonical_schema.sql` y aplica las migraciones forward-only
V2-V6. V5 incorpora las estructuras RBAC y el backfill de roles múltiples; V6
incorpora el catálogo y las matrices productivas. V1-V6 no deben editarse. No
existe una ruta de upgrade desde el historial retirado V1-V060.

La autorización usa permisos efectivos calculados en backend. El contrato de
sesión devuelve `roles[]` y `permisos[]`; el refresh token vive sólo en una
cookie HttpOnly. `usuarios.rol_id` se conserva temporalmente como compatibilidad,
pero no es la fuente de autorización.

## Inicio rápido en Windows

Requisitos: Git, JDK 21, Node 22.14.0, npm 10 y Docker Desktop con Compose.
Configurá `JAVA_HOME` para que apunte al JDK 21.

```powershell
Copy-Item .env.local.example .env
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\setup.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dev\start-db.ps1
```

`.env` configura únicamente Docker Compose. Para ejecutar Maven o Vite fuera de
Compose, exportá las variables en la terminal, el script o el IDE.

En terminales separadas:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dev\start-backend.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dev\start-frontend.ps1
```

Validación completa:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope All
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\smoke-local.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-demo-seed.ps1
```

El setup sólo resuelve dependencias. No inicia Docker y no ejecuta la suite completa.

## Demo local persistente

Después de validar el HEAD actual:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\demo-local.ps1 -Action Start
```

Guías:

- [Demo local persistente](docs/testing/demo-local.md)
- [Dataset de demostración](docs/testing/demo-seed.md)
- [Auditoría histórica del seed](12_AUDITORIA_SEED_DEMO.md)

El seed demo sólo puede ejecutarse sobre una base descartable o expresamente
destinada a demostración. No es una migración y no debe corregir RBAC productivo.

## Dominio financiero

Los pagos usan cargos y aplicaciones explícitas, ledgers compensatorios e
idempotency keys con request hash. La generación, almacenamiento y entrega de
recibos se procesa fuera de la transacción financiera mediante `ReciboPendiente`.

La etapa pendiente de liquidación por vigencia debe conectar tarifas y
condiciones históricas con `cargo_liquidaciones` y retirar del cálculo los
campos legacy. Ver
[Etapa 1B](docs/codex/gestudio-release-hardening/04_ETAPA_1B_LIQUIDACION_FINANCIERA.md).

## Documentación

- [Estrategia comercial canónica](docs/comercial/estrategia-comercial.md)
- [Release hardening](docs/codex/gestudio-release-hardening/00_INDEX.md)
- [Desarrollo local](docs/development/local-development.md)
- [Variables de entorno](docs/development/environment-variables.md)
- [Auditoría del entorno](docs/development/environment-audit.md)

No uses `.env.example` como configuración de producción. Los secretos reales
deben permanecer fuera de Git, imágenes, artefactos y logs.

<!-- GATE1B-VALIDACION-2026-07-20 -->
## Validación de release hardening

El validador canónico funciona en Windows y Linux con Java 21:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Backend
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Frontend
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope All
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\smoke-local.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-demo-seed.ps1
```

No usar `-SkipTests`. Las pruebas PostgreSQL requieren Docker/Testcontainers. El estado de release y la evidencia de GATE-1B están en `docs/codex/gestudio-release-hardening/15_CIERRE_GATE_1B_2026-07-20.md`. Staging y producción permanecen en `NO-GO`.
