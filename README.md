# Gestudio

Monorepo de gestión para alumnos, inscripciones, disciplinas, asistencias, mensualidades, pagos, inventario, caja, recibos y reportes.

> **Estado contractual:** código, demo local y producción se evalúan por
> separado. El SHA publicado y sus resultados locales/remotos pertenecen al
> informe de cierre; este archivo no congela el SHA del propio commit.

## Estado

El worktree incorpora Flyway V1-V12, baseline fresh B12 sin seed funcional,
autenticación ligada a tenant/membership, RLS shared-schema forzado y un control
plane separado con `PLATFORM_SUPERADMIN`, MFA TOTP y step-up. El cierre sólo se
considera válido después de ejecutar los gates sobre el SHA definitivo. La demo
local canónica usa el proyecto exclusivo `gestudio-demo-local`; el proyecto
protegido `gestudio-remote-demo` nunca forma parte de ese flujo.

Integrado y probado sobre el árbol de release:

- seguridad y RBAC fail-closed;
- catálogo de 32 permisos;
- liquidación financiera por vigencia;
- Flyway V1-V12 y baseline B12, con fresh y upgrade separados;
- demo interna automatizada;
- emisor firmado mínimo de estudiantes, deshabilitado por defecto;
- receptor multipágina compatible integrado en Jere Platform;
- backup PostgreSQL/recibos con manifiesto SHA-256;
- restore protegido en base alternativa y activa, validado en PowerShell 7 y Windows PowerShell 5.1;
- rollback backend forward-compatible con backup previo y retorno al artefacto actual;
- observabilidad mínima con readiness, Prometheus protegido, correlación y logs sanitizados;
- email controlado con `NOOP` predeterminado, `FAKE` sin red y adaptador Gmail SMTP fail-closed no conectado;
- demo multitenant persistente con control plane, Alpha/Beta, MFA, lifecycle,
  RLS, auditoría, puertos loopback y detección de drift;
- dependencia vulnerable `brace-expansion` actualizada en el lockfile sin cambios mayores;
- recorrido real de navegador de los cinco roles demo, en escritorio y móvil;
- imágenes backend y frontend no-root, rutas SPA y headers de seguridad;
- contrato paginado estable con `PageResponse<T>` sin exponer `PageImpl` como respuesta pública.

Quedan fuera del alcance de un repositorio y requieren un ambiente autorizado:

- staging, TLS, DNS, CORS, cookies y secretos productivos: [#23](https://github.com/JerePrograma/Gestudio/issues/23);
- servidor externo de métricas, dashboards, alertas, retención de logs y responsables: [#24](https://github.com/JerePrograma/Gestudio/issues/24);
- transporte y smoke desplegado Gestudio → Jere Platform: [#25](https://github.com/JerePrograma/Gestudio/issues/25);
- coordinador Jere Platform `#51`, incluidos Scalaris y requisitos productivos;
- políticas organizacionales de retención de backups, artefactos y secretos: [#23](https://github.com/JerePrograma/Gestudio/issues/23);
- despliegue productivo y su aprobación operativa: [#23](https://github.com/JerePrograma/Gestudio/issues/23).

La demo local está soportada. Staging y producción no se declaran desplegados:
el código falla de forma segura si faltan secretos productivos, y la promoción
exige TLS, CORS, correo, almacenamiento, monitoreo y recuperación configurados en
el ambiente real.

Fuentes vigentes:

- [ADR shared-schema multitenancy](docs/architecture/adr-0008-shared-schema-multitenancy.md)
- [ADR del control plane SUPERADMIN](docs/architecture/adr-0009-platform-control-plane.md)
- [Threat model del control plane](docs/architecture/threat-model-platform-control-plane.md)
- [Runbook del control plane](docs/operations/platform-control-plane-runbook.md)
- [Gobierno y salud multitenancy](docs/architecture/multitenancy-governance-and-health.md)
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
- Frontend: React 19.2.8, React Router 8.3.0, TypeScript, Vite 6, Node 22 LTS y npm 10.x o compatible.
- Operación: PowerShell, Docker y Docker Compose v2.
- Observabilidad: Spring Boot Actuator, Micrometer y formato Prometheus.

El worktree contiene la cadena forward-only V1-V12 y la baseline productiva
B12. Las migraciones ya publicadas permanecen inmutables y toda corrección debe
usar la próxima versión contigua; fresh y upgrade deben validarse por separado.

## Inicio recomendado: demo persistente

Para un despliegue local idempotente desde Windows use `deploy.cmd`; requisitos,
modos, estado, secretos, backups y recuperación están en la
[guía de despliegue para Windows](docs/deployment-windows.md).

```powershell
git clone https://github.com/JerePrograma/Gestudio.git
Set-Location .\Gestudio
git switch main
git pull --ff-only origin main
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\setup.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-local.ps1 -Action Start
```

`Start` crea una configuración privada una sola vez, construye imágenes desde el
checkout, migra B12 fresh cuando corresponde, ejecuta el bootstrap one-shot del
primer administrador de plataforma, aprovisiona Alpha/Beta por el control plane,
carga los fixtures externos a Flyway y sólo termina si `Status` queda verde.
Los actores sintéticos disponibles son:

- `platform.demo.admin` (`PLATFORM_SUPERADMIN`, sin membership tenant);
- `alpha.demo.admin` y `beta.demo.admin`;
- `demo-superadmin`;
- `demo-direccion`;
- `demo-administrador`;
- `demo-secretaria`;
- `demo-caja`.

URLs:

- frontend: `http://127.0.0.1:18081`;
- control plane: `http://127.0.0.1:18081/platform/login`;
- backend/API: `http://127.0.0.1:18080` / `http://127.0.0.1:18080/api`;
- PostgreSQL: `127.0.0.1:15432`;
- liveness/readiness: `http://127.0.0.1:18080/actuator/health/liveness` y
  `http://127.0.0.1:18080/actuator/health/readiness`.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-local.ps1 -Action Status
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-local.ps1 -Action Stop
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-local.ps1 -Action Reset -ConfirmReset
```

`Stop` conserva configuración, credenciales, datos y auditoría. `Reset` exige
`-ConfirmReset`, elimina sólo contenedores/red/volúmenes del proyecto exacto y
reconstruye una demo fresh. `Status` es de sólo lectura y falla ante drift,
health/Flyway/RLS/RBAC/dataset/aislamiento/auditoría o secretos en logs.

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
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\ops\verify-email-delivery.ps1
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

La imagen objetivo debe contener exactamente el manifiesto Flyway ya aplicado.
Una base en `V<N>` rechaza una imagen que sólo alcance `V<N-1>` o no declare la
baseline `B<N>` correspondiente.

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

Jere Platform PR `#60` incorporó el receptor multipágina y cerró el bloqueo técnico `#59`. El issue coordinador `#51` permanece abierto porque abarca además Scalaris y la operación productiva. La conexión desplegada Gestudio → Jere Platform todavía no fue ejecutada ni autorizada; su seguimiento está en [Gestudio #25](https://github.com/JerePrograma/Gestudio/issues/25) y no debe describirse como un bloqueo `#59` abierto.

## Email controlado

`IEmailService` selecciona `NOOP`, `FAKE` o `GMAIL_SMTP` por configuración, no
por el perfil `prod`. El default no abre red ni exige credenciales; Gmail SMTP
permanece implementado pero no conectado y requiere `prod` más cinco guardas simultáneas.
El gate local usa únicamente dobles y configuración sintética. Véase
[Entrega de email controlada](docs/integrations/gmail-email-delivery.md).

## Documentación

- [Despliegue idempotente en Windows](docs/deployment-windows.md)
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
- [Email Gmail controlado](docs/integrations/gmail-email-delivery.md)
- [Estrategia comercial](docs/comercial/estrategia-comercial.md)
- [Release hardening](docs/codex/gestudio-release-hardening/00_INDEX.md)
- [Cierre técnico 2026-07-22](docs/codex/gestudio-release-hardening/23_CIERRE_RELEASE_2026-07-22.md)

No versionar `.env`, secretos, backups, dumps, recibos ni artefactos sensibles.
