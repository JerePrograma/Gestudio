# Puesta en marcha y flujo de uso local

> Estado: desarrollo y evaluación interna `GO`; demo comercial, staging y producción `NO-GO`.

Este es el procedimiento operativo principal para instalar, levantar, usar, validar y diagnosticar Gestudio.

## 1. Modalidades

| Modalidad | Uso | Persistencia |
|---|---|---|
| Demo persistente | evaluación funcional y recorridos por rol | conserva datos hasta `Reset` |
| Docker Compose completo | entorno local integrado cercano al runtime | volúmenes PostgreSQL y recibos |
| Desarrollo separado | programación y depuración | PostgreSQL Docker persistente |
| Smoke, seed y drills | validación automatizada | descartable |

Recomendación:

- primera evaluación: **Demo persistente**;
- desarrollo: **Desarrollo separado**;
- comprobación de imágenes/red/volúmenes: **Docker Compose completo**.

## 2. Requisitos

- Git 2.x;
- JDK 21 y `JAVA_HOME` correcto;
- Node.js 22 LTS;
- npm 10.x;
- Docker Desktop o Docker Engine activo;
- Docker Compose v2;
- PowerShell 7 o Windows PowerShell 5.1.

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

No continuar si Java no es 21 o Docker no informa el servidor.

## 3. Obtener y validar el código

```powershell
git clone https://github.com/JerePrograma/Gestudio.git
Set-Location .\Gestudio

git switch main
git pull --ff-only origin main

git status --short --branch
git rev-parse HEAD

powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\codex\setup.ps1

powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\codex\validate.ps1 `
  -Scope All
```

El árbol debe estar limpio. No usar `-SkipTests` para declarar un gate aprobado.

# 4. Opción recomendada: demo persistente

## Iniciar

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\demo-local.ps1 `
  -Action Start
```

Solicita claves para:

- `demo-superadmin`;
- `demo-direccion`;
- `demo-administrador`;
- `demo-secretaria`;
- `demo-caja`.

No reutilizar contraseñas reales.

## Direcciones

| Servicio | Dirección |
|---|---|
| Frontend | `http://localhost:18081` |
| Backend | `http://localhost:18080` |
| API | `http://localhost:18080/api` |
| PostgreSQL | `localhost:15432` |
| Base | `gestudio_demo_local` |
| Liveness | `http://localhost:18080/actuator/health/liveness` |
| Readiness | `http://localhost:18080/actuator/health/readiness` |

Prometheus permanece cerrado si no se configura un token. Es intencional.

## Estado, detención y reset

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\demo-local.ps1 `
  -Action Status

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\demo-local.ps1 `
  -Action Stop
```

`Stop` conserva datos.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\demo-local.ps1 `
  -Action Reset
```

`Reset` elimina los datos de la demo. Invoca Compose con el nombre fijo
`gestudio-demo-local`, por lo que sólo desciende ese proyecto y sus volúmenes;
no usar limpiezas Docker globales.

### Contrato de vigencia

`Start` reconstruye imágenes y fuerza la recreación de backend y frontend sin
borrar el volumen PostgreSQL. `Status` no acepta como disponible un contenedor
healthy pero viejo: compara image ID, revisión Git, hash de
`docker-compose.yml`, metadata Flyway, health, respuesta frontend e integridad
del seed. La cadena esperada se deriva de las migraciones locales contiguas
(V1-V7 en este corte), no de un número duplicado en el script.

Si alguna condición falla, `Status` imprime `Demo disponible: NO`, detalla el
motivo y termina con exit code `1`. La disponibilidad afirmativa y exit `0` son
requisitos del gate.

La demo conserva un `demo_anchor_date` estable para datos históricos y usa un
`demo_business_date` diario en `America/Argentina/Buenos_Aires` para el alumno
de cumpleaños. Sólo se notifican personas activas y el día exacto; 29/2 se
observa el 28/2 en un año no bisiesto.

# 5. Docker Compose completo

## Crear `.env`

```powershell
Copy-Item .env.local.example .env
```

`.env` no se versiona.

Editar como mínimo:

- `POSTGRES_PASSWORD`;
- `JWT_SECRET`;
- `JWT_ISSUER`, `JWT_ACCESS_TOKEN_TTL` y `JWT_REFRESH_TOKEN_TTL`;
- `APP_OBSERVABILITY_METRICS_TOKEN` para consultar Prometheus;
- bootstrap inicial si la base no tiene usuarios;
- puertos si `5432`, `8080` o `8081` están ocupados.

Generar secretos locales independientes:

```powershell
function New-HexSecret([int]$Bytes) {
  [Convert]::ToHexString(
    [Security.Cryptography.RandomNumberGenerator]::GetBytes($Bytes)
  ).ToLowerInvariant()
}

$jwtSecret = New-HexSecret 64
$metricsToken = New-HexSecret 48

$jwtSecret
$metricsToken
```

No reutilizar el secreto JWT como token de métricas.
En producción los TTL usan duraciones ISO-8601, por ejemplo `PT15M` y `P7D`, y
la cookie refresh se configura con `Secure=true`.

## Primer superadministrador

Sólo en una base sin usuarios:

```text
APP_BOOTSTRAP_SUPERADMIN_ENABLED=true
APP_BOOTSTRAP_SUPERADMIN_USERNAME=admin-inicial
APP_BOOTSTRAP_SUPERADMIN_PASSWORD=<clave de 16 a 72 bytes UTF-8>
```

## Validar y levantar

```powershell
docker compose --env-file .env -p gestudio config --quiet
docker compose --env-file .env -p gestudio up -d --build
docker compose --env-file .env -p gestudio ps
```

Esperar `db` y `backend` en estado `healthy`.

| Servicio | Dirección |
|---|---|
| Frontend | `http://localhost:8081` |
| Backend | `http://localhost:8080` |
| API | `http://localhost:8080/api` |
| PostgreSQL | `localhost:5432` |
| Liveness | `http://localhost:8080/actuator/health/liveness` |
| Readiness | `http://localhost:8080/actuator/health/readiness` |
| Prometheus | `http://localhost:8080/actuator/prometheus` |

## Apagar bootstrap

Después del primer login:

```text
APP_BOOTSTRAP_SUPERADMIN_ENABLED=false
```

```powershell
docker compose --env-file .env -p gestudio `
  up -d --no-deps --force-recreate backend
```

La bandera no debe permanecer activa.

## Detener

Conservar datos:

```powershell
docker compose --env-file .env -p gestudio down --remove-orphans
```

Eliminar también base y recibos:

```powershell
docker compose --env-file .env -p gestudio `
  down --volumes --remove-orphans
```

El segundo comando es destructivo.

# 6. Desarrollo separado

Terminal 1 — PostgreSQL:

```powershell
$backupRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'GestudioBackups'
New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\dev\start-db.ps1
```

Terminal 2 — Backend:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\dev\start-backend.ps1
```

Terminal 3 — Frontend:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\dev\start-frontend.ps1
```

Direcciones:

- Vite: `http://localhost:5173`;
- Backend: `http://localhost:8080`;
- API: `http://localhost:8080/api`;
- PostgreSQL: `localhost:5432`.

Maven y Vite se detienen con `Ctrl+C`.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\dev\stop.ps1
```

# 7. Health y métricas

## Health

```powershell
$base = 'http://localhost:8080'

Invoke-RestMethod "$base/actuator/health/liveness"
Invoke-RestMethod "$base/actuator/health/readiness"
```

Esperado:

```json
{"status":"UP"}
```

No deben exponerse detalles internos.

## Prometheus

```powershell
$headers = @{
  'X-Gestudio-Metrics-Token' = $env:APP_OBSERVABILITY_METRICS_TOKEN
}

Invoke-WebRequest `
  'http://localhost:8080/actuator/prometheus' `
  -Headers $headers
```

Contrato:

- sin token o token incorrecto: `401`;
- token exacto: `200`;
- dos o más valores de cabecera: `401`, aunque uno sea correcto;
- no enviarlo desde el navegador;
- no incluirlo en URLs;
- no reutilizar `JWT_SECRET`.

# 8. Flujo funcional recomendado

## 8.1 Login y permisos

Ingresar como `SUPERADMIN` o `demo-superadmin`.

Verificar:

- menú según permisos;
- sin sesión: `401`;
- sin permiso: `403`;
- conflicto real: `409`;
- cabecera `X-Request-ID` presente.

## 8.2 Configuración inicial

Orden recomendado:

1. salones;
2. profesores;
3. disciplinas;
4. horarios;
5. métodos de pago;
6. conceptos y subconceptos;
7. usuarios y roles.

`PROFESOR` permanece inactivo y no asignable como rol de acceso.

## 8.3 Tarifas efectivas

En cada disciplina registrar:

- `vigenteDesde`;
- valor mensual;
- matrícula;
- clase suelta;
- clase de prueba cuando corresponda;
- motivo.

No usar `valorCuota` o `matricula` legacy como fuente operativa.

## 8.4 Alumno

Registrar:

- nombre;
- apellido;
- documento;
- contacto;
- fecha de incorporación;
- sólo datos sintéticos durante demo o pruebas.

## 8.5 Inscripción

1. abrir Inscripciones;
2. seleccionar alumno;
3. seleccionar disciplina;
4. informar fecha;
5. confirmar.

Si falta una tarifa efectiva, no deben quedar inscripción, mensualidad, matrícula, cargo ni snapshot parciales.

## 8.6 Condición económica

Sólo para una excepción comercial:

- vigencia;
- costo particular opcional;
- porcentaje;
- importe fijo.

No editar bonificaciones o costos mediante campos legacy.

## 8.7 Mensualidad y matrícula

- mensualidad: tarifa efectiva al primer día del mes;
- matrícula: tarifa efectiva al 1 de enero;
- condición económica: opcional y resuelta por fecha;
- matrícula multidisciplina: mayor importe final;
- recargo: cargo tardío separado;
- cada cargo: snapshot en `cargo_liquidaciones`.

## 8.8 Pago y recibo

1. abrir cargos del alumno;
2. seleccionar obligación;
3. registrar pago y método;
4. verificar aplicaciones;
5. generar o consultar recibo;
6. comprobar movimiento de caja.

La misma idempotency key no debe duplicar pago, aplicación, recibo ni movimiento.

## 8.9 Caja y egresos

- consultar resumen por fecha;
- registrar egreso sólo con rol autorizado;
- anular o revertir;
- comprobar movimiento compensatorio;
- no borrar historia.

## 8.10 Stock

1. crear producto;
2. registrar entrada o ajuste;
3. registrar venta;
4. verificar movimiento y caja;
5. revertir;
6. confirmar que el stock nunca sea negativo.

## 8.11 Asistencia

- seleccionar disciplina, horario o clase;
- buscar alumno por referencia humana;
- marcar asistencia;
- confirmar guardado;
- revisar estado vacío, error y teclado.

# 9. Recorridos por rol

| Rol | Flujo | Denegaciones esperadas |
|---|---|---|
| SUPERADMIN | configuración, seguridad y operación completa | ninguna dentro del inventario |
| DIRECCION | gestión y reportes | administración de roles |
| ADMINISTRADOR | operación amplia | administración de roles |
| SECRETARIA | alumnos, inscripciones y asistencia | egresos y seguridad |
| CAJA | cargos, pagos, recibos, caja y stock permitido | gestión académica restringida |

La matriz detallada y la evidencia real del 22 de julio están en
`docs/testing/human-role-walkthrough.md`. El recorrido cubrió los cinco roles,
escritorio/móvil, teclado, foco, datos/vacío, permisos, refresh y logout.

# 10. Integración Jere Platform

Gestudio V7 incluye un emisor `GESTUDIO_STUDENT`:

- ID;
- nombre visible;
- activo;
- snapshots/páginas firmadas;
- tenant explícito;
- feature apagada por defecto;
- sin push automático.

Configuración:

```text
APP_JERE_PLATFORM_STUDENT_EXPORT_ENABLED=true
APP_JERE_PLATFORM_STUDENT_EXPORT_ORGANIZATION_ID=<identificador estable>
APP_JERE_PLATFORM_STUDENT_EXPORT_TENANT_ID=<UUID externo>
APP_JERE_PLATFORM_STUDENT_EXPORT_CURRENT_SECRET=<secreto independiente de 32 bytes o más>
```

No habilitarla para uso local normal.

Estado verificado:

- Jere Platform PR `#60` incorporó el receptor multipágina;
- issue técnico `#59` está cerrado;
- el coordinador `#51` continúa abierto por Scalaris y requisitos productivos;
- el transporte desplegado Gestudio → Jere Platform no fue ejecutado ni autorizado.

El bloqueo técnico `#59` no está pendiente. La ausencia de transporte
desplegado es una condición operativa distinta y el issue coordinador `#51`
permanece abierto.

# 11. Backup

Antes de migraciones, despliegues o rollback:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\ops\backup-postgres.ps1 `
  -EnvFile .\.env `
  -ProjectName gestudio `
  -OutputDirectory $backupRoot `
  -StopBackend
```

Runbook: `docs/operations/backup-restore.md`.

# 12. Restore

Restaurar primero sobre una base alternativa. No sobrescribir origen sin validación y confirmaciones explícitas.

```powershell
$rollbackRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'GestudioBackups\Rollback'
New-Item -ItemType Directory -Force -Path $rollbackRoot | Out-Null
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\ops\verify-backup-restore.ps1
```

El restore se revalidó el 22 de julio en PowerShell 7 y Windows PowerShell 5.1:
12/12 etapas en ambos shells, incluida la matriz adversarial y cleanup aislado.
El resultado local no autoriza por sí solo una restauración productiva; esa
operación requiere ventana, backup aprobado y responsables identificados.

# 13. Rollback backend

Una imagen objetivo debe contener exactamente todas las migraciones aplicadas. Una base V7 rechaza una imagen V6.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\ops\rollback-backend.ps1 `
  -TargetBackendImage '<imagen-anterior-aprobada>' `
  -ExpectedCurrentImage '<imagen-actual>' `
  -EnvFile .\.env `
  -ProjectName gestudio `
  -BackupOutputDirectory $rollbackRoot `
  -ConfirmRollback
```

Nunca ejecutar down migrations.

Contratos health:

- actual: `actuator-readiness-v1`;
- pre-Actuator: `legacy-api-401-v1`.

Runbook: `docs/operations/rollback.md`.

# 14. Gates técnicos

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

Los drills usan stacks descartables y no deben compartir datos reales.
El validador demo muestra cada etapa y su duración, impone un timeout global
configurable (`-TimeoutMinutes`), imprime siempre el resumen y propaga un exit
code no cero. También comprueba por HTTP el cumpleaños del día. El uso de
`-SkipBackendBuild` sólo es seguro cuando el JAR no es anterior a sus entradas.

# 15. Diagnóstico

```powershell
docker compose --env-file .env -p gestudio ps
docker compose --env-file .env -p gestudio logs --tail 200 db backend frontend

$backend = docker compose --env-file .env -p gestudio ps -q backend
docker inspect --format '{{json .State.Health}}' $backend

docker volume ls --filter label=com.docker.compose.project=gestudio
docker network ls --filter label=com.docker.compose.project=gestudio
```

Problemas frecuentes:

- Java distinto de 21: corregir `JAVA_HOME`;
- Docker sin Engine: iniciar Docker Desktop/Engine;
- puerto ocupado: cambiar `.env`;
- Flyway falla: no editar una migración aplicada;
- `Status` falla con imagen vieja: ejecutar `Start`; no borrar el volumen;
- `Status` falla por revisión/Compose/Flyway: reconstruir desde el checkout correcto;
- Hibernate no valida: no usar `ddl-auto=update`;
- login inicial ausente: revisar bootstrap sólo en base sin usuarios;
- backend falla tras bootstrap: apagar la bandera;
- tarifa ausente: crear tarifa histórica;
- readiness DOWN: revisar PostgreSQL, disco y Flyway;
- Prometheus `401`: revisar cabecera y token exactos;
- Prometheus con cabecera repetida: enviar exactamente un valor;
- restore rechazado: usar base alternativa;
- rollback rechazado: revisar metadata Flyway y health de la imagen.

# 16. Límites

Un entorno local verde no autoriza demo comercial, staging ni producción.

Para staging faltan:

- ambiente y dominio;
- TLS, CORS y cookies reales;
- secret manager y rotación;
- registry por digest, firma y promoción;
- destino cifrado y retención de backups;
- Prometheus o equivalente, almacenamiento, dashboard y alertas;
- responsables y escalamiento;
- recorridos humanos GATE-2;
- smoke desplegado Gestudio → Jere Platform.

También siguen abiertos rate limiting/fuerza bruta, correo real, revisión de
IDs técnicos remanentes, accesibilidad, imágenes no-root y controles de supply
chain/CI de seguridad. La evidencia histórica de rollback u observabilidad no
se debe presentar como una ejecución nueva de este ciclo.

Producción permanece en `NO-GO` hasta autorización independiente.
