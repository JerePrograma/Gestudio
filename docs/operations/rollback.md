# Rollback de aplicación compatible con Flyway y health

## Principio

Gestudio usa migraciones Flyway forward-only. Un rollback de aplicación no puede borrar migraciones ni iniciar una imagen que desconozca versiones ya aplicadas.

Si la base registra V7, la imagen objetivo debe contener V1-V7 aunque su código funcional corresponda a una versión anterior. Una imagen que declare V6 se rechaza antes de recrear el backend.

El rollback también debe conocer cómo comprobar que cada artefacto quedó operativo. Las imágenes anteriores a Actuator no publican readiness, por lo que no pueden validarse con el mismo endpoint que una imagen actual.

## Primera respuesta ante un incidente V7

El emisor Jere Platform está deshabilitado por defecto. Ante un problema localizado en esa función:

1. mantener `APP_JERE_PLATFORM_STUDENT_EXPORT_ENABLED=false`;
2. reiniciar el backend sólo si la configuración cambió;
3. conservar V7 y sus tablas;
4. investigar antes de cambiar el artefacto completo.

La feature flag es una mitigación, no una down migration.

## Metadata obligatoria de imagen

El Dockerfile genera:

```text
/app/build-metadata/flyway-latest
/app/build-metadata/git-revision
/app/build-metadata/health-contract
```

`flyway-latest` se deriva de los archivos `V*__*.sql` incluidos en la imagen.

`health-contract` admite:

| Contrato | Uso | Sonda |
|---|---|---|
| `actuator-readiness-v1` | imágenes con Actuator | `/actuator/health/readiness` debe responder `UP` |
| `legacy-api-401-v1` | imágenes anteriores a Actuator | `/api/alumnos` debe responder HTTP `401` sin credencial |

La sonda legacy no es un simple puerto. Exige que la aplicación haya terminado de iniciar y que su capa HTTP/seguridad responda con el contrato esperado. Se usa sólo para permitir una retirada temporal a un artefacto anterior aprobado.

Imágenes creadas antes de incorporar `health-contract`, pero que sí tienen metadata Flyway válida, se clasifican con advertencia como `legacy-api-401-v1`.

Regla de esquema:

```text
Flyway máximo de imagen objetivo == Flyway máximo exitoso de base
```

Una imagen sin metadata Flyway, con valor inválido, anterior o posterior se rechaza. Un contrato de health desconocido también se rechaza.

## Preparar un artefacto rollback

Debe construirse y publicarse antes de una ventana operativa. Si se revierte código a un commit anterior a V7 o Actuator:

1. crear checkout separado del commit funcional anterior;
2. incorporar todas las migraciones aplicadas después de ese commit;
3. construir con el Dockerfile actual;
4. dejar que el build derive el contrato de health según las dependencias presentes;
5. ejecutar pruebas de esa fuente compatible;
6. etiquetar/publicar de forma inmutable;
7. registrar commit funcional, migraciones, contrato health, digest y fecha.

No usar `latest` como único identificador.

Ejemplo conceptual:

```powershell
git worktree add --detach .\.rollback-source <commit-anterior>
Copy-Item .\backend\src\main\resources\db\migration\V7__jere_platform_student_source_exports.sql `
  .\.rollback-source\backend\src\main\resources\db\migration\
Copy-Item .\backend\Dockerfile .\.rollback-source\backend\Dockerfile -Force

docker build `
  --build-arg VCS_REF=<commit-anterior>-compatible-v7 `
  -t registry.example/gestudio-backend:rollback-<id> `
  .\.rollback-source\backend
```

Comprobar metadata:

```powershell
docker run --rm --entrypoint cat <imagen> /app/build-metadata/flyway-latest
docker run --rm --entrypoint cat <imagen> /app/build-metadata/health-contract
```

## Ejecutar rollback local o controlado

Requisitos:

- base y backend ya creados por Compose;
- imagen objetivo presente o descargada explícitamente;
- directorio seguro para backup;
- ventana de mantenimiento;
- autorización operativa.

```powershell
$rollbackRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'GestudioBackups\Rollback'
New-Item -ItemType Directory -Force -Path $rollbackRoot | Out-Null
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\ops\rollback-backend.ps1 `
  -TargetBackendImage registry.example/gestudio-backend:rollback-20260720 `
  -ExpectedCurrentImage registry.example/gestudio-backend:current-20260720 `
  -EnvFile .\.env `
  -ProjectName gestudio `
  -BackupOutputDirectory $rollbackRoot `
  -ConfirmRollback
```

El script:

1. verifica Docker y Compose;
2. identifica imagen actual;
3. impide carreras mediante `ExpectedCurrentImage`;
4. lee Flyway de la base;
5. lee Flyway de la imagen objetivo;
6. rechaza cualquier diferencia;
7. obtiene contratos de health actual y objetivo;
8. crea backup consistente previo;
9. recrea sólo backend con el contrato objetivo;
10. espera health;
11. confirma imagen y contrato exactos;
12. si falla, recupera la imagen anterior con su propio contrato.

El JSON final incluye:

- imagen anterior y objetivo;
- contrato health anterior y objetivo;
- Flyway;
- directorio de backup.

## `-SkipBackup`

Existe sólo para drills o retorno inmediato a un artefacto ya respaldado:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\ops\rollback-backend.ps1 `
  -TargetBackendImage <imagen> `
  -EnvFile .\.env `
  -ProjectName gestudio `
  -SkipBackup `
  -ConfirmRollback
```

No usar en un cambio real sin copia verificada y decisión explícita.

## Verificación posterior

```powershell
docker compose --env-file .env -p gestudio ps
docker compose --env-file .env -p gestudio logs --tail 200 backend

$backend = docker compose --env-file .env -p gestudio ps -q backend
docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' $backend | Select-String BACKEND_HEALTHCHECK_MODE

docker compose --env-file .env -p gestudio exec db sh -ec `
  'PGPASSWORD="$POSTGRES_PASSWORD" psql --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" --command="SELECT version, success FROM flyway_schema_history ORDER BY installed_rank"'
```

Verificar además:

- login;
- alumno previo;
- cargos/pagos;
- recibo;
- caja/stock;
- ausencia de nuevas excepciones;
- health estable;
- si el contrato es legacy, registrar explícitamente que readiness Actuator no está disponible durante la mitigación.

## Retorno al artefacto actual

Se ejecuta con el mismo script. Al volver, la imagen actual recupera `actuator-readiness-v1` automáticamente.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\ops\rollback-backend.ps1 `
  -TargetBackendImage registry.example/gestudio-backend:current-20260720 `
  -ExpectedCurrentImage registry.example/gestudio-backend:rollback-20260720 `
  -EnvFile .\.env `
  -ProjectName gestudio `
  -SkipBackup `
  -ConfirmRollback
```

## Drill descartable

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\ops\verify-application-rollback.ps1
```

El drill:

1. construye imagen actual con `actuator-readiness-v1`;
2. crea worktree de `ef4f9c31...`, anterior a V7 y Actuator;
3. incorpora V7 y Dockerfile actual;
4. construye artefacto compatible `legacy-api-401-v1`;
5. construye imagen incompatible V6;
6. inicia actual y aplica V1-V7;
7. crea alumno sintético;
8. verifica rechazo sin confirmación;
9. verifica rechazo V6;
10. crea backup;
11. cambia al artefacto legacy compatible;
12. verifica health 401, dato, Flyway y tablas V7;
13. vuelve al artefacto actual;
14. verifica readiness, datos y Flyway;
15. elimina stack, volúmenes, imágenes, worktree y temporales.

### Evidencia local 2026-07-22

- PowerShell 7.6.3: 8/8 etapas, exit 0, aproximadamente 264 s.
- Windows PowerShell 5.1: 8/8 etapas, exit 0, aproximadamente 173 s.
- En ambos casos se preservó el dato, se rechazó la imagen incompatible antes de
  mutar el servicio, se volvió a la imagen actual y no quedaron recursos del
  proyecto aislado.

## Qué no es rollback

- editar o borrar V7;
- eliminar filas de `flyway_schema_history`;
- restaurar una base antigua sin procedimiento;
- usar `ddl-auto=update`;
- usar imagen pre-V7 sin incorporar V7;
- cambiar `latest` sin digest;
- aceptar un backend unhealthy;
- usar únicamente una sonda TCP cuando hay contrato HTTP disponible;
- confundir feature flag con reversión de efectos externos.

## Límites

El drill no define:

- registry productivo;
- firma de imágenes;
- retención/promoción;
- responsables y tiempo máximo;
- monitoreo externo durante ventana;
- rollback coordinado del frontend;
- reconciliación de efectos externos.

Un rollback legacy es una mitigación temporal y pierde readiness detallada mientras permanece activo. Estos puntos continúan bloqueando staging y producción.
