# Puesta en marcha y flujo de uso local

## Modalidades soportadas

| Modalidad | Uso | Persistencia |
|---|---|---|
| Demo persistente | evaluación funcional y recorridos por rol | conserva datos hasta `Reset` |
| Docker Compose completo | uso local integrado y desarrollo cercano al runtime | volúmenes `postgres_data` y `receipts_data` |
| Desarrollo separado | backend y frontend en primer plano, PostgreSQL en Docker | base Docker persistente |
| Smoke/seed/drills | gates automatizados | descartable |

Para una primera evaluación funcional conviene usar **Demo persistente**. Para desarrollar, usar **Desarrollo separado** o **Docker Compose completo**.

## Requisitos

- Git 2.x;
- JDK 21 y `JAVA_HOME` correcto;
- Node.js 22.14.0 y npm 10.x;
- Docker Desktop con Engine activo;
- Docker Compose v2;
- PowerShell 7 o Windows PowerShell 5.1.

Verificación rápida:

```powershell
git --version
java -version
node --version
npm --version
docker version
docker compose version
$PSVersionTable.PSVersion
```

## Obtener y validar el código

```powershell
git clone https://github.com/JerePrograma/Gestudio.git
Set-Location .\Gestudio
git switch main
git pull --ff-only origin main
git status --short --branch
git rev-parse HEAD
```

Preparar dependencias:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\codex\setup.ps1
```

Validación completa antes de usar el entorno:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\codex\validate.ps1 `
  -Scope All
```

## Opción recomendada: demo persistente

Iniciar:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\demo-local.ps1 `
  -Action Start
```

El script solicita cinco contraseñas y crea:

- `demo-superadmin`;
- `demo-direccion`;
- `demo-administrador`;
- `demo-secretaria`;
- `demo-caja`.

Direcciones:

- frontend: `http://localhost:18081`;
- backend: `http://localhost:18080`;
- API: `http://localhost:18080/api`;
- PostgreSQL: `localhost:15432`, base `gestudio_demo_local`.

Consultar estado:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\demo-local.ps1 `
  -Action Status
```

Detener sin borrar datos:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\demo-local.ps1 `
  -Action Stop
```

Recrear desde cero y volver a solicitar claves:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\demo-local.ps1 `
  -Action Reset
```

## Docker Compose completo

Crear configuración local no versionada:

```powershell
Copy-Item .env.local.example .env
```

Editar `.env` y reemplazar, como mínimo:

- `POSTGRES_PASSWORD`;
- `JWT_SECRET`;
- usuario y clave de bootstrap inicial si la base no tiene usuarios;
- puertos si `5432`, `8080` o `8081` están ocupados.

Primer arranque con superadministrador:

```text
APP_BOOTSTRAP_SUPERADMIN_ENABLED=true
APP_BOOTSTRAP_SUPERADMIN_USERNAME=admin-inicial
APP_BOOTSTRAP_SUPERADMIN_PASSWORD=<clave de 16 a 72 bytes UTF-8>
```

Levantar:

```powershell
docker compose --env-file .env -p gestudio up -d --build
docker compose --env-file .env -p gestudio ps
```

URLs predeterminadas:

- frontend: `http://localhost:8081`;
- backend: `http://localhost:8080`;
- API: `http://localhost:8080/api`;
- PostgreSQL: `localhost:5432`.

Después de confirmar el primer login:

1. cambiar `APP_BOOTSTRAP_SUPERADMIN_ENABLED=false` en `.env`;
2. recrear el backend:

```powershell
docker compose --env-file .env -p gestudio up -d --no-deps --force-recreate backend
```

Mantener la bandera activa provoca un fallo cerrado en reinicios posteriores.

Ver logs:

```powershell
docker compose --env-file .env -p gestudio logs -f --tail 150 backend frontend db
```

Detener conservando datos:

```powershell
docker compose --env-file .env -p gestudio down --remove-orphans
```

Eliminar también datos locales, sólo si está decidido:

```powershell
docker compose --env-file .env -p gestudio down --volumes --remove-orphans
```

## Desarrollo separado

Base PostgreSQL:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\dev\start-db.ps1
```

En otra terminal, backend:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\dev\start-backend.ps1
```

En otra terminal, frontend:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\dev\start-frontend.ps1
```

El frontend Vite queda normalmente en `http://localhost:5173` y el backend en `http://localhost:8080`.

Detener los contenedores conservando volúmenes:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\dev\stop.ps1
```

Maven y Vite se detienen con `Ctrl+C` en sus terminales.

## Flujo funcional recomendado

### 1. Iniciar sesión y confirmar el rol

Usar inicialmente `SUPERADMIN` o el usuario demo equivalente. Verificar que el menú no muestre funciones no autorizadas y que una URL prohibida devuelva 403.

### 2. Configurar la operación

Orden recomendado:

1. salones;
2. profesores;
3. disciplinas;
4. horarios;
5. métodos de pago y conceptos;
6. usuarios y roles, sólo desde un actor autorizado.

`PROFESOR` permanece inactivo y no asignable como rol de acceso.

### 3. Crear tarifas efectivas

Después de crear una disciplina, abrir **Tarifas** y registrar:

- `vigenteDesde`;
- valor mensual;
- matrícula;
- clase suelta y de prueba cuando corresponda;
- motivo de cambio.

No usar `valorCuota` o `matricula` legacy como fuente operativa. Una inscripción no puede liquidarse si falta tarifa para su fecha efectiva.

### 4. Crear alumno e inscripción

1. crear el alumno;
2. abrir Inscripciones;
3. elegir alumno, disciplina y fecha;
4. confirmar.

La transacción crea la inscripción y sus obligaciones iniciales. Si falta tarifa, revierte todo el agregado; no quedan cargos parciales.

### 5. Revisar mensualidad y matrícula

- mensualidad: tarifa efectiva al primer día del mes;
- matrícula: tarifa efectiva al 1 de enero;
- condición económica: opcional y vigente por fecha;
- matrícula multidisciplina: toma el mayor importe final;
- recargo: regla tardía separada, no parte del cargo inicial.

Cada cargo nuevo debe tener su snapshot en `cargo_liquidaciones`.

### 6. Registrar cobros

1. abrir cargos del alumno;
2. seleccionar la obligación;
3. registrar pago y método;
4. verificar aplicaciones del pago;
5. generar o consultar recibo;
6. comprobar el movimiento en caja.

Los reintentos con la misma idempotency key no deben duplicar pagos, aplicaciones ni recibos.

### 7. Operar caja y egresos

- revisar resumen por fecha;
- registrar egresos sólo con un rol autorizado;
- probar anulación o reversión;
- verificar que el ledger compense, sin borrar historia.

### 8. Operar stock

1. crear producto;
2. registrar entrada o ajuste;
3. registrar venta;
4. verificar movimiento y caja;
5. probar reversión;
6. confirmar que el stock nunca sea negativo.

### 9. Registrar asistencia

- seleccionar disciplina, horario o clase;
- buscar al alumno por referencia humana;
- marcar asistencia;
- revisar estados vacíos, errores y navegación por teclado.

### 10. Recorrer roles

| Rol | Foco de prueba |
|---|---|
| SUPERADMIN | configuración, usuarios, roles y operación completa |
| DIRECCION | gestión y reportes, sin administración de roles |
| ADMINISTRADOR | operación amplia, sin administración de roles |
| SECRETARIA | alumnos, inscripciones y asistencia; sin egresos ni seguridad |
| CAJA | cargos, pagos, recibos, caja y stock permitido; sin gestión académica restringida |

## Integración Jere Platform V7

Está deshabilitada por defecto. No la habilites para el uso normal local.

Requiere explícitamente:

```text
APP_JERE_PLATFORM_STUDENT_EXPORT_ENABLED=true
APP_JERE_PLATFORM_STUDENT_EXPORT_ORGANIZATION_ID=<identificador estable>
APP_JERE_PLATFORM_STUDENT_EXPORT_TENANT_ID=<UUID externo>
APP_JERE_PLATFORM_STUDENT_EXPORT_CURRENT_SECRET=<secreto independiente de 32 bytes o más>
```

Sólo exporta ID, nombre de visualización y estado activo. No existe push automático. La operación end-to-end multipágina continúa bloqueada por `JerePrograma/jere-platform#59`.

## Backup antes de cambios relevantes

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\ops\backup-postgres.ps1 `
  -EnvFile .\.env `
  -ProjectName gestudio `
  -OutputDirectory D:\Backups\Gestudio `
  -StopBackend
```

Consultar el procedimiento completo en [Backup y restore](backup-restore.md).

## Gates antes de considerar una demo comercial

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope All
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\smoke-local.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-demo-seed.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\ops\verify-backup-restore.ps1
```

Además deben completarse recorridos humanos por rol, GATE-2, observabilidad y rollback operativo. Un entorno local verde no autoriza staging ni producción.

## Diagnóstico rápido

```powershell
docker compose --env-file .env -p gestudio ps
docker compose --env-file .env -p gestudio logs --tail 200 db backend frontend
docker volume ls --filter label=com.docker.compose.project=gestudio
```

Problemas frecuentes:

- Java distinto de 21: corregir `JAVA_HOME`;
- Docker CLI sin Engine: iniciar Docker Desktop;
- puerto ocupado: cambiarlo en `.env`;
- Flyway falla: no editar una migración aplicada;
- Hibernate no valida: no cambiar `ddl-auto` a `update`;
- login inicial no existe: revisar bootstrap sólo en una base sin usuarios;
- backend falla tras crear el superadmin: apagar la bandera de bootstrap;
- tarifa ausente: crear una tarifa histórica, no rellenar campos legacy;
- restore rechazado: usar una base destino alternativa y las confirmaciones explícitas.
