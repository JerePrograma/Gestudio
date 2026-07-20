# Demo local persistente

Requisitos: Docker Desktop con Compose v2 y JDK 21 configurado en `JAVA_HOME`.

Desde la raíz del repositorio:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\demo-local.ps1 `
  -Action Start
```

`Start` construye las imágenes, levanta el proyecto Compose aislado
`gestudio-demo-local`, aplica Flyway V1-V7 sobre PostgreSQL vacío cuando
corresponde, solicita las cinco contraseñas como `SecureString`, aplica dos
veces el seed manual y valida frontend, CORS, cookie, login, RBAC e integridad.
La demo continúa ejecutándose al terminar el script.

## Acceso

- Frontend: `http://localhost:18081`
- Backend: `http://localhost:18080`
- API usada por el frontend: `http://localhost:18080/api`
- PostgreSQL: `localhost:15432`, base `gestudio_demo_local`

Usuarios:

- `demo-superadmin`
- `demo-direccion`
- `demo-administrador`
- `demo-secretaria`
- `demo-caja`

Las contraseñas se piden en cada `Start` o `Reset`. Pueden ser cortas y
repetidas; sólo se rechazan valores vacíos, compuestos únicamente por espacios
o mayores que el límite técnico de 72 bytes UTF-8 de BCrypt. No se escriben en
archivos ni logs. El único hash persistente es el que necesita la tabla
`usuarios`.

## Operación

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-local.ps1 -Action Status
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-local.ps1 -Action Stop
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-local.ps1 -Action Reset
```

- `Status` muestra URLs, base, estado/health, versión Flyway y disponibilidad.
- `Stop` elimina contenedores y red, pero conserva los volúmenes y los datos.
- `Reset` elimina también los volúmenes y recrea la demo desde cero; vuelve a
  solicitar las contraseñas.

Los puertos son fijos. Si `15432`, `18080` o `18081` están ocupados por otro
proceso o contenedor, el inicio falla e identifica al ocupante; nunca cambia de
puerto silenciosamente.

## Cookies locales

Las cookies de `localhost` no se aíslan por puerto. La demo usa la cookie
host-only `gestudio_demo_refresh`, con `Secure=false`, `SameSite=Strict` y
`Path=/api/login`, para no colisionar con `gestudio_refresh` de los entornos en
`5173`/`8080`. No define `Domain`.

`scripts/validate-demo-seed.ps1` continúa siendo el gate integral descartable;
`demo-local.ps1` es el lanzador persistente para uso humano.

## Seed sobre PostgreSQL local nativo

Para poblar una base local vacía que ya tenga Flyway V1-V7, sin depender de
Docker ni de `psql` en `PATH`:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\demo-local.ps1 `
  -Action SeedNative
```

La acción localiza `psql.exe` en la instalación de PostgreSQL, solicita la
contraseña de la base y las cinco contraseñas demo, genera BCrypt y aplica el
mismo `gestudio_demo_seed_full.sql`. Falla antes de escribir si encuentra datos
ajenos a los catálogos productivos de V1-V7. Los parámetros opcionales son
`-DatabaseHost`, `-DatabasePort`, `-DatabaseName`, `-DatabaseUser` y
`-PsqlPath`.
