# Gestudio

Monorepo de gestión para alumnos, inscripciones, disciplinas, asistencias, mensualidades, pagos, inventario, caja, recibos y reportes.

## Estado

Gestudio está en etapa pre-productiva.

Integrado y probado:

- seguridad y RBAC fail-closed;
- catálogo de 32 permisos;
- liquidación financiera por vigencia;
- Flyway V1-V7;
- demo interna automatizada;
- emisor firmado de referencias mínimas de estudiantes, deshabilitado por defecto;
- backup PostgreSQL y recibos con manifiesto SHA-256;
- restore protegido en base alternativa.

Continúan abiertos:

- recorridos humanos por rol;
- GATE-2 UX crítica;
- rollback forward-compatible;
- observabilidad y alertas;
- política de retención, cifrado, RPO/RTO y responsables;
- staging;
- producción.

**El repositorio no constituye autorización de despliegue. Demo comercial, staging y producción permanecen en NO-GO.**

Fuentes vigentes:

- [Estado actual y backlog](docs/codex/gestudio-release-hardening/12_ESTADO_ACTUAL_Y_BACKLOG.md)
- [Checklist de release](docs/codex/gestudio-release-hardening/11_CHECKLIST_RELEASE.md)
- [Bitácora de continuidad](docs/codex/gestudio-release-hardening/13_BITACORA_CONTINUIDAD.md)
- [Cierre GATE-1B](docs/codex/gestudio-release-hardening/15_CIERRE_GATE_1B_2026-07-20.md)
- [Cierre V7 y recuperación](docs/codex/gestudio-release-hardening/16_CIERRE_BACKUP_RESTORE_Y_V7_2026-07-20.md)

## Stack

- Backend: Java 21, Spring Boot 3.4.1, Maven Wrapper, PostgreSQL 15 y Flyway.
- Frontend: React 18, TypeScript, Vite 6, Node 22.14.0 y npm 10.x.
- Operación local: PowerShell, Docker y Docker Compose v2.

Flyway parte de `V1__canonical_schema.sql` y aplica migraciones forward-only V2-V7. V5 incorpora estructuras RBAC y backfill de roles múltiples; V6 incorpora el catálogo y matrices productivas; V7 agrega snapshots firmados de integración. **V1-V7 son inmutables.**

## Inicio recomendado: demo persistente

Requisitos: Git, JDK 21, Node 22.14.0, npm 10 y Docker Desktop con Compose.

```powershell
git clone https://github.com/JerePrograma/Gestudio.git
Set-Location .\Gestudio
git switch main
git pull --ff-only origin main
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\setup.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-local.ps1 -Action Start
```

El script solicita claves para:

- `demo-superadmin`;
- `demo-direccion`;
- `demo-administrador`;
- `demo-secretaria`;
- `demo-caja`.

Direcciones:

- frontend: `http://localhost:18081`;
- backend: `http://localhost:18080`;
- API: `http://localhost:18080/api`;
- PostgreSQL: `localhost:15432`.

Consultar o detener:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-local.ps1 -Action Status
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-local.ps1 -Action Stop
```

Guía completa: [Puesta en marcha y flujo de uso](docs/operations/local-runbook.md).

## Desarrollo local

Crear configuración Compose no versionada:

```powershell
Copy-Item .env.local.example .env
```

Preparar e iniciar componentes separados:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\setup.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dev\start-db.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dev\start-backend.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dev\start-frontend.ps1
```

Compose completo:

```powershell
docker compose --env-file .env -p gestudio up -d --build
docker compose --env-file .env -p gestudio ps
```

URLs predeterminadas de Compose:

- frontend: `http://localhost:8081`;
- backend: `http://localhost:8080`;
- API: `http://localhost:8080/api`;
- PostgreSQL: `localhost:5432`.

Más detalle: [Desarrollo local](docs/development/local-development.md).

## Validación canónica

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Backend
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Frontend
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope All
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\smoke-local.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-demo-seed.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\ops\verify-backup-restore.ps1
```

No usar `-SkipTests`. Las pruebas PostgreSQL requieren Docker/Testcontainers.

## Backup

Backup consistente de base y recibos:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\ops\backup-postgres.ps1 `
  -EnvFile .\.env `
  -ProjectName gestudio `
  -OutputDirectory D:\Backups\Gestudio `
  -StopBackend
```

Procedimiento completo: [Backup y restore](docs/operations/backup-restore.md).

## Dominio financiero

Mensualidades y matrículas resuelven tarifas históricas y condiciones efectivas por fecha. Cada cargo nuevo persiste un snapshot en `cargo_liquidaciones` dentro de la misma transacción. La API rechaza fuentes financieras legacy y la UI dirige la operación a tarifas y condiciones económicas.

Los pagos usan cargos y aplicaciones explícitas, ledgers compensatorios e idempotency keys con request hash. Los recibos se procesan fuera de la transacción financiera mediante `ReciboPendiente`.

## Integración Jere Platform

V7 incorpora un emisor administrativo de referencias `GESTUDIO_STUDENT` con ID, nombre de visualización y activo. Está deshabilitado por defecto, requiere mapping de tenant y secreto independiente, y no realiza push automático.

La reconciliación multipágina end-to-end continúa bloqueada por `JerePrograma/jere-platform#59`. No habilitar la función como integración productiva hasta cerrar ese contrato.

## Documentación

- [Puesta en marcha y flujo de uso](docs/operations/local-runbook.md)
- [Backup y restore](docs/operations/backup-restore.md)
- [Demo local persistente](docs/testing/demo-local.md)
- [Dataset demo](docs/testing/demo-seed.md)
- [Variables de entorno](docs/development/environment-variables.md)
- [Emisor Jere Platform V1](docs/integrations/jere-platform-student-export-v1.md)
- [Estrategia comercial](docs/comercial/estrategia-comercial.md)
- [Release hardening](docs/codex/gestudio-release-hardening/00_INDEX.md)

No uses `.env.example` como configuración de producción. Los secretos reales, backups, dumps y recibos deben permanecer fuera de Git, imágenes, artefactos públicos y logs.
