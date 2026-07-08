# Desarrollo local

## Requisitos

| Herramienta | Versión de referencia | Uso |
| --- | --- | --- |
| Windows PowerShell | 5.1 o PowerShell 7 | Scripts locales y acciones Codex |
| Git | 2.x | Control de versiones |
| JDK | 21 | Compilación y ejecución backend |
| Maven Wrapper | 3.9.10 | Build reproducible; no requiere Maven global |
| Node.js | 22.14.0 | Build frontend |
| npm | 10.x | Instalación reproducible con lockfile |
| Docker Desktop | Engine activo | PostgreSQL y stack en contenedores |
| Docker Compose | v2 o superior | Orquestación local |

No hay componente Python requerido.

## Preparación inicial

1. Definí `JAVA_HOME` con la ruta de un JDK 21. En el host auditado: `C:\Program Files\Java\corretto-21.0.7`.
2. Si vas a usar Compose, creá una configuración local no versionada:

   ```powershell
   Copy-Item .env.local.example .env
   ```

3. Ajustá puertos o credenciales locales en `.env` si difieren de los ejemplos. Sólo Compose carga `.env`; Maven y Vite reciben variables de la terminal, scripts o IDE.
4. Resolvé dependencias sin iniciar servicios ni ejecutar tests completos:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\setup.ps1
   ```

`setup.ps1` exige JDK 21, usa `backend\mvnw.cmd dependency:go-offline` y `frontend\npm ci`. No instala herramientas globales.

## Perfiles Spring

- `dev`: perfil local explícito; PostgreSQL local, email no-op y schedulers deshabilitados salvo `APP_SCHEDULING_ENABLED=true`.
- `test`: email no-op, schedulers deshabilitados, recibos en temporales y Flyway deshabilitado por defecto. Las pruebas PostgreSQL deben proporcionar su datasource aislado.
- `prod`: datasource, JWT, SMTP/IMAP, CORS, zona horaria y almacenamiento obligatorios; `ddl-auto=validate`; Flyway activo por defecto; email real; schedulers activos.

La configuración común vive en `backend/src/main/resources/application.yml`. No existe un perfil predeterminado: fuera de Compose, el script local o el IDE deben declarar `SPRING_PROFILES_ACTIVE=dev`. Los perfiles no contienen secretos reales.

Flyway aplica V1 como baseline canónica y luego las migraciones forward-only
V2–V5. V5 crea el catálogo RBAC y backfillea `usuario_roles` desde
`usuarios.rol_id`. El historial retirado V1-V060 no forma parte del runtime ni
constituye una ruta de upgrade soportada.

Los scripts no importan `.env`. Para ejecutar Maven/Vite con puertos distintos, exportá las variables en la misma terminal; las rutas con espacios se asignan como strings normales de PowerShell:

```powershell
$env:SPRING_PROFILES_ACTIVE = "dev"
$env:SPRING_DATASOURCE_URL = "jdbc:postgresql://localhost:5433/ledance_db"
$env:BACKEND_PORT = "8090"
$env:SERVER_PORT = $env:BACKEND_PORT
$env:FRONTEND_PORT = "5190"
$env:LEDANCE_HOME = "C:\ruta con espacios\le-dance"
```

`start-backend.ps1` declara `dev` sólo para la ejecución local cuando la terminal no eligió otro perfil y traduce `BACKEND_PORT` a `SERVER_PORT`. `start-frontend.ps1` pasa `FRONTEND_PORT` a Vite. Compose usa su propio `.env` y mantiene PostgreSQL en 5432 dentro de la red Docker aunque publique otro puerto al host.

## Ejecución local

Base de datos:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dev\start-db.ps1
```

Backend:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dev\start-backend.ps1
```

Frontend:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dev\start-frontend.ps1
```

Detener sólo los contenedores del proyecto, conservando volúmenes:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dev\stop.ps1
```

Los procesos Maven/Vite iniciados en primer plano se detienen desde su propia terminal. Ningún script ejecuta `docker compose down -v`.

## Docker Compose

`docker-compose.yml` es la configuración local: construye imágenes, usa puertos configurables, healthchecks y nombres de proyecto derivados del worktree. Para worktrees paralelos, definí un `COMPOSE_PROJECT_NAME` distinto sólo si los nombres de directorio coinciden.

```powershell
docker compose config
docker compose up -d db
docker compose ps
```

`docker-compose.prod.yml` es el único mecanismo de despliegue soportado. Exige secretos y URLs explícitos, elimina la publicación de PostgreSQL heredada del archivo local y no debe iniciarse para desarrollo:

```powershell
docker compose -f docker-compose.yml -f docker-compose.prod.yml config
```

## Bootstrap único del superadministrador

Sólo para una base sin usuarios, exportá temporalmente las tres variables antes
de iniciar el backend:

```powershell
$env:APP_BOOTSTRAP_SUPERADMIN_ENABLED = "true"
$env:APP_BOOTSTRAP_SUPERADMIN_USERNAME = "admin-inicial"
$bootstrapSecret = Read-Host "Clave inicial" -AsSecureString
$env:APP_BOOTSTRAP_SUPERADMIN_PASSWORD = [System.Net.NetworkCredential]::new("", $bootstrapSecret).Password
Remove-Variable bootstrapSecret
```

En producción preferí el mecanismo de secretos del entorno. Una vez creado el
usuario, detené el proceso y eliminá las variables del proceso o del secret
store. Si la bandera continúa activa al reiniciar, la aplicación falla cerrado.

El rol de máximo privilegio es `SUPERADMIN`. El bootstrap reclama una ejecución
única, sincroniza `usuarios.rol_id` y `usuario_roles`, usa BCrypt y exige una
clave externa de 16 a 72 bytes UTF-8. Después del primer arranque se debe recrear
el backend con `APP_BOOTSTRAP_SUPERADMIN_ENABLED=false`.

El alias `APP_BOOTSTRAP_ADMIN_*` queda sólo por compatibilidad. El reset de una
clave local existente usa `APP_BOOTSTRAP_ADMIN_RESET_EXISTING_PASSWORD=true` en
perfil `dev`; no convierte el bootstrap en reconciliador.

## Contrato RBAC

- Login, refresh y perfil devuelven `roles[]` y `permisos[]` sin prefijos.
- Spring genera `ROLE_` y `PERM_` sólo al construir authorities.
- Roles y permisos inactivos no autorizan.
- Los JWT no copian authorities; contienen identidad y `auth_version`.
- El refresh token no aparece en JSON: se rota en una cookie HttpOnly.
- `usuarios.rol_id` es compatibilidad temporal; `usuario_roles` es la relación
  efectiva y los cambios de seguridad incrementan `auth_version`.

## Smoke integrado local

El smoke canónico construye y levanta un proyecto Compose único con puertos,
red y volúmenes efímeros; no usa la base local ni se conecta a
`localhost:5432`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\smoke-local.ps1
```

Ejecuta bootstrap, seguridad, login/refresh, reinicio con bootstrap apagado,
alumno, inscripción/matrícula, cargo, pagos e idempotencia, recibo/outbox, caja,
egreso/reversión, stock/reversión, persistencia tras reinicio y auditorías SQL de
solo lectura. El detalle operativo está en [Smoke local](../testing/smoke-local.md).

Los volúmenes `postgres_data` y `receipts_data` son persistentes. No se eliminan en setup, cleanup ni stop.

PM2 no está soportado. Se retiró su configuración incompleta para no mantener dos mecanismos productivos divergentes.

## Validación

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\status.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1
```

Validaciones parciales:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Backend
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Frontend
```

El gate completo ejecuta `mvnw.cmd clean verify`, lint, tests frontend sólo si existe el script, build y `docker compose config`. Conserva el primer código de error y muestra todos los resultados.

El contrato frontend no interactivo es `npm test`, que ejecuta `vitest run` una
sola vez y termina. El modo de desarrollo queda separado y explícito:

```powershell
Push-Location frontend
npm test
npm run test:watch
Pop-Location
```

CI y `validate.ps1` usan únicamente `npm test`, sin reenviar argumentos.

En CI, `clean verify` se ejecuta primero en el runner con acceso a Docker para que Testcontainers use PostgreSQL 15. La construcción de imágenes es un job posterior y el `Dockerfile` backend empaqueta con `-DskipTests`; no monta `docker.sock` ni intenta iniciar Testcontainers dentro de BuildKit. Ambas imágenes se etiquetan con el SHA verificado. El workflow acepta push a `main`, pull requests y ejecución manual mediante `workflow_dispatch`; no publica imágenes ni despliega.

La baseline `041a27fd` se validó localmente el 2026-07-01 con 70 tests backend,
16 tests frontend, ambos Compose y ambas imágenes en verde. La evidencia completa
está en el [worklog canónico](../refactor/16-canonical-v1-worklog.md#cierre-de-reproducibilidad-ci-y-docker---2026-07-01).

## Configuración local de Codex

Script de configuración, pestaña Windows:

```powershell
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\setup.ps1
exit $LASTEXITCODE
```

Script de limpieza, pestaña Windows:

```powershell
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\cleanup.ps1
exit $LASTEXITCODE
```

Las variables y acciones completas están en [Variables de entorno](environment-variables.md#variables-recomendadas-para-codex) y en la entrega de esta auditoría.

Acciones recomendadas; todas usan `C:\laburo\le-dance` como directorio de ejecución:

| Nombre | Comando |
| --- | --- |
| Estado | `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\status.ps1` |
| Preparar entorno | `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\setup.ps1` |
| Validar todo | `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1` |
| Validar backend | `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Backend` |
| Validar frontend | `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Frontend` |
| Smoke integrado | `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\smoke-local.ps1` |
| Iniciar base | `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dev\start-db.ps1` |
| Iniciar backend | `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dev\start-backend.ps1` |
| Iniciar frontend | `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dev\start-frontend.ps1` |
| Ver servicios | `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\status.ps1` |
| Detener servicios | `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dev\stop.ps1` |

## Solución de problemas

- `java -version` muestra Java 8 pero existe JDK 21: corregí `JAVA_HOME`; los scripts usan directamente `%JAVA_HOME%\bin\java.exe`.
- Maven informa `JAVA_HOME ... not defined correctly`: la ruta no existe o no contiene `bin\java.exe`.
- Puerto 5432 ocupado: cambiá `POSTGRES_PORT` en `.env`; el backend en Docker sigue usando `db:5432` internamente.
- Docker CLI funciona pero Engine no: iniciá Docker Desktop y esperá a que `docker info` finalice con código 0.
- `npm ci` falla: no reemplaces por `npm install`; verificá que `frontend/package-lock.json` esté presente y sincronizado.
- El backend no valida el esquema: iniciá PostgreSQL, revisá credenciales y no cambies `ddl-auto` a `update`.
- Producción rechaza el inicio: completá todas las variables marcadas como obligatorias; no agregues fallbacks inseguros.
