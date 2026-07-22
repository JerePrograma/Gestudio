# Desarrollo local

Esta guía describe el entorno de desarrollo. Para una puesta en marcha funcional completa y el flujo de uso, ver [Puesta en marcha y flujo de uso](../operations/local-runbook.md).

## Requisitos

| Herramienta | Versión de referencia |
|---|---|
| PowerShell | 5.1 o 7 |
| Git | 2.x |
| JDK | 21 |
| Maven | Wrapper del repositorio |
| Node.js | 22 LTS |
| npm | 10.x |
| Docker Desktop | Engine activo |
| Docker Compose | v2 |

No se requiere Python para ejecutar Gestudio.

## Preparación

Definí `JAVA_HOME` con el JDK 21 de tu entorno. Como ayuda opcional, el script
dot-sourced acepta una ruta explícita y sólo modifica la terminal actual:

```powershell
. .\scripts\use-local-java.ps1 -JdkPath '<ruta-local-al-jdk-21>'
```

Ese helper omite deliberadamente `Set-StrictMode` y
`$ErrorActionPreference = 'Stop'` para no cambiar las preferencias de la
terminal llamadora. Todos los scripts ejecutables sí fijan ambos controles.

```powershell
git switch main
git pull --ff-only origin main
Copy-Item .env.local.example .env
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\setup.ps1
```

`setup.ps1` valida JDK 21, resuelve dependencias del backend y ejecuta `npm ci`. No levanta servicios ni acredita que la aplicación esté saludable.

## Perfiles Spring

- `dev`: PostgreSQL local, email no-op y schedulers apagados salvo habilitación explícita.
- `test`: infraestructura aislada de pruebas; Testcontainers provee PostgreSQL cuando corresponde.
- `prod`: configuración externa obligatoria, `ddl-auto=validate`, Flyway activo y sin fallbacks locales.

JPA usa `open-in-view=false` en todos los perfiles. El mapeo a DTO debe ocurrir
dentro del caso de uso/transacción; no se debe reactivar OSIV para ocultar una
relación lazy. Hibernate autodetecta PostgreSQL, por lo que no se configura el
dialecto redundante.

No existe un perfil predeterminado fuera de Compose. Usar explícitamente:

```powershell
$env:SPRING_PROFILES_ACTIVE = 'dev'
```

## Flyway

La cadena productiva vigente es V1-V7:

- V1: esquema canónico;
- V5: estructuras RBAC y backfill;
- V6: catálogo de 32 permisos y matrices base;
- V7: snapshots y páginas firmadas del emisor Jere Platform.

Reglas:

- V1-V7 son inmutables;
- cualquier corrección futura requiere V8 o superior;
- no usar `ddl-auto=update`;
- no ejecutar down migrations;
- el seed demo no es una migración;
- un artefacto de rollback debe conservar todas las migraciones aplicadas.

Los scripts de demo derivan el manifiesto desde los nombres `V*__*.sql`, exigen
versiones únicas y contiguas y comparan el historial completo. Al agregar V8 no
se debe editar un número fijo en `demo-local.ps1` ni en el validador.

## Ejecución separada

Base PostgreSQL:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dev\start-db.ps1
```

Backend, en otra terminal:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dev\start-backend.ps1
```

Frontend, en otra terminal:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dev\start-frontend.ps1
```

Puertos usuales:

- PostgreSQL: `5432` o `POSTGRES_PORT`;
- backend: `8080` o `BACKEND_PORT`;
- frontend Vite: `5173` o `FRONTEND_PORT`.

Detener los contenedores conservando volúmenes:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dev\stop.ps1
```

Maven y Vite se detienen con `Ctrl+C` en sus terminales.

## Docker Compose completo

```powershell
docker compose --env-file .env -p gestudio config
docker compose --env-file .env -p gestudio up -d --build
docker compose --env-file .env -p gestudio ps
```

URLs predeterminadas:

- frontend: `http://localhost:8081`;
- backend: `http://localhost:8080`;
- API: `http://localhost:8080/api`;
- PostgreSQL: `localhost:5432`.

Detener conservando datos:

```powershell
docker compose --env-file .env -p gestudio down --remove-orphans
```

Eliminar volúmenes sólo cuando esté decidido perder la base y recibos locales:

```powershell
docker compose --env-file .env -p gestudio down --volumes --remove-orphans
```

`docker-compose.prod.yml` es configuración de despliegue y no debe usarse como atajo de desarrollo.

## Bootstrap inicial

Sólo sobre una base sin usuarios:

```powershell
$env:APP_BOOTSTRAP_SUPERADMIN_ENABLED = 'true'
$env:APP_BOOTSTRAP_SUPERADMIN_USERNAME = 'admin-inicial'
$secret = Read-Host 'Clave inicial' -AsSecureString
$env:APP_BOOTSTRAP_SUPERADMIN_PASSWORD = [System.Net.NetworkCredential]::new('', $secret).Password
Remove-Variable secret
```

La clave debe tener entre 16 y 72 bytes UTF-8. Después del primer arranque:

1. confirmar el login;
2. apagar `APP_BOOTSTRAP_SUPERADMIN_ENABLED`;
3. recrear el backend.

Mantener la bandera activa provoca un fallo cerrado.

JWT usa `JWT_ACCESS_TOKEN_TTL` y `JWT_REFRESH_TOKEN_TTL` como duraciones
ISO-8601 (`PT15M`, `P7D` en desarrollo). Producción las exige sin fallback y
fuerza `APP_SECURITY_REFRESH_COOKIE_SECURE=true`.

## Validación

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\status.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Backend
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Frontend
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope All
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\smoke-local.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-demo-seed.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\ops\verify-backup-restore.ps1
```

`Scope All` ejecuta backend, lint, tests frontend, build y validación Compose. No usar `-SkipTests`.

Desde `frontend`, `npm audit --omit=dev --audit-level=high` es gate de
dependencias de producción. El advisory alto de desarrollo de
`brace-expansion` se cerró mediante actualización controlada del lockfile, sin
`--force` ni cambio mayor; ejecutar también `npm audit` para revalidar el árbol
completo.

## Demo persistente

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-local.ps1 -Action Start
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-local.ps1 -Action Status
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-local.ps1 -Action Stop
```

Guía: [Demo local persistente](../testing/demo-local.md).

`Start` fuerza la recreación de backend y frontend sin borrar PostgreSQL.
`Status` termina en `1` si las imágenes, contenedores, revisión Git, hash
Compose, Flyway, health, frontend o seed no coinciden. `Reset` es la única
acción que elimina los volúmenes del proyecto aislado `gestudio-demo-local`.

## Backup y restore

Backup consistente de base y recibos:

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

Drill descartable:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\ops\verify-backup-restore.ps1
```

Runbook: [Backup y restore](../operations/backup-restore.md).

## Integración V7

Permanece deshabilitada por defecto. Para una prueba administrativa controlada se requieren:

```text
APP_JERE_PLATFORM_STUDENT_EXPORT_ENABLED=true
APP_JERE_PLATFORM_STUDENT_EXPORT_ORGANIZATION_ID=<id estable>
APP_JERE_PLATFORM_STUDENT_EXPORT_TENANT_ID=<UUID>
APP_JERE_PLATFORM_STUDENT_EXPORT_CURRENT_SECRET=<32 bytes o más>
```

El receptor multipágina integrado cerró `JerePrograma/jere-platform#59`. No
habilitar como operación end-to-end hasta contar con transporte desplegado,
secretos, tenant, smoke y autorización; el coordinador `#51` sigue abierto.

## Diagnóstico

```powershell
docker compose --env-file .env -p gestudio ps
docker compose --env-file .env -p gestudio logs --tail 200 db backend frontend
docker volume ls --filter label=com.docker.compose.project=gestudio
```

Problemas frecuentes:

- Java no es 21: corregir `JAVA_HOME`;
- Docker CLI sin Engine: iniciar Docker Desktop;
- puerto ocupado: cambiarlo en `.env`;
- Flyway falla: no editar una migración aplicada;
- Hibernate falla: revisar datasource y mantener `ddl-auto=validate`;
- bootstrap falla tras crear usuario: apagar la bandera;
- falta tarifa: crear una vigencia histórica, no usar campos legacy;
- restore rechazado: usar una base alternativa y confirmaciones explícitas;
- demo no disponible: leer el detalle de freshness y ejecutar `Start`, sin borrar volumen;
- Prometheus `401`: enviar exactamente una cabecera con el token independiente.

## Límites

Un entorno local verde no autoriza staging ni producción. El 22 de julio de
2026 se revalidaron rollback, observabilidad, backup/restore, imágenes no-root y
el recorrido de los cinco roles. Continúan dependiendo del ambiente real TLS,
secret manager, SMTP, almacenamiento, monitoreo externo, alertas y responsables
de operación. Esas precondiciones no se simulan ni se presentan como despliegue.
