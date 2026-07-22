# Demo local persistente

Requisitos: Docker Desktop/Engine con Compose v2 y JDK 21 disponible. El
proyecto Compose reservado es `gestudio-demo-local`; los puertos son PostgreSQL
`15432`, backend `18080` y frontend `18081`.

## Inicio

Desde la raíz:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\demo-local.ps1 `
  -Action Start
```

`Start`:

1. deriva el manifiesto contiguo de migraciones desde
   `backend/src/main/resources/db/migration`; hoy resulta V1-V7;
2. construye backend y frontend con revisión Git, hash de Compose y metadata
   Flyway;
3. fuerza la recreación de backend y frontend aunque los contenedores previos
   estén healthy;
4. conserva PostgreSQL y sus volúmenes;
5. aplica el seed dos veces con la misma ancla y las mismas credenciales;
6. valida snapshot idéntico, RBAC, frontend, CORS, cookie, login, cumpleaños y
   denegaciones HTTP;
7. exige que `Status` confirme un stack vigente antes de terminar en cero.

No se reutiliza silenciosamente un contenedor sano creado desde una imagen
anterior. No se borran volúmenes durante `Start`.

## Fecha del dataset y cumpleaños

El seed separa dos conceptos:

- `demo_anchor_date`: ancla estable de períodos, importes y hechos históricos;
- `demo_business_date`: día civil de la ejecución en
  `America/Argentina/Buenos_Aires`.

La reejecución conserva el ancla histórica, pero alinea el cumpleaños designado
con el día comercial actual. El endpoint de cumpleaños incluye sólo personas
activas cuyo día corresponde exactamente a hoy. No adelanta cumpleaños
próximos. Un nacimiento del 29 de febrero se observa el 28 de febrero en años
no bisiestos y el 29 en años bisiestos.

## Acceso

- Frontend: `http://localhost:18081`
- Backend: `http://localhost:18080`
- API: `http://localhost:18080/api`
- PostgreSQL: `localhost:15432`, base `gestudio_demo_local`
- Liveness: `http://localhost:18080/actuator/health/liveness`
- Readiness: `http://localhost:18080/actuator/health/readiness`

Usuarios:

- `demo-superadmin`
- `demo-direccion`
- `demo-administrador`
- `demo-secretaria`
- `demo-caja`

Las contraseñas se solicitan como `SecureString`, se definen sólo localmente y
no se escriben en Git, logs ni archivos temporales. No reutilizar credenciales
reales.

## Estado, stop y reset

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-local.ps1 -Action Status
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-local.ps1 -Action Stop
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-local.ps1 -Action Reset
```

`Status` diferencia y muestra:

- imagen inexistente;
- contenedor inexistente;
- contenedor basado en otra image ID;
- revisión Git o hash Compose incompatible;
- metadata Flyway incompatible;
- servicio no healthy;
- historial Flyway incompleto o con scripts inesperados;
- frontend no disponible;
- seed incompleto o cumpleaños diario desalineado.

La demo sólo está disponible cuando todas las condiciones son válidas. En caso
contrario imprime `Demo disponible: NO` y termina con exit code `1`. La versión
Flyway mostrada se deriva del manifiesto y de `flyway_schema_history`; no hay una
comparación fija con V7 que deba editarse cuando aparezca V8.

`Stop` ejecuta el descenso del proyecto y conserva datos. `Reset` usa el nombre
Compose fijo `gestudio-demo-local` y elimina únicamente contenedores, red y
volúmenes de ese proyecto; no afecta otros proyectos Docker.

## Cookies y seguridad local

Las cookies de `localhost` no se aíslan por puerto. La demo usa la cookie
host-only `gestudio_demo_refresh`, con `Secure=false`, `SameSite=Strict` y
`Path=/api/login`, para no colisionar con `gestudio_refresh`. No define
`Domain`. El Compose productivo exige cookie `Secure=true`.

Health es público y mínimo. `/actuator/prometheus` permanece protegido por un
token independiente: falta, error o cabeceras duplicadas producen `401`.

## Seed nativo

Para una base local vacía con la cadena Flyway completa:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\demo-local.ps1 `
  -Action SeedNative
```

La acción localiza `psql.exe`, solicita la clave de base y las cinco claves
demo, genera BCrypt y aplica el mismo SQL. Falla antes de escribir si encuentra
datos ajenos al namespace permitido. Admite `-DatabaseHost`, `-DatabasePort`,
`-DatabaseName`, `-DatabaseUser` y `-PsqlPath`.

## Evidencia del ciclo 2026-07-22

`Reset` recreó la demo desde volúmenes vacíos y aprobó 914 filas, cinco hashes,
cinco logins, CORS, cookie, RBAC y dos aplicaciones idénticas del seed. El
recorrido headed de navegador aprobó los cinco roles en escritorio y móvil. El
detalle está en `human-role-walkthrough.md` y en el cierre técnico 23.
