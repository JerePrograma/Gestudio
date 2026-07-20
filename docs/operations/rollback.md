# Rollback de aplicación compatible con Flyway

## Principio

Gestudio usa migraciones Flyway forward-only. Un rollback de aplicación **no** puede borrar migraciones ni iniciar una imagen que desconozca versiones ya aplicadas.

Si la base registra V7, la imagen objetivo debe contener V1-V7 aunque su código funcional corresponda a una versión anterior. Una imagen que declare V6 se rechaza antes de recrear el backend.

## Primera respuesta ante un incidente V7

El emisor Jere Platform está deshabilitado por defecto. Ante un problema localizado en esa función:

1. mantener `APP_JERE_PLATFORM_STUDENT_EXPORT_ENABLED=false`;
2. reiniciar el backend sólo si la configuración cambió;
3. conservar V7 y sus tablas;
4. investigar antes de cambiar el artefacto completo.

La feature flag es una mitigación, no una down migration.

## Metadata obligatoria de imagen

El `backend/Dockerfile` genera:

```text
/app/build-metadata/flyway-latest
/app/build-metadata/git-revision
```

`flyway-latest` se deriva de los archivos `V*__*.sql` incluidos en la imagen. El rollback compara ese valor con `max(version)` de `flyway_schema_history`.

Regla:

```text
Flyway máximo de imagen objetivo == Flyway máximo exitoso de base
```

Una imagen sin metadata, con un valor inválido, anterior o posterior se rechaza.

## Preparar un artefacto rollback

El artefacto rollback debe construirse y publicarse antes de una ventana operativa. Si se revierte código a un commit anterior a V7:

1. crear un checkout separado del commit funcional anterior;
2. incorporar todas las migraciones aplicadas después de ese commit;
3. construir con el Dockerfile actual, que genera metadata;
4. ejecutar pruebas de esa fuente compatible;
5. etiquetar la imagen de forma inmutable;
6. registrar commit funcional, migraciones incorporadas, digest y fecha.

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

Este ejemplo no publica nada automáticamente. El registry, permisos y política de firmas deben definirse para staging/producción.

## Ejecutar rollback local o controlado

Requisitos:

- base y backend ya creados por Compose;
- imagen objetivo presente localmente o descargada explícitamente;
- directorio seguro para backup;
- ventana de mantenimiento;
- autorización operativa.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\ops\rollback-backend.ps1 `
  -TargetBackendImage registry.example/gestudio-backend:rollback-20260720 `
  -ExpectedCurrentImage registry.example/gestudio-backend:current-20260720 `
  -EnvFile .\.env `
  -ProjectName gestudio `
  -BackupOutputDirectory D:\Backups\Gestudio\Rollback `
  -ConfirmRollback
```

El script:

1. verifica Docker y Compose;
2. identifica la imagen actual del contenedor;
3. impide carreras mediante `ExpectedCurrentImage` cuando se informa;
4. lee la versión Flyway de la base;
5. lee la metadata Flyway de la imagen objetivo;
6. rechaza cualquier diferencia;
7. crea un backup consistente previo;
8. recrea sólo el backend;
9. espera health;
10. confirma que el contenedor usa la imagen exacta;
11. si falla, intenta restaurar automáticamente la imagen anterior.

El resultado JSON incluye imagen anterior, imagen objetivo, Flyway y directorio del backup.

## `-SkipBackup`

Existe únicamente para drills o para el retorno inmediato a un artefacto ya respaldado:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\ops\rollback-backend.ps1 `
  -TargetBackendImage <imagen> `
  -EnvFile .\.env `
  -ProjectName gestudio `
  -SkipBackup `
  -ConfirmRollback
```

No usar en un cambio destructivo real sin una copia verificada y una decisión explícita.

## Verificación después del cambio

```powershell
docker compose --env-file .env -p gestudio ps
docker compose --env-file .env -p gestudio logs --tail 200 backend
docker compose --env-file .env -p gestudio exec db sh -ec `
  'PGPASSWORD="$POSTGRES_PASSWORD" psql --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" --command="SELECT version, success FROM flyway_schema_history ORDER BY installed_rank"'
```

Verificar además:

- login;
- lectura de un alumno previo;
- consulta de cargos y pagos;
- emisión o lectura de recibo;
- caja y stock;
- ausencia de nuevas excepciones;
- health estable durante la ventana acordada.

## Retorno al artefacto actual

El retorno se ejecuta con el mismo script, usando la imagen actual como objetivo y la imagen rollback como `ExpectedCurrentImage`. No se modifica el esquema.

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

1. construye la imagen actual;
2. crea un worktree de `ef4f9c31...`, anterior a V7;
3. incorpora V7 y el Dockerfile actual para producir un artefacto compatible;
4. construye una imagen incompatible que declara V6;
5. inicia la versión actual y aplica V1-V7;
6. crea un alumno sintético;
7. verifica rechazo sin confirmación;
8. verifica rechazo de la imagen V6;
9. crea backup y cambia al artefacto anterior compatible;
10. comprueba health, dato, Flyway y tablas V7;
11. vuelve al artefacto actual;
12. verifica nuevamente datos y Flyway;
13. elimina stack, volúmenes, imágenes, worktree y temporales.

Usar `-KeepStack` sólo para diagnóstico.

## Qué no es rollback

- editar o borrar V7;
- eliminar filas de `flyway_schema_history`;
- restaurar una base antigua sobre datos actuales sin procedimiento aprobado;
- ejecutar `ddl-auto=update`;
- usar una imagen pre-V7 sin incorporar V7;
- cambiar `latest` sin registrar digest;
- ignorar un backend unhealthy;
- confundir desactivar una feature con revertir datos ya publicados externamente.

## Límites

El drill técnico no define:

- registry productivo;
- firma de imágenes;
- retención de artefactos;
- responsables;
- tiempo máximo de decisión;
- monitoreo durante la ventana;
- rollback coordinado con frontend;
- reconciliación de efectos externos.

Esos puntos continúan bloqueando staging y producción aunque el drill local sea verde.
