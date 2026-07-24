# Gestudio

Monorepo de gestión para alumnos, inscripciones, disciplinas, asistencias, mensualidades, pagos, inventario, caja, recibos y reportes.

## Estado

El árbol de release del 22 de julio de 2026 quedó validado localmente para
desarrollo, demo, CI, backup/restore y rollback de aplicación. La identidad del
commit publicado y las ejecuciones remotas se consultan en el informe de cierre
externo asociado al release; no se incrusta el SHA del propio commit dentro del
commit.

Integrado y probado sobre el árbol de release:

- seguridad y RBAC fail-closed;
- catálogo de 32 permisos;
- liquidación financiera por vigencia;
- Flyway V1-V7;
- demo interna automatizada;
- emisor firmado mínimo de estudiantes, deshabilitado por defecto;
- receptor multipágina compatible integrado en Jere Platform;
- backup PostgreSQL/recibos con manifiesto SHA-256;
- restore protegido en base alternativa y activa, validado en PowerShell 7 y Windows PowerShell 5.1;
- rollback backend forward-compatible con backup previo y retorno al artefacto actual;
- observabilidad mínima con readiness, Prometheus protegido, correlación y logs sanitizados;
- demo persistente con fecha comercial diaria separada del ancla estable, detección de imágenes obsoletas y Flyway derivado del manifiesto local;
- dependencia vulnerable `brace-expansion` actualizada en el lockfile sin cambios mayores;
- recorrido real de navegador de los cinco roles demo, en escritorio y móvil;
- imágenes backend y frontend no-root, rutas SPA y headers de seguridad.

Quedan fuera del alcance de un repositorio y requieren un ambiente autorizado:

- transporte y smoke desplegado Gestudio → Jere Platform;
- coordinador Jere Platform `#51`, incluidos Scalaris y requisitos productivos;
- servidor externo de métricas, dashboards, alertas, retención de logs y responsables;
- transporte real y pruebas desplegadas Gestudio → Jere Platform;
- políticas organizacionales de retención de backups, artefactos y secretos;
- TLS/CORS/cookies en ambiente real;
- staging;
- despliegue productivo y su aprobación operativa.

La demo local está habilitada. Staging y producción no se declaran desplegados:
el código falla de forma segura si faltan secretos productivos, y la promoción
exige TLS, CORS, correo, almacenamiento, monitoreo y recuperación configurados en
el ambiente real.

Fuentes vigentes:

- [Estado de release y traspaso](docs/project-status-and-handoff.md)
- [Estado y backlog](docs/codex/gestudio-release-hardening/12_ESTADO_ACTUAL_Y_BACKLOG.md)
- [Checklist](docs/codex/gestudio-release-hardening/11_CHECKLIST_RELEASE.md)
- [Bitácora](docs/codex/gestudio-release-hardening/13_BITACORA_CONTINUIDAD.md)
- [Bitácora operativa](docs/codex/gestudio-release-hardening/19_BITACORA_CIERRE_OPERATIVO_2026-07-20.md)
- [Cierre GATE-1B](docs/codex/gestudio-release-hardening/15_CIERRE_GATE_1B_2026-07-20.md)
- [Cierre V7 y recuperación](docs/codex/gestudio-release-hardening/16_CIERRE_BACKUP_RESTORE_Y_V7_2026-07-20.md)
- [Cierre rollback](docs/codex/gestudio-release-hardening/17_CIERRE_ROLLBACK_FORWARD_COMPATIBLE_2026-07-20.md)
- [Cierre observabilidad](docs/codex/gestudio-release-hardening/18_CIERRE_OBSERVABILIDAD_MINIMA_2026-07-20.md)
- [Cierre técnico 2026-07-22](docs/codex/gestudio-release-hardening/23_CIERRE_RELEASE_2026-07-22.md)

## Stack

- Backend: Java 21, Spring Boot 3.5.16, Maven Wrapper, PostgreSQL 15 y Flyway.
- Frontend: React 18, TypeScript, Vite 6, Node 22 LTS y npm 10.x o compatible.
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

`Start` construye imágenes con metadata del commit, del Compose y de Flyway, fuerza la recreación de backend y frontend sin borrar la base, aplica dos veces el seed y exige que `Status` confirme el stack vigente. El script solicita claves para:

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

`Status` termina con exit code `1` si falta una imagen, el contenedor usa otra image ID, no coinciden revisión/Compose/Flyway, algún servicio no está healthy, el frontend no responde, el historial Flyway está incompleto o el seed no corresponde al día comercial actual. `Reset` elimina únicamente los recursos con proyecto Compose `gestudio-demo-local` y nunca es necesario para un `Start` normal.

Guía: [Puesta en marcha y flujo de uso](docs/operations/local-runbook.md).

## Manual visual de usuarios nuevos

El generador captura recorridos reales de la demo local con Playwright y produce HTML, PDF y metadata sin versionar los artefactos:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\manual\Build-Manual.ps1
```

Arquitectura, credenciales, variantes y validación local: [docs/manual-usuarios/README.md](docs/manual-usuarios/README.md).

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
$backupRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'GestudioBackups'
New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\ops\backup-postgres.ps1 `
  -EnvFile .\.env `
  -ProjectName gestudio `
  -OutputDirectory $backupRoot `
  -StopBackend
```

Runbook: [Backup y restore](docs/operations/backup-restore.md).

## Rollback backend

La imagen objetivo debe contener exactamente todas las migraciones aplicadas. Una base V7 rechaza una imagen V6.

```powershell
$rollbackRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'GestudioBackups\Rollback'
New-Item -ItemType Directory -Force -Path $rollbackRoot | Out-Null
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\ops\rollback-backend.ps1 `
  -TargetBackendImage registry.example/gestudio-backend:rollback-20260720 `
  -ExpectedCurrentImage registry.example/gestudio-backend:current-20260720 `
  -EnvFile .\.env `
  -ProjectName gestudio `
  -BackupOutputDirectory $rollbackRoot `
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
- cabecera repetida, aun con un valor correcto: `401`;
- no enviar el token desde el navegador;
- no reutilizar `JWT_SECRET`.

Runbook: [Observabilidad y diagnóstico](docs/operations/observability.md).

## Dominio financiero

Mensualidades y matrículas resuelven tarifas históricas y condiciones efectivas por fecha. Cada cargo persiste un snapshot en `cargo_liquidaciones` dentro de la misma transacción. La API rechaza fuentes legacy y la UI dirige a tarifas y condiciones económicas.

## Integración Jere Platform

V7 incorpora un emisor administrativo `GESTUDIO_STUDENT` con ID, nombre visible y activo. Está apagado por defecto, requiere tenant y secreto independiente y no realiza push automático.

Jere Platform PR `#60` incorporó el receptor multipágina y cerró el bloqueo técnico `#59`. El issue coordinador `#51` permanece abierto porque abarca además Scalaris y la operación productiva. La conexión desplegada Gestudio → Jere Platform todavía no fue ejecutada ni autorizada; no debe describirse como un bloqueo `#59` abierto.

## Documentación

- [Puesta en marcha y flujo de uso](docs/operations/local-runbook.md)
- [Backup y restore](docs/operations/backup-restore.md)
- [Rollback](docs/operations/rollback.md)
- [Observabilidad](docs/operations/observability.md)
- [Demo persistente](docs/testing/demo-local.md)
- [Dataset demo](docs/testing/demo-seed.md)
- [Recorridos humanos por rol](docs/testing/human-role-walkthrough.md)
- [Manual visual de usuarios nuevos](docs/manual-usuarios/README.md)
- [Variables de entorno](docs/development/environment-variables.md)
- [Integración V7](docs/integrations/jere-platform-student-export-v1.md)
- [Estrategia comercial](docs/comercial/estrategia-comercial.md)
- [Release hardening](docs/codex/gestudio-release-hardening/00_INDEX.md)
- [Cierre técnico 2026-07-22](docs/codex/gestudio-release-hardening/23_CIERRE_RELEASE_2026-07-22.md)

No versionar `.env`, secretos, backups, dumps, recibos ni artefactos sensibles.
