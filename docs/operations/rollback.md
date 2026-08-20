# Rollback de aplicación compatible con Flyway y health

## Principio

Gestudio usa migraciones Flyway forward-only. Un rollback de aplicación no puede borrar migraciones ni iniciar una imagen que desconozca versiones ya aplicadas.

El estado actual del repositorio contiene la cadena versionada V1-V12 y la baseline fresh B12. Este runbook no fija 12 como constante operativa: los scripts derivan `N` de los archivos `V*__*.sql`, exigen una única `B<N>__*.sql` y comprueban que ambas llegan a la misma versión.

Si la base registra `N`, la imagen objetivo debe contener la cadena productiva actual `V1..VN` y `B<N>`, aunque su código funcional corresponda a una versión anterior. Una imagen que declare `N-1` se rechaza antes de recrear el backend.

El rollback también debe conocer cómo comprobar que cada artefacto quedó operativo. Las imágenes anteriores a Actuator no publican readiness, por lo que no pueden validarse con el mismo endpoint que una imagen actual.

## Primera respuesta ante un incidente del control plane

V12 incorpora identidad, sesiones, MFA, step-up, idempotencia y auditoría del control plane; B12 representa el esquema fresh equivalente. No existe una down migration segura de ese contrato.

Ante un incidente localizado:

1. contener nuevas operaciones privilegiadas mediante el control de tráfico o acceso ya autorizado para el entorno;
2. conservar V12/B12, las tablas de plataforma, sus grants y sus políticas;
3. obtener y verificar un backup antes de cambiar el artefacto;
4. preferir un forward fix cuando cambió la semántica persistida;
5. usar rollback de aplicación sólo con un artefacto histórico previamente calificado contra la versión `N` actual;
6. verificar después del cambio que el runtime tenant no ganó escritura de control plane y que el runtime de plataforma no ganó lectura de datos funcionales tenant.

Contener tráfico o cambiar una imagen no revierte datos ni migraciones.

## Metadata obligatoria de imagen

El Dockerfile genera:

```text
/app/build-metadata/flyway-latest
/app/build-metadata/flyway-versioned-latest
/app/build-metadata/flyway-baseline-script
/app/build-metadata/git-revision
/app/build-metadata/health-contract
```

`flyway-latest` y `flyway-versioned-latest` se derivan de los archivos `V*__*.sql` incluidos en la imagen. `flyway-baseline-script` identifica la única baseline B<N> y el build exige que `N` coincida en ambas familias.

`health-contract` admite:

| Contrato | Uso | Sonda |
|---|---|---|
| `actuator-readiness-v1` | imágenes con Actuator | `/actuator/health/readiness` debe responder `UP` |
| `legacy-api-401-v1` | imágenes anteriores a Actuator | `/api/alumnos` debe responder HTTP `401` sin credencial |

La sonda legacy no es un simple puerto. Exige que la aplicación haya terminado de iniciar y que su capa HTTP/seguridad responda con el contrato esperado. Se usa sólo para permitir una retirada temporal a un artefacto anterior aprobado.

Imágenes creadas antes de incorporar `health-contract`, pero que sí tienen metadata Flyway válida, se clasifican con advertencia como `legacy-api-401-v1`.

Regla de esquema:

```text
manifiesto local == V1..VN contiguo + una única B<N>
flyway-latest de imagen activa y objetivo == N
flyway-versioned-latest de imagen activa y objetivo == N
flyway-baseline-script de imagen activa y objetivo == nombre local exacto B<N>
historial DB == VERSIONED V1..VN exacto o BASELINE B<N> exacta
failed en flyway_schema_history == 0
```

Una imagen activa u objetivo sin cualquiera de las tres metadata Flyway, con valor inválido, anterior o posterior se rechaza. Comparar sólo `max(version)` no es suficiente: un historial con huecos o con filas fallidas también se rechaza aunque conserve el mismo máximo. Un contrato de health desconocido también se rechaza.

El runtime de rollback y el drill comprueban que el historial permanece exactamente en el mismo modo (`VERSIONED` V1..VN o `BASELINE` B<N>) y que siguen vigentes las estructuras y los grants mínimos del control plane. Esos contratos se verifican antes de crear el backup o recrear el backend, después del cambio y después de una recuperación automática.

## Preparar un artefacto rollback

Debe construirse, calificarse y publicarse antes de una ventana operativa. Para revertir código a un commit funcional anterior:

1. seleccionar un SHA exacto, aprobado y ancestro del SHA actual;
2. extraer `backend/` de ese commit mediante `git archive`, en un directorio aleatorio bajo el temporal del sistema;
3. validar que todas las rutas resueltas permanecen dentro de ese temporal y rechazar reparse points;
4. conservar el contenido histórico exacto salvo dos overlays deliberados: el Dockerfile actual y el directorio Flyway productivo actual `V1..VN` más `B<N>`;
5. comprobar por SHA-256 cada archivo copiado y volver a derivar el manifiesto Flyway;
6. construir y probar el artefacto compatible sin crear ramas ni modificar estado Git;
7. dejar que el build derive el contrato de health según las dependencias históricas presentes;
8. etiquetar/publicar de forma inmutable;
9. registrar SHA funcional resuelto, `N`, baseline, contrato health, digest y fecha.

No usar `latest` como único identificador.

El drill implementa la extracción y los overlays fail-closed. Para calificar un commit concreto:

```powershell
$historicalCommit = '<sha-anterior-aprobado>'
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\ops\verify-application-rollback.ps1 `
  -HistoricalCommit $historicalCommit
```

Si se omite `-HistoricalCommit`, el drill descartable usa `HEAD^`; esto sirve para CI de continuidad, no sustituye la selección y promoción explícita de un artefacto productivo. El drill elimina sus imágenes al finalizar. La publicación debe reproducir los mismos inputs verificados en una pipeline controlada y registrar el digest resultante.

Comprobar metadata:

```powershell
$image = 'registry.example/gestudio-backend:<id-inmutable>'
docker run --rm --entrypoint cat $image /app/build-metadata/flyway-latest
docker run --rm --entrypoint cat $image /app/build-metadata/flyway-versioned-latest
docker run --rm --entrypoint cat $image /app/build-metadata/flyway-baseline-script
docker run --rm --entrypoint cat $image /app/build-metadata/health-contract
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
  -TargetBackendImage 'registry.example/gestudio-backend:rollback-<id-inmutable>' `
  -ExpectedCurrentImage 'registry.example/gestudio-backend:current-<id-inmutable>' `
  -EnvFile .\.env `
  -ProjectName gestudio `
  -BackupOutputDirectory $rollbackRoot `
  -ConfirmRollback
```

El script:

1. deriva el manifiesto local contiguo `V1..VN` y la baseline única `B<N>`;
2. verifica Docker y Compose;
3. identifica imagen actual e impide carreras mediante `ExpectedCurrentImage`;
4. exige en imagen activa y objetivo las tres metadata Flyway exactas del manifiesto local;
5. exige historial DB exacto `VERSIONED` o `BASELINE`, sin migraciones fallidas;
6. verifica estructuras y frontera mínima de grants del control plane;
7. obtiene contratos de health actual y objetivo;
8. crea backup consistente previo;
9. recrea sólo backend con el contrato objetivo y espera health;
10. vuelve a verificar modo Flyway, estructuras y grants;
11. si falla, recupera la imagen anterior con su propio contrato;
12. después de recuperar vuelve a verificar modo Flyway, estructuras y grants antes de informar la mitigación.

El JSON final incluye:

- imagen anterior y objetivo;
- contrato health anterior y objetivo;
- versión, modo (`VERSIONED` o `BASELINE`) y baseline Flyway;
- directorio de backup.

El contrato fail-closed sin daemon real se valida con:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\ops\test-rollback-backend-contract.ps1
```

Las fixtures usan un comando Docker falso sin secretos. Demuestran que una imagen sin metadata de baseline, un historial con hueco pero máximo `N` y un historial con filas fallidas pero máximo `N` abortan antes de crear backup o ejecutar `docker compose up`.

## `-SkipBackup`

Existe sólo para drills o retorno inmediato a un artefacto ya respaldado:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\ops\rollback-backend.ps1 `
  -TargetBackendImage 'registry.example/gestudio-backend:<id-inmutable>' `
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
  -TargetBackendImage 'registry.example/gestudio-backend:current-<id-inmutable>' `
  -ExpectedCurrentImage 'registry.example/gestudio-backend:rollback-<id-inmutable>' `
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

1. deriva la cadena actual `V1..VN` y la baseline única `B<N>`;
2. resuelve `HistoricalCommit` a un SHA exacto, distinto de HEAD y ancestro suyo;
3. extrae `backend/` mediante un archivo Git de sólo lectura en una ruta temporal validada;
4. reemplaza sólo Flyway y Dockerfile por las copias actuales verificadas por SHA-256;
5. construye las imágenes actual, histórica-compatible e incompatible `N-1`;
6. inicia la imagen actual y acepta sólo un historial exacto `V1..VN` o `B<N>`;
7. verifica estructuras y privilegios del control plane;
8. crea un tenant y un alumno sintéticos;
9. verifica rechazo sin confirmación;
10. verifica rechazo de la imagen `N-1` antes de mutar;
11. crea backup y cambia al artefacto histórico compatible;
12. verifica health según la metadata del artefacto, dato, Flyway y control plane;
13. vuelve al artefacto actual;
14. verifica nuevamente health, datos, Flyway y control plane;
15. elimina únicamente el stack etiquetado, sus volúmenes/red, las imágenes del drill y el temporal validado. Git no se modifica.

### Estado de evidencia

La evidencia de julio de 2026 correspondía al contrato anterior y quedó invalidada por V12/B12, el control plane y el nuevo ensamblado temporal. Debe ejecutarse nuevamente el comando anterior sobre el SHA candidato. Hasta obtener exit 0 y cleanup completo, el gate de rollback no es `PASS`.

## Qué no es rollback

- editar o borrar una migración publicada `V1..VN` o su baseline `B<N>`;
- eliminar filas de `flyway_schema_history`;
- restaurar una base antigua sin procedimiento;
- usar `ddl-auto=update`;
- usar una imagen histórica sin incorporar la cadena Flyway y el Dockerfile actuales;
- cambiar `latest` sin digest;
- aceptar un backend unhealthy;
- usar únicamente una sonda TCP cuando hay contrato HTTP disponible;
- confundir un cambio de imagen con una down migration o con reversión de efectos externos.

## Límites

El drill no define:

- registry productivo;
- firma de imágenes;
- retención/promoción;
- responsables y tiempo máximo;
- monitoreo externo durante ventana;
- rollback coordinado del frontend;
- reconciliación de efectos externos.

Un rollback legacy es una mitigación temporal y pierde readiness detallada mientras permanece activo. No revierte migraciones destructivas: esos casos requieren forward fix o restore verificado, más reconciliación explícita. Los puntos anteriores continúan bloqueando staging y producción mientras no exista evidencia del entorno real.
