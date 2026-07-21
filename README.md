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
- emisor firmado mínimo de estudiantes, deshabilitado por defecto;
- backup PostgreSQL/recibos con manifiesto SHA-256;
- restore protegido en base alternativa;
- rollback backend forward-compatible con backup previo y retorno al artefacto actual;
- observabilidad mínima con readiness, Prometheus protegido, correlación y logs sanitizados.

Continúan abiertos:

- servidor externo de métricas, dashboards, alertas, retención de logs y responsables;
- GATE-2 y recorridos humanos;
- políticas de backups, artefactos y secretos;
- TLS/CORS/cookies en ambiente real;
- staging;
- producción.

**Demo comercial, staging y producción permanecen en NO-GO.**

Fuentes vigentes:

- [Estado y backlog](docs/codex/gestudio-release-hardening/12_ESTADO_ACTUAL_Y_BACKLOG.md)
- [Checklist](docs/codex/gestudio-release-hardening/11_CHECKLIST_RELEASE.md)
- [Bitácora](docs/codex/gestudio-release-hardening/13_BITACORA_CONTINUIDAD.md)
- [Cierre GATE-1B](docs/codex/gestudio-release-hardening/15_CIERRE_GATE_1B_2026-07-20.md)
- [Cierre V7 y recuperación](docs/codex/gestudio-release-hardening/16_CIERRE_BACKUP_RESTORE_Y_V7_2026-07-20.md)
- [Cierre rollback](docs/codex/gestudio-release-hardening/17_CIERRE_ROLLBACK_FORWARD_COMPATIBLE_2026-07-20.md)
- [Cierre observabilidad](docs/codex/gestudio-release-hardening/18_CIERRE_OBSERVABILIDAD_MINIMA_2026-07-20.md)

## Stack

- Backend: Java 21, Spring Boot 3.4.1, Maven Wrapper, PostgreSQL 15 y Flyway.
- Frontend: React 18, TypeScript, Vite 6, Node 22.14.0 y npm 10.x.
- Operación: PowerShell, Docker y Docker Compose v2.
- Observabilidad: Spring Boot Actuator, Micrometer y formato Prometheus.

V1-V7 son migraciones forward-only e inmutables.

## Inicio recomendado: demo persistente

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

URLs:

- frontend: `http://localhost:18081`;
- backend: `http://localhost:18080`;
- API: `http://localhost:18080/api`;
- PostgreSQL: `localhost:15432`;
- liveness: `http://localhost:18080/actuator/health/liveness`;
- readiness: `http://localhost:18080/actuator/health/readiness`.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-local.ps1 -Action Status
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-local.ps1 -Action Stop
```

Guía: [Puesta en marcha y flujo de uso](docs/operations/local-runbook.md).

## Desarrollo local

```powershell
Copy-Item .env.local.example .env
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

URLs predeterminadas:

- frontend: `http://localhost:8081`;
- backend: `http://localhost:8080`;
- API: `http://localhost:8080/api`;
- PostgreSQL: `localhost:5432`;
- liveness: `http://localhost:8080/actuator/health/liveness`;
- readiness: `http://localhost:8080/actuator/health/readiness`.

## Validación canónica

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Backend
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Frontend
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope All
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\smoke-local.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-demo-seed.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\ops\verify-backup-restore.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\ops\verify-application-rollback.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\ops\verify-observability.ps1
```

No usar `-SkipTests`.

## Backup

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\ops\backup-postgres.ps1 `
  -EnvFile .\.env `
  -ProjectName gestudio `
  -OutputDirectory D:\Backups\Gestudio `
  -StopBackend
```

Runbook: [Backup y restore](docs/operations/backup-restore.md).

## Rollback backend

La imagen objetivo debe contener exactamente todas las migraciones aplicadas. Una base V7 rechaza una imagen V6.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\ops\rollback-backend.ps1 `
  -TargetBackendImage registry.example/gestudio-backend:rollback-20260720 `
  -ExpectedCurrentImage registry.example/gestudio-backend:current-20260720 `
  -EnvFile .\.env `
  -ProjectName gestudio `
  -BackupOutputDirectory D:\Backups\Gestudio\Rollback `
  -ConfirmRollback
```

Runbook: [Rollback compatible con Flyway](docs/operations/rollback.md).

## Observabilidad

Health público mínimo:

```powershell
Invoke-RestMethod http://localhost:8080/actuator/health/liveness
Invoke-RestMethod http://localhost:8080/actuator/health/readiness
```

Prometheus requiere un secreto independiente:

```powershell
$headers = @{
  'X-Gestudio-Metrics-Token' = $env:APP_OBSERVABILITY_METRICS_TOKEN
}
Invoke-WebRequest http://localhost:8080/actuator/prometheus -Headers $headers
```

- credencial ausente o inválida: `401`;
- credencial exacta: `200`;
- no enviar el token desde el navegador;
- no reutilizar `JWT_SECRET`.

Runbook: [Observabilidad y diagnóstico](docs/operations/observability.md).

## Dominio financiero

Mensualidades y matrículas resuelven tarifas históricas y condiciones efectivas por fecha. Cada cargo persiste un snapshot en `cargo_liquidaciones` dentro de la misma transacción. La API rechaza fuentes legacy y la UI dirige a tarifas y condiciones económicas.

## Integración Jere Platform

V7 incorpora un emisor administrativo `GESTUDIO_STUDENT` con ID, nombre visible y activo. Está apagado por defecto, requiere tenant y secreto independiente y no realiza push automático.

La reconciliación multipágina end-to-end continúa bloqueada por `JerePrograma/jere-platform#59`.

## Documentación

- [Puesta en marcha y flujo de uso](docs/operations/local-runbook.md)
- [Backup y restore](docs/operations/backup-restore.md)
- [Rollback](docs/operations/rollback.md)
- [Observabilidad](docs/operations/observability.md)
- [Demo persistente](docs/testing/demo-local.md)
- [Dataset demo](docs/testing/demo-seed.md)
- [Variables de entorno](docs/development/environment-variables.md)
- [Integración V7](docs/integrations/jere-platform-student-export-v1.md)
- [Estrategia comercial](docs/comercial/estrategia-comercial.md)
- [Release hardening](docs/codex/gestudio-release-hardening/00_INDEX.md)

No versionar `.env`, secretos, backups, dumps, recibos ni artefactos sensibles.
