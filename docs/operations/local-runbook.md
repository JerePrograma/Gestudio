# Puesta en marcha y flujo de uso local

> Estado: desarrollo y evaluación interna `GO`; demo comercial, staging y producción `NO-GO`.

Este documento es el procedimiento operativo principal para levantar Gestudio, recorrer sus funciones y ejecutar sus controles técnicos.

## 1. Modalidades soportadas

| Modalidad | Uso recomendado | Persistencia |
|---|---|---|
| Demo persistente | evaluación funcional y recorridos por rol | conserva datos hasta `Reset` |
| Docker Compose completo | entorno local integrado cercano al runtime | volúmenes `postgres_data` y `receipts_data` |
| Desarrollo separado | backend y frontend en primer plano | PostgreSQL Docker persistente |
| Smoke, seed y drills | gates automatizados | descartable |

Para una primera evaluación funcional usar **Demo persistente**. Para programar y depurar usar **Desarrollo separado**. Para comprobar imágenes, red y volúmenes usar **Docker Compose completo**.

## 2. Requisitos

- Git 2.x;
- JDK 21 y `JAVA_HOME` correcto;
- Node.js 22.14.0;
- npm 10.x;
- Docker Desktop o Docker Engine activo;
- Docker Compose v2;
- PowerShell 7 o Windows PowerShell 5.1.

Verificación:

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

No continuar si Java no es 21 o Docker no muestra información del servidor.

## 3. Obtener el código

```powershell
git clone https://github.com/JerePrograma/Gestudio.git
Set-Location .\Gestudio

git switch main
git pull --ff-only origin main

git status --short --branch
git rev-parse HEAD
```

El estado debe estar limpio antes de levantar el entorno.

## 4. Preparar y validar dependencias

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\codex\setup.ps1
```

Validación completa:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\codex\validate.ps1 `
  -Scope All
```

No usar `-SkipTests` para declarar un gate aprobado.

## 5. Opción recomendada: demo persistente

### Iniciar

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\demo-local.ps1 `
  -Action Start
```

El script solicita contraseñas para:

- `demo-superadmin`;
- `demo-direccion`;
- `demo-administrador`;
- `demo-secretaria`;
- `demo-caja`.

No reutilizar contraseñas reales.

### Direcciones

| Servicio | Dirección |
|---|---|
| Frontend | `http://localhost:18081` |
| Backend | `http://localhost:18080` |
| API | `http://localhost:18080/api` |
| PostgreSQL | `localhost:15432` |
| Base | `gestudio_demo_local` |
| Liveness | `http://localhost:18080/actuator/health/liveness` |
| Readiness | `http://localhost:18080/actuator/health/readiness` |

En la demo persistente Prometheus permanece cerrado si no se configura un token explícito. Esto es intencional.

### Consultar estado

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\demo-local.ps1 `
  -Action Status
```

### Detener conservando datos

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\demo-local.ps1 `
  -Action Stop
```

### Recrear desde cero

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\demo-local.ps1 `
  -Action Reset
```

`Reset` elimina los datos de la demo. No usarlo sobre información que se quiera conservar.

## 6. Docker Compose completo

### Crear configuración local

```powershell
Copy-Item .env.local.example .env
```

`.env` no debe versionarse.

Editar como mínimo:

- `POSTGRES_PASSWORD`;
- `JWT_SECRET`;
- `APP_OBSERVABILITY_METRICS_TOKEN` si se desea consultar Prometheus;
- usuario y clave de bootstrap inicial si la base no tiene usuarios;
- puertos cuando `5432`, `8080` o `8081` estén ocupados.

Generar valores locales aleatorios:

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

No usar el mismo valor para JWT y métricas.

### Primer superadministrador

Sólo cuando la base todavía no tiene usuarios:

```text
APP_BOOTSTRAP_SUPERADMIN_ENABLED=true
APP_BOOTSTRAP_SUPERADMIN_USERNAME=admin-inicial
APP_BOOTSTRAP_SUPERADMIN_PASSWORD=<clave de 16 a 72 bytes UTF-8>
```

### Validar Compose

```powershell
docker compose --env-file .env -p gestudio config --quiet
```

### Levantar

```powershell
docker compose --env-file .env -p gestudio up -d --build
docker compose --env-file .env -p gestudio ps
```

Esperar que `db` y `backend` queden `healthy`.

### Direcciones predeterminadas

| Servicio | Dirección |
|---|---|
| Frontend | `http://localhost:8081` |
| Backend | `http://localhost:8080` |
| API | `http://localhost:8080/api` |
| PostgreSQL | `localhost:5432` |
| Liveness | `http://localhost:8080/actuator/health/liveness` |
| Readiness | `http://localhost:8080/actuator/health/readiness` |
| Prometheus | `http://localhost:8080/actuator/prometheus` |

### Desactivar bootstrap después del primer login

1. cambiar en `.env`:

```text
APP_BOOTSTRAP_SUPERADMIN_ENABLED=false
```

2. recrear backend:

```powershell
docker compose --env-file .env -p gestudio `
  up -d --no-deps --force-recreate backend
```

La bandera no debe permanecer activa.

### Detener conservando datos

```powershell
docker compose --env-file .env -p gestudio down --remove-orphans
```

### Eliminar también base y recibos

```powershell
docker compose --env-file .env -p gestudio `
  down --volumes --remove-orphans
```

Este comando es destructivo.

## 7. Desarrollo separado

### PostgreSQL

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\dev\start-db.ps1
```

### Backend, en otra terminal

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\dev\start-backend.ps1
```

### Frontend, en otra terminal

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\dev\start-frontend.ps1
```

Direcciones habituales:

- frontend Vite: `http://localhost:5173`;
- backend: `http://localhost:8080`;
- API: `http://localhost:8080/api`;
- PostgreSQL: `localhost:5432`.

Maven y Vite se detienen con `Ctrl+C`.

Contenedores:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\dev\stop.ps1
```

## 8. Comprobar salud y métricas

### Health

```powershell
$base = 'http://localhost:8080'

Invoke-RestMethod "$base/actuator/health/liveness"
Invoke-RestMethod "$base/actuator/health/readiness"
```

Resultado esperado:

```json
{"status":"UP"}
```

No deben exponerse detalles de componentes.

### Prometheus

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
- no enviar el token desde el navegador;
- no ponerlo en una URL;
- no reutilizar `JWT_SECRET`.

Runbook: [Observabilidad y diagnóstico](observability.md).

## 9. Flujo funcional recomendado

### 9.1 Iniciar sesión y confirmar permisos

Ingresar inicialmente con `SUPERADMIN` o `demo-superadmin`.

Verificar:

- menú condicionado por permisos;
- una ruta sin autenticación devuelve `401`;
- una operación sin permiso devuelve `403`;
- un conflicto real devuelve `409`;
- la respuesta incluye `X-Request-ID`.

### 9.2 Configurar la operación

Orden recomendado:

1. salones;
2. profesores;
3. disciplinas;
4. horarios;
5. métodos de pago;
6. conceptos y subconceptos;
7. usuarios y roles.

`PROFESOR` permanece inactivo y no debe asignarse como rol de acceso.

### 9.3 Crear tarifas efectivas

Después de crear una disciplina, abrir **Tarifas** y registrar:

- `vigenteDesde`;
- valor mensual;
- matrícula;
- clase suelta;
- clase de prueba cuando corresponda;
- motivo.

No utilizar `valorCuota` o `matricula` legacy como fuente operativa.

### 9.4 Crear alumno

Registrar:

- nombre;
- apellido;
- documento;
- contacto;
- fecha de incorporación;
- sólo datos sintéticos durante pruebas o demo.

### 9.5 Crear inscripción

1. abrir Inscripciones;
2. seleccionar alumno;
3. seleccionar disciplina;
4. informar fecha;
5. confirmar.

La operación crea obligaciones iniciales dentro de una transacción. Si falta una tarifa efectiva, no deben quedar inscripción, mensualidad, matrícula, cargo ni snapshot parciales.

### 9.6 Configurar condición económica

Sólo para excepciones comerciales:

- vigencia;
- costo particular opcional;
- porcentaje;
- importe fijo.

No editar bonificación o costo particular mediante campos legacy de inscripción.

### 9.7 Revisar mensualidad y matrícula

- mensualidad: tarifa efectiva al primer día del mes;
- matrícula: tarifa efectiva al 1 de enero;
- condición económica: opcional y resuelta por fecha;
- matrícula multidisciplina: mayor importe final;
- recargo: cargo tardío separado.

Cada cargo nuevo debe tener snapshot en `cargo_liquidaciones`.

### 9.8 Registrar pago y recibo

1. abrir cargos del alumno;
2. seleccionar obligación;
3. registrar pago y método;
4. verificar aplicaciones;
5. generar o consultar recibo;
6. comprobar movimiento en caja.

Un reintento con la misma idempotency key no debe duplicar pago, aplicación, recibo ni movimiento.

### 9.9 Caja y egresos

- consultar resumen por fecha;
- registrar egreso sólo con rol autorizado;
- anular o revertir;
- verificar movimiento compensatorio;
- no borrar historia.

### 9.10 Stock

1. crear producto;
2. registrar entrada o ajuste;
3. registrar venta;
4. verificar movimiento y caja;
5. revertir;
6. comprobar que el stock nunca sea negativo.

### 9.11 Asistencia

- seleccionar disciplina, horario o clase;
- buscar alumno por referencia humana;
- marcar asistencia;
- confirmar guardado;
- revisar estado vacío, error y navegación por teclado.

## 10. Recorridos por rol

| Rol | Flujo principal | Denegaciones esperadas |
|---|---|---|
| SUPERADMIN | configuración, seguridad y operación completa | ninguna dentro del inventario habilitado |
| DIRECCION | gestión y reportes | administración de roles |
| ADMINISTRADOR | operación amplia | administración de roles |
| SECRETARIA | alumnos, inscripciones y asistencia | egresos y seguridad |
| CAJA | cargos, pagos, recibos, caja y stock permitido | gestión académica restringida |

Los cinco recorridos humanos siguen siendo una tarea pendiente de GATE-2. La automatización no los reemplaza.

## 11. Integración Jere Platform V7

Está deshabilitada por defecto. No habilitarla para uso local normal.

Requiere:

```text
APP_JERE_PLATFORM_STUDENT_EXPORT_ENABLED=true
APP_JERE_PLATFORM_STUDENT_EXPORT_ORGANIZATION_ID=<identificador estable>
APP_JERE_PLATFORM_STUDENT_EXPORT_TENANT_ID=<UUID externo>
APP_JERE_PLATFORM_STUDENT_EXPORT_CURRENT_SECRET=<secreto independiente de 32 bytes o más>
```

Sólo exporta ID, nombre visible y activo. No existe push automático. La operación multipágina end-to-end continúa bloqueada por `JerePrograma/jere-platform#59`.

## 12. Backup

Antes de migraciones, despliegues o rollback:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\ops\backup-postgres.ps1 `
  -EnvFile .\.env `
  -ProjectName gestudio `
  -OutputDirectory D:\Backups\Gestudio `
  -StopBackend
```

Runbook: [Backup y restore](backup-restore.md).

## 13. Restore

Restaurar primero sobre una base alternativa. No sobrescribir el origen sin validación previa y confirmaciones explícitas.

Ejecutar el drill:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\ops\verify-backup-restore.ps1
```

## 14. Rollback backend

La imagen objetivo debe declarar exactamente todas las migraciones aplicadas. Una base V7 rechaza una imagen V6.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\ops\rollback-backend.ps1 `
  -TargetBackendImage '<imagen-anterior-aprobada>' `
  -ExpectedCurrentImage '<imagen-actual>' `
  -EnvFile .\.env `
  -ProjectName gestudio `
  -BackupOutputDirectory D:\Backups\Gestudio\Rollback `
  -ConfirmRollback
```

Nunca ejecutar down migrations para adaptar la base a una imagen anterior.

Runbook: [Rollback compatible con Flyway](rollback.md).

## 15. Gates técnicos

Ejecutar secuencialmente:

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

## 16. Diagnóstico rápido

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
- Docker CLI sin Engine: iniciar Docker Desktop/Engine;
- puerto ocupado: cambiarlo en `.env`;
- Flyway falla: no editar una migración aplicada;
- Hibernate no valida: no cambiar `ddl-auto` a `update`;
- login inicial no existe: revisar bootstrap sólo en una base sin usuarios;
- backend falla tras crear el superadmin: apagar bootstrap;
- tarifa ausente: crear tarifa histórica, no completar campos legacy;
- readiness DOWN: revisar PostgreSQL, disco y Flyway;
- Prometheus `401`: revisar cabecera y token exactos;
- restore rechazado: usar base alternativa y confirmaciones explícitas;
- rollback rechazado: revisar metadata Flyway de la imagen objetivo.

## 17. Límites

Un entorno local verde no autoriza demo comercial, staging ni producción.

Para staging todavía faltan:

- ambiente y dominio;
- TLS, CORS y cookies reales;
- secret manager y rotación;
- registry por digest, firma y promoción;
- destino cifrado y retención de backups;
- Prometheus o equivalente, almacenamiento, dashboard y alertas;
- responsables y escalamiento;
- recorridos humanos de GATE-2.

Producción permanece en `NO-GO` hasta autorización independiente.
