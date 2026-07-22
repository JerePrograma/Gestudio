# Demo remota: Cloudflare Pages y backend local

## Estado y alcance

Este runbook prepara Gestudio para una ronda de pruebas remota con esta topología:

```text
navegador del tester
  -> Cloudflare Pages (frontend React/Vite)
  -> hostname HTTPS de API
  -> Cloudflare Tunnel nombrado
  -> http://127.0.0.1:18080
  -> backend Spring Boot local
  -> PostgreSQL local sin puerto publicado
```

El repositorio aporta el perfil `remote-demo`, el override de Docker Compose, el
launcher local y la generación de cabeceras estáticas. La cuenta de Cloudflare,
DNS, TLS, el túnel, WAF, rate limiting, alertas, dominios y secretos pertenecen a
un segmento operativo posterior y nunca se versionan.

Esta modalidad es una demo pública controlada, no alta disponibilidad ni un
reemplazo de producción. El host local, Docker y `cloudflared` deben permanecer
encendidos y conectados.

## Contratos de seguridad

- El backend usa `SPRING_PROFILES_ACTIVE=remote-demo`.
- `ProductionConfigurationGuard` exige CORS HTTPS explícito, cookie de refresh
  `Secure` y token de métricas independiente de al menos 32 bytes UTF-8.
- El perfil no activa SMTP/IMAP: usa `NoOpEmailService`.
- PostgreSQL no publica ningún puerto del host.
- El backend publica un único binding en `127.0.0.1:18080`.
- El frontend Docker queda fuera del arranque remoto; Cloudflare Pages sirve
  `frontend/dist`.
- `APP_CORS_ALLOWED_ORIGINS` contiene un único origin HTTPS exacto, sin path,
  wildcard, credenciales, query ni fragmento.
- La cookie es host-only: `APP_SECURITY_REFRESH_COOKIE_DOMAIN` queda vacío.
- Bootstrap, reset local, scheduling e integración externa quedan deshabilitados.
- `.env.remote-demo` está ignorado y no debe confirmarse ni copiarse a Pages.
- El hostname público de API debe exponer sólo `/api/**`; `/actuator/**` debe
  permanecer inaccesible desde Internet.

Con `SameSite=Strict`, el frontend y la API deben ser subdominios HTTPS del mismo
sitio registrable, por ejemplo `app.dominio.tld` y `api.dominio.tld`. No usar una
combinación `pages.dev`/otro dominio sin volver a probar refresh y logout.

## Archivos

| Archivo | Función |
|---|---|
| `.env.remote-demo.example` | plantilla sin secretos |
| `.env.remote-demo` | configuración local real, ignorada |
| `backend/src/main/resources/application-remote-demo.yml` | perfil Spring público sin correo real |
| `docker-compose.remote-demo.yml` | elimina el puerto de PostgreSQL y limita backend a loopback |
| `scripts/demo-remote.ps1` | `Start`, `Status`, `Stop` y `Reset` |
| `scripts/remote-demo/*` | módulos internos y contrato SQL del launcher; no ejecutar directamente |
| `frontend/public/_headers` | plantilla versionada para Cloudflare Pages |
| `frontend/scripts/generate-pages-headers.mjs` | sustituye el origin exacto de API durante el build |

## Requisitos del host

- Git.
- JDK 21 completo.
- Node.js 22 y npm compatible.
- Docker Desktop o Docker Engine con Compose v2.
- PowerShell 7 o Windows PowerShell 5.1.
- `cloudflared`, únicamente cuando se configure el túnel.

```powershell
git --version
java -version
javac -version
node --version
npm --version
docker version
docker compose version
$PSVersionTable.PSVersion
```

No continuar si Java no es 21, Docker no informa el servidor o el árbol Git no
está limpio.

## Preparar `.env.remote-demo`

Copiar la plantilla:

```powershell
Set-Location (git rev-parse --show-toplevel)
Copy-Item .\.env.remote-demo.example .\.env.remote-demo
```

Completar valores reales exclusivamente en `.env.remote-demo`:

- `POSTGRES_PASSWORD`: aleatoria y exclusiva de esta base;
- `JWT_SECRET`: aleatorio, mínimo 32 bytes UTF-8;
- `APP_OBSERVABILITY_METRICS_TOKEN`: aleatorio, mínimo 32 bytes UTF-8 y distinto
  de `JWT_SECRET`;
- `APP_CORS_ALLOWED_ORIGINS`: origin HTTPS definitivo de Cloudflare Pages;
- los demás valores deben conservar los contratos de la plantilla.

No agregar `VITE_API_BASE_URL` al archivo del backend: esa variable se configura
en el build de Cloudflare Pages.

Comprobación previa:

```powershell
git check-ignore --quiet .env.remote-demo
if ($LASTEXITCODE -ne 0) { throw '.env.remote-demo no está ignorado' }

git ls-files --error-unmatch .env.remote-demo 2>$null
if ($LASTEXITCODE -eq 0) { throw '.env.remote-demo está versionado' }
```

## Iniciar y sembrar la demo

La primera ejecución sobre una base vacía solicita por TTY cinco contraseñas
distintas, de 12 a 72 bytes UTF-8:

- `demo-superadmin`;
- `demo-direccion`;
- `demo-administrador`;
- `demo-secretaria`;
- `demo-caja`.

Las contraseñas se convierten a BCrypt en memoria, no se escriben en archivos y
no se imprimen. No reutilizar contraseñas personales o productivas.

PowerShell 7:

```powershell
pwsh -NoProfile -File .\scripts\demo-remote.ps1 -Action Start
```

Windows PowerShell 5.1:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\demo-remote.ps1 `
  -Action Start
```

`Start` realiza estas comprobaciones antes de declarar disponibilidad:

1. valida `.env.remote-demo` sin mostrar secretos;
2. renderiza ambos archivos Compose;
3. levanta sólo `db` y `backend` bajo el proyecto fijo
   `gestudio-remote-demo`;
4. sincroniza la contraseña del rol PostgreSQL mediante entrada estándar;
5. construye y recrea el backend actual;
6. exige ambos contenedores `healthy`;
7. confirma PostgreSQL sin puerto y backend sólo en `127.0.0.1`;
8. valida el manifiesto Flyway real;
9. sobre base vacía, aplica el seed sintético de 914 filas y cinco roles;
10. exige readiness `UP`.

El endpoint local esperado es:

```text
http://127.0.0.1:18080
```

No abrir ni redirigir en el router los puertos `18080`, `8080`, `5432` ni la API
de Docker.

## Estado, detención y Reset

PowerShell 7:

```powershell
pwsh -NoProfile -File .\scripts\demo-remote.ps1 -Action Status
pwsh -NoProfile -File .\scripts\demo-remote.ps1 -Action Stop
pwsh -NoProfile -File .\scripts\demo-remote.ps1 -Action Reset
```

Windows PowerShell 5.1:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\demo-remote.ps1 -Action Status

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\demo-remote.ps1 -Action Stop

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\demo-remote.ps1 -Action Reset
```

- `Status` termina con código `1` si health, red, Flyway, seed o readiness no
  cumplen el contrato.
- `Stop` elimina contenedores y red del proyecto remoto, pero conserva sus
  volúmenes.
- `Reset` elimina únicamente los volúmenes del proyecto
  `gestudio-remote-demo`, recrea el stack y solicita nuevas contraseñas demo.
- Detener temporalmente el túnel antes de `Reset` para que ningún tester acceda
  mientras Flyway y el seed reconstruyen el estado.
- Ninguna acción ejecuta una limpieza Docker global ni afecta
  `gestudio-demo-local`.

## Backup antes de compartir acceso

Antes de una ronda de pruebas, crear un backup base y conservarlo fuera del
repositorio. El directorio elegido no debe estar dentro del checkout.

```powershell
$backupRoot = Join-Path `
  ([Environment]::GetFolderPath('MyDocuments')) `
  'GestudioBackups\RemoteDemo'

New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\ops\backup-postgres.ps1 `
  -EnvFile .\.env.remote-demo `
  -ProjectName gestudio-remote-demo `
  -OutputDirectory $backupRoot `
  -StopBackend
```

Después del backup, volver a iniciar con `demo-remote.ps1 -Action Start`.
Validar una restauración primero sobre una base alternativa siguiendo
`docs/operations/backup-restore.md`. `Reset` recrea el dataset demo; no sustituye
un backup cuando deban conservarse resultados de una ronda.

## Cloudflare Pages — segmento posterior

Configuración prevista, todavía externa al repositorio:

| Campo | Valor |
|---|---|
| Repositorio | `JerePrograma/Gestudio` |
| Rama de producción | `main` |
| Root directory | `frontend` |
| Build command | `npm run build` |
| Output directory | `dist` |
| Node | `22.14.0` o Node 22 LTS compatible |
| `VITE_API_BASE_URL` | `https://<api-host>/api` |
| `VITE_APP_TIME_ZONE` | `America/Argentina/Buenos_Aires` |

No cargar secretos en Pages. Las variables `VITE_*` son públicas y quedan dentro
del bundle.

Durante `npm run build`, Vite copia la plantilla `public/_headers` y el generador
reemplaza `__GESTUDIO_API_ORIGIN__` por el origin derivado de
`VITE_API_BASE_URL`. El build falla si la URL falta, es inválida o usa HTTP fuera
de localhost. El archivo final `dist/_headers` no debe conservar el placeholder.

Los preview deployments deben deshabilitarse o mantenerse fuera del flujo de
autenticación hasta incluir deliberadamente sus origins exactos en CORS.

## Cloudflare Tunnel — segmento posterior

Crear un túnel nombrado, no un Quick Tunnel, y publicar:

```text
https://<api-host> -> http://127.0.0.1:18080
```

El token del túnel es secreto: debe existir sólo en el host autorizado. Registrar
`cloudflared` como servicio automático una vez creada la configuración. No
colocar Cloudflare Access delante de la aplicación mientras el objetivo sea que
terceros puedan probar el login libremente.

En el hostname de API:

- bloquear toda ruta que no comience por `/api/`;
- limitar `POST /api/login` por IP con una regla conservadora;
- no exponer `/actuator/**`;
- habilitar alertas de túnel `Down`/`Degraded`;
- comprobar DNS proxied y TLS válido.

## IP del cliente detrás del túnel

El backend conserva `HttpServletRequest.getRemoteAddr()`. Detrás de
`cloudflared`, el dato puede representar al conector local y no al navegador.
No confiar todavía en `CF-Connecting-IP`: aceptar una cabecera reenviada sin una
política de proxies confiables permitiría falsificación. La resolución debe
hacerse en el segmento de Cloudflare, sólo después de confirmar que el backend
acepta tráfico exclusivamente desde loopback.

## Disponibilidad del host

Mientras la demo esté publicada:

- impedir la suspensión de Windows cuando esté conectado a corriente;
- iniciar Docker Desktop automáticamente;
- mantener `cloudflared` como servicio automático;
- evitar reinicios no planificados;
- supervisar espacio de disco, estado de Docker y conectividad;
- rotar credenciales entre rondas de prueba;
- ejecutar `Reset` cuando deba restaurarse el dataset sintético inicial.

El frontend de Pages puede seguir respondiendo mientras el host está apagado,
pero login y operaciones de API fallarán.

## Troubleshooting

### `Status` informa backend no disponible

```powershell
docker compose `
  --env-file .\.env.remote-demo `
  -f .\docker-compose.yml `
  -f .\docker-compose.remote-demo.yml `
  -p gestudio-remote-demo `
  ps -a

docker compose `
  --env-file .\.env.remote-demo `
  -f .\docker-compose.yml `
  -f .\docker-compose.remote-demo.yml `
  -p gestudio-remote-demo `
  logs --tail 100 db backend
```

No publicar esos logs sin revisar que no contengan datos personales. El launcher
redacta los secretos conocidos al mostrar diagnósticos.

### CORS o refresh falla

Confirmar que `APP_CORS_ALLOWED_ORIGINS` coincide carácter por carácter con el
origin visible en el navegador y no incluye `/`. Confirmar además:

```text
APP_SECURITY_REFRESH_COOKIE_SECURE=true
APP_SECURITY_REFRESH_COOKIE_SAME_SITE=Strict
APP_SECURITY_REFRESH_COOKIE_DOMAIN=
APP_SECURITY_REFRESH_COOKIE_PATH=/api/login
```

### PostgreSQL aparece publicado

Detener inmediatamente la demo y revisar el Compose renderizado:

```powershell
docker compose `
  --env-file .\.env.remote-demo `
  -f .\docker-compose.yml `
  -f .\docker-compose.remote-demo.yml `
  -p gestudio-remote-demo `
  config
```

El servicio `db` no debe tener `ports`. El backend debe mostrar únicamente un
binding `127.0.0.1:<BACKEND_PORT>:8080`.

### El dataset está incompleto o fue alterado

Conservar un backup si los cambios deben revisarse. Para volver a la línea base
sintética:

```powershell
pwsh -NoProfile -File .\scripts\demo-remote.ps1 -Action Reset
```

`Reset` es destructivo únicamente para los volúmenes del proyecto remoto.
