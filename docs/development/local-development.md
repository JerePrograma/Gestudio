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

La cadena versionada del árbol es `V1..V12` y la instalación fresh usa `B12`:

- V1: esquema canónico;
- V5: estructuras RBAC y backfill;
- V6: catálogo de 32 permisos y matrices base;
- V7: snapshots y páginas firmadas del emisor Jere Platform;
- V8: control plane de tenants y memberships;
- V9: aislamiento shared-schema del plano de dominio;
- V10: RLS, grants mínimos y salud estructural;
- V11: cobertura de índices para claves foráneas;
- V12: identidad/control plane de plataforma, MFA, sesiones, activaciones,
  idempotencia, auditoría y roles runtime separados;
- B12: baseline fresh equivalente, con catálogo técnico y cero seed funcional.

Reglas:

- V1-V12 son inmutables una vez publicadas; cualquier corrección posterior usa
  la siguiente migración forward-only;
- no usar `ddl-auto=update`;
- no ejecutar down migrations;
- el seed demo no es una migración;
- la demo estable remota está protegida: no se infiere ni modifica su versión
  desde un entorno sin Docker; su estado se verifica separadamente;
- un artefacto de rollback debe conservar todas las migraciones aplicadas.

Los scripts de demo derivan el manifiesto desde los nombres `V*__*.sql`, exigen
versiones únicas y contiguas, reconocen una única baseline `B<latest>` y comparan
el historial completo. Al agregar una versión no se debe editar un número fijo
en `demo-local.ps1` ni en el validador.

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

## Bootstrap inicial de plataforma

El backend ordinario siempre mantiene `APP_BOOTSTRAP_SUPERADMIN_ENABLED=false`.
Sobre una base sin administradores de plataforma, después de que DB/backend estén
healthy, ejecutar el job externo one-shot:

```powershell
$recoveryCodes = Join-Path `
  ([Environment]::GetFolderPath('MyDocuments')) `
  'gestudio-platform-recovery.txt'

pwsh -NoProfile -File .\scripts\ops\bootstrap-platform-admin.ps1 `
  -EnvFile .\.env `
  -ProjectName gestudio `
  -Username admin-inicial `
  -RecoveryCodesPath $recoveryCodes `
  -ConfirmBootstrap
```

Password, secreto Base32 y TOTP se solicitan como `SecureString`. El resultado
es una identidad platform-only con MFA y diez recovery codes one-shot; no crea
tenant, rol ni membership. Si falla su entrega después del commit, usar el modo
`-RecoverJobId ... -ConfirmRecovery` indicado por el script, nunca repetir el
bootstrap.

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

## Reset de base efímera sin seed

Para demostrar una reconstrucción fresh sin tocar el deploy ni eliminar
volúmenes existe `scripts/ops/reset-ephemeral-database.ps1`. Es destructivo y
sólo opera sobre un contenedor `db` ya iniciado que cumpla simultáneamente:

- target exacto `dev`, `test` o `ephemeral`;
- proyecto `gestudio-<target>-<12 hex>` y base derivada reemplazando `-` por `_`;
- usuarios `ge_<12 hex>_owner`, `ge_<12 hex>_app` y `ge_<12 hex>_ctl`;
- tres claves distintas con prefijo `ephemeral-<12 hex>-` y al menos 24
  caracteres aleatorios adicionales;
- `JWT_SECRET` con ese mismo prefijo, una clave MFA Base64 de 32 bytes generada
  criptográficamente para esa ejecución y ningún secreto de email, métricas ni
  reset local. El operador es responsable de generar una clave nueva; el script
  sólo valida el formato y rechaza el valor inseguro conocido;
- imagen `gestudio-backend:ephemeral-<12 hex>` ya construida y con metadata
  Flyway igual a las migraciones locales;
- volumen `${ProjectName}_postgres_data`, labels Compose exactos y un único
  contenedor consumidor;
- perfil `dev`/`test`, Flyway activo, `ddl-auto=validate`, bootstrap, reset
  local, scheduler y email real deshabilitados.

El archivo de entorno debe ser sintético, privado y estar fuera del repo. No
reutilizar credenciales de producción. Con el proyecto efímero ya healthy:

```powershell
$suffix = 'a1b2c3d4e5f6' # generar uno nuevo por ejecución
$dockerContext = 'desktop-linux' # confirmar antes con: docker context show
$project = "gestudio-ephemeral-$suffix"
$database = $project.Replace('-', '_')
$confirmation = "RESET-EPHEMERAL-DATABASE:${dockerContext}:${project}:${database}"

docker --context $dockerContext compose -f .\docker-compose.yml `
  --env-file C:\secure\gestudio-ephemeral.env -p $project build backend
docker --context $dockerContext compose -f .\docker-compose.yml `
  --env-file C:\secure\gestudio-ephemeral.env -p $project up -d db

pwsh -NoProfile -File .\scripts\ops\reset-ephemeral-database.ps1 `
  -TargetEnvironment ephemeral `
  -DockerContext $dockerContext `
  -ProjectName $project `
  -DatabaseName $database `
  -EnvFile C:\secure\gestudio-ephemeral.env `
  -Confirmation $confirmation
```

La frase es case-sensitive. El preflight exige un contexto Docker explícito con
endpoint local (`npipe` o `/var/run/docker.sock`) y rechaza `DOCKER_HOST`,
production, staging, nombres
demo/remote, `gestudio-remote-demo`, bases no correlacionadas, Compose
alternativos, recursos sin ownership exacto y credenciales no sintéticas antes
del `DROP SCHEMA`. Luego recrea sólo `public`, deja que el backend ejecute
Flyway con validación, exige health real, roles runtime `NOSUPERUSER` y
`NOBYPASSRLS`, y comprueba cero tenants, usuarios, memberships, alumnos,
profesores y pagos. Nunca ejecuta `prune`, `down -v` ni borra volúmenes. Un
fallo devuelve exit code no cero y no imprime el contenido efectivo del env.

Contrato estático, ejecutable aun sin Docker:

```powershell
pwsh -NoProfile -File .\scripts\ops\test-reset-ephemeral-database-contract.ps1
```

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
- bootstrap de plataforma ausente: verificar que no exista `platform_admins` y
  ejecutar el job one-shot; no habilitar la bandera en el backend ordinario;
- recovery codes no entregados tras commit: recuperar desde el job retenido con
  su ID completo y `-ConfirmRecovery`, sin volver a crear la identidad;
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
