# Despliegue idempotente en Windows

`deploy.cmd` es el único punto de entrada para desplegar Gestudio desde un
checkout limpio. El launcher se puede abrir desde el Explorador o ejecutar
desde `cmd.exe` o PowerShell, incluso cuando el directorio actual no es el
repositorio y la ruta contiene espacios. Toda la lógica reside en PowerShell;
el archivo Batch solo resuelve su propia ruta, selecciona PowerShell 7 o
Windows PowerShell 5.1 y propaga argumentos y código de salida.

Este procedimiento despliega un entorno local autocontenido. No constituye una
aprobación de producción: TLS, DNS, CORS público, correo real, almacenamiento
externo, monitoreo y gestión organizacional de secretos siguen requiriendo un
ambiente autorizado.

## Requisitos

- Windows 10 u 11.
- PowerShell 7 o Windows PowerShell 5.1.
- Docker Desktop ya iniciado por el usuario.
- Docker CLI y Docker Compose v2 disponibles en `PATH`.
- Puertos predeterminados libres: PostgreSQL `25432`, backend `28080` y
  frontend `28081`.
- Checkout Git limpio cuando el bundle contiene `.git`.

El launcher no requiere privilegios de administrador, no inicia Docker Desktop,
no cambia su contexto, no modifica variables globales y no toca el proyecto
protegido `gestudio-remote-demo`.

## Primer despliegue

Desde el Explorador, haga doble clic en `deploy.cmd`. Desde una terminal:

```cmd
deploy.cmd
```

La primera ejecución:

1. adquiere un mutex exclusivo para el repositorio y proyecto;
2. valida Windows, PowerShell, Git, Docker, Compose, archivos y puertos;
3. crea `.gestudio-deploy/config/deploy.env` con secretos aleatorios locales;
4. valida `docker compose config`;
5. construye las imágenes backend y frontend;
6. crea o reconcilia los logins externos de runtime tenant y control-plane;
7. crea el volumen PostgreSQL y ejecuta Flyway con el migrador;
8. arranca el backend seedless con `gestudio_runtime` y
   `gestudio_control_runtime`; el bootstrap queda deshabilitado;
9. verifica PostgreSQL, Flyway, separación de privilegios, RLS, backend, seguridad anónima,
   frontend y logs;
10. escribe el último estado exitoso de forma atómica.

Después de un deploy healthy, el primer `SUPERADMIN` se crea mediante el job
one-shot externo documentado en [Bootstrap inicial](#bootstrap-inicial). Sus
credenciales, MFA y recovery codes nunca quedan en el entorno del servicio
ordinario.

El proyecto Compose predeterminado es `gestudio-windows`. Para evitar colisiones,
no se selecciona un nombre o un puerto alternativo de forma automática.

## Ejecuciones siguientes

Ejecute el mismo comando:

```cmd
deploy.cmd
```

Con el mismo commit y configuración, el launcher contrasta el estado persistido
con Docker, Flyway y los endpoints reales. Si todo está sano, no ejecuta build,
backup, `compose up` ni migraciones, no recrea contenedores y no rota secretos.
Un drift de disponibilidad puede repararse con Compose sin build; un drift de
imagen, configuración o datos que no sea seguro converge con código `10`.

Cuando cambia el commit se reconstruyen imágenes para que la metadata de la
imagen coincida con el commit desplegado. Cuando cambia el historial de
migraciones y ya existe una base, se exige un backup válido antes de continuar.

## Modos de solo lectura

```cmd
deploy.cmd --dry-run
deploy.cmd --verify-only
deploy.cmd --help
```

- `--dry-run` ejecuta preflight, resuelve una configuración efímera, valida
  Compose, calcula el fingerprint y muestra el plan. No crea configuración
  efectiva, estado, contenedores, redes ni volúmenes.
- `--verify-only` no construye, migra, arranca ni recrea. Exige que el estado,
  las imágenes, la configuración, Flyway, los contenedores y los endpoints
  coincidan con el checkout actual.
- `--help` no requiere Docker y muestra sintaxis, requisitos, archivos locales,
  backups, idempotencia y códigos de salida.

Dos despliegues concurrentes no están permitidos. El segundo termina con código
`8` antes de modificar recursos.

## Configuración, estado y logs

Todo el estado local vive en el directorio ignorado `.gestudio-deploy/`:

| Ruta | Contenido |
|---|---|
| `.gestudio-deploy/config/deploy.env` | Configuración efectiva y secretos locales |
| `.gestudio-deploy/state/deployment.json` | Último despliegue exitoso, sin secretos |
| `.gestudio-deploy/logs/` | Un log sanitizado por ejecución normal |
| `.gestudio-deploy/backups/` | Paquetes creados antes de upgrades Flyway |
| `.gestudio-deploy/test-results/` | Evidencia no sensible del gate aislado |

La plantilla versionada es
`scripts/deploy/deploy.env.example`. Para personalizar puertos o endpoints,
edite la copia efectiva antes del despliegue. Un puerto ocupado solo se acepta
cuando pertenece al mismo proyecto Compose; el launcher no mata procesos ni
elige otro puerto silenciosamente.

El estado JSON incluye formato, último éxito UTC, commit, fingerprint, proyecto,
Compose, versión de aplicación, Flyway, imágenes/configuración de contenedores,
puertos, endpoints, health checks y último backup. No contiene contraseñas,
tokens, claves JWT, el contenido del `.env` ni cadenas de conexión con
credenciales. Una ejecución fallida conserva el último estado exitoso.

## Política de secretos

- No hay secretos reales versionados.
- La primera ejecución genera valores criptográficamente aleatorios cuando
  faltan y los persiste solo en `deploy.env`.
- Las ejecuciones posteriores reutilizan esos valores y nunca los rotan de
  forma automática. Una rotación explícita del operador cambia el fingerprint,
  reconcilia el password del login y converge los servicios sin reemplazar el
  volumen ni crear un backup de esquema innecesario.
- Una variable nueva se agrega sin reemplazar las existentes y solo se registra
  su nombre.
- Los secretos no se imprimen, no se guardan en el estado y se sanitizan en
  errores y logs.
- El tráfico de correo real permanece deshabilitado y fail-closed.

`.gitignore` cubre el directorio completo. El preflight también exige que Git
reconozca la configuración efectiva como ignorada.

## Bootstrap inicial

El servicio ordinario fija `APP_BOOTSTRAP_SUPERADMIN_ENABLED=false`. Una vez que
el deploy terminó healthy y antes de habilitar tráfico de plataforma, ejecute el
job one-shot desde una terminal interactiva:

```powershell
$recoveryCodes = 'C:\ruta-segura\gestudio-platform-recovery-codes.txt'
pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\ops\bootstrap-platform-admin.ps1 `
  -EnvFile .\.gestudio-deploy\config\deploy.env `
  -ProjectName gestudio-windows `
  -Username '<superadmin-inicial>' `
  -RecoveryCodesPath $recoveryCodes `
  -ConfirmBootstrap
```

El script solicita password, secreto TOTP Base32 y código TOTP como
`SecureString`; no los agregue a la línea de comandos. Rechaza un claim previo,
el proyecto protegido `gestudio-remote-demo` y un destino de recovery codes ya
existente. Sólo informa éxito tras verificar identidad/admin activos, MFA TOTP
verificado, exactamente diez recovery codes sin usar y cero memberships tenant.
Copia los códigos antes de eliminar el contenedor temporal, restringe el ACL al
usuario Windows actual y nunca imprime su contenido. Custodie ese archivo fuera
del checkout mediante el procedimiento organizacional aprobado.

Si PostgreSQL ya confirmó el bootstrap pero falla el copiado o la protección
local, el script termina con error, intenta detener y **conserva únicamente ese
job one-shot**: no vuelva a ejecutar el bootstrap. El error incluye un comando
sanitizado con `-RecoverJobId <id-completo> -ConfirmRecovery`; ejecútelo con el
mismo Compose, env y proyecto, y con un `RecoveryCodesPath` que todavía no
exista. Ese modo no solicita ni acepta username, password, secreto TOTP o código
TOTP: valida el ID completo, los labels y nombre exactos del job, y el
claim/MFA/códigos/membership en PostgreSQL. Sólo elimina el contenedor después
de publicar un archivo con exactamente diez códigos y ACL exclusivo del usuario
Windows actual. Si la
recuperación vuelve a fallar, conserva el job y devuelve exit code no cero; no
inspeccione su entorno ni sus logs porque el contenedor retenido contiene los
secretos de bootstrap. Recupérelo y elimínelo mediante el mismo comando tan
pronto como sea operacionalmente posible.

## Backups y upgrades

El launcher reutiliza `scripts/ops/backup-postgres.ps1`. Solo crea un backup
cuando existe una base persistente y cambió el fingerprint de migraciones. El
paquete contiene dump PostgreSQL, recibos, manifiesto y hashes; debe validarse
antes de aplicar la migración.

Una ejecución sin cambios no crea otro backup. Ante un fallo posterior, el
launcher conserva volumen, backup y logs, devuelve un código no cero y no hace
restore automático. La recuperación siempre es una decisión explícita del
operador mediante el runbook de [backup y restore](operations/backup-restore.md).

El gate automatizado deriva la última versión del checkout y valida un upgrade
desde el fixture histórico anterior a V8 sobre un volumen aislado: backup
previo, sólo migraciones pendientes, datos y ACL conservados, grants del
migrador conservados, separación de runtimes tenant/control-plane, RLS `GREEN`
y una reejecución final sin migraciones ni backup adicional. También prueba una
rotación explícita de la credencial control-plane y su siguiente no-op.

## Health checks

Un exit code `0` exige todos estos contratos:

- contenedores PostgreSQL, backend y frontend `healthy`;
- Flyway con historia exacta `V1..Vlatest` o baseline exacta `Blatest`, sin
  fallos;
- runtimes tenant y control-plane distintos, cada uno miembro sólo de su rol
  técnico, sin `SUPERUSER`, `BYPASSRLS`, `CREATEROLE`, `CREATEDB` ni
  `REPLICATION`;
- control-plane sin acceso al dominio funcional tenant; su acceso a
  `tenants`, memberships y roles es el mínimo de provisioning, siempre con
  target `TenantContext` y RLS. El runtime tenant no tiene DML global sobre
  `tenants`, `platform_admins`, bootstrap, sesiones/MFA/idempotencia/auditoría
  de plataforma;
- health estructural RLS `GREEN` desde V10;
- cero o un claim de bootstrap; si existe, debe enlazar un administrador de
  plataforma activo;
- `GET /actuator/health/readiness`: HTTP `200`, JSON con `status=UP`;
- `GET /api/usuarios/perfil`: HTTP `401`, JSON no vacío y sin HTML/stack trace;
- frontend: HTTP `2xx` o `3xx` esperado y `text/html`;
- logs recientes sin errores fatales clasificados de Flyway, Hibernate, RLS,
  autenticación PostgreSQL, conexión o arranque.

Endpoints predeterminados:

- frontend: `http://127.0.0.1:28081/`;
- backend: `http://127.0.0.1:28080/`;
- API: `http://127.0.0.1:28080/api`;
- readiness: `http://127.0.0.1:28080/actuator/health/readiness`;
- PostgreSQL: `127.0.0.1:25432`.

## Detener sin borrar datos

Desde el repositorio, el comando operativo es:

```powershell
docker compose --env-file .\.gestudio-deploy\config\deploy.env -p gestudio-windows stop
```

`deploy.cmd` vuelve a arrancar el mismo proyecto y conserva los volúmenes. No
use `down -v`, `volume rm` ni herramientas de prune si necesita conservar datos.

## Códigos de salida

| Código | Significado |
|---:|---|
| `0` | Despliegue o verificación correcta |
| `2` | Argumento, plataforma, archivo o preflight inválido |
| `3` | Configuración incompleta o Compose inválido |
| `4` | Docker Server, Docker CLI o Compose no disponible |
| `5` | Build, reconciliación de roles, Compose o migración fallida |
| `6` | Health check fallido |
| `7` | Verificación funcional, Flyway, privilegios, RLS o logs fallida |
| `8` | Otro despliegue conserva el lock |
| `9` | Backup previo fallido |
| `10` | Drift no reparable de forma segura |

El launcher propaga exactamente el código del motor PowerShell. Ningún fallo
parcial devuelve `0`.

## Recuperación y límites deliberados

Revise primero el último log y ejecute:

```cmd
deploy.cmd --verify-only
```

El launcher no realiza ninguna de estas acciones:

- iniciar o configurar Docker Desktop;
- modificar Git, cambiar de rama, descargar commits o publicar imágenes;
- ejecutar `docker system prune`, `volume prune` o `network prune`;
- ejecutar `compose down`, `down -v`, `rm` o `--remove-orphans` en operación
  normal;
- borrar o recrear la base para resolver un fallo;
- reparar `flyway_schema_history` o ejecutar SQL paralelo a Flyway;
- restaurar automáticamente;
- tocar `gestudio-remote-demo` ni otros proyectos;
- resetear datos o rotar secretos.

Las operaciones destructivas quedan fuera de `deploy.cmd` y requieren una
herramienta explícita y una decisión humana. No se agregó un ZIP versionado: la
estrategia Docker construye desde backend y frontend, por lo que un checkout
limpio ya es el bundle reproducible mínimo sin duplicar el repositorio. Los
ZIPs futuros, si se requieren para distribución, deben ser artefactos de CI sin
secretos, caches, logs, backups ni estado local, acompañados por SHA-256.

## Gate de idempotencia

El gate permanente crea proyectos, puertos, secretos y volúmenes sintéticos y
aislados:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy\test-idempotency.ps1
```

Ejecuta dos despliegues idénticos, una rotación de credencial control-plane,
`--verify-only`, lock concurrente, una ruta con espacios, Docker deliberadamente
inaccesible y el upgrade histórico hasta la última V local. La
limpieza enumera contenedores, volúmenes y redes por el label exacto del proyecto
de prueba. Finalmente compara los IDs de `gestudio-remote-demo` y verifica que
ningún recurso ajeno existente haya sido eliminado.
