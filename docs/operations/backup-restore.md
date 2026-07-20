# Backup y restore operativo

## Estado y alcance

Este runbook cubre el respaldo y la recuperación local o de un entorno controlado de Gestudio mediante Docker Compose.

El paquete de backup puede incluir:

- PostgreSQL en formato custom de `pg_dump`;
- el volumen lógico de recibos de `/app/data/receipts`;
- un `manifest.json` con SHA-256, tamaños, HEAD Git y versión Flyway.

No constituye por sí solo autorización para operar producción. La retención, cifrado externo, custodia, RPO/RTO y permisos del repositorio de backups deben definirse antes de staging o producción.

## Requisitos

- Docker Engine activo;
- Docker Compose v2;
- PowerShell 7 o Windows PowerShell 5.1;
- stack creado mediante `docker-compose.yml`;
- acceso de escritura a un directorio fuera del repositorio para conservar backups reales.

Los comandos siguientes se ejecutan desde la raíz del repositorio.

## Crear un backup consistente de aplicación

Cuando se incluyen recibos, el backend debe detenerse para evitar que la base y los archivos representen instantes diferentes. El script lo detiene y reinicia con `-StopBackend`.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\ops\backup-postgres.ps1 `
  -EnvFile .\.env `
  -ProjectName gestudio `
  -OutputDirectory D:\Backups\Gestudio `
  -StopBackend
```

El resultado es un directorio similar a:

```text
D:\Backups\Gestudio\gestudio-backup-20260720T190000Z-a1b2c3d4\
├── database.dump
├── receipts.tar.gz
└── manifest.json
```

El manifiesto registra:

- fecha UTC;
- proyecto Compose;
- base y usuario de origen;
- HEAD Git, cuando está disponible;
- cantidad y última versión Flyway;
- tamaño y SHA-256 del dump;
- tamaño y SHA-256 del archivo de recibos;
- si el backup se tomó con consistencia de aplicación.

## Backup sólo de PostgreSQL

`pg_dump` obtiene un snapshot transaccional consistente. Puede ejecutarse con el backend activo si se excluyen los recibos:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\ops\backup-postgres.ps1 `
  -EnvFile .\.env `
  -ProjectName gestudio `
  -OutputDirectory D:\Backups\Gestudio `
  -SkipReceipts
```

Este modo no preserva los archivos PDF ya generados. No debe usarse como único respaldo de una instalación que necesite reconstruir exactamente su archivo de recibos.

## Restaurar primero a una base nueva

La práctica segura es validar el paquete en una base distinta antes de considerar un reemplazo del origen:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\ops\restore-postgres.ps1 `
  -BackupDirectory D:\Backups\Gestudio\gestudio-backup-20260720T190000Z-a1b2c3d4 `
  -TargetDatabase gestudio_restore_20260720 `
  -EnvFile .\.env `
  -ProjectName gestudio `
  -ConfirmDestructiveRestore
```

El script:

1. valida el manifiesto;
2. compara tamaños y SHA-256;
3. rechaza nombres PostgreSQL inseguros o bases reservadas;
4. elimina y recrea únicamente la base destino indicada;
5. ejecuta `pg_restore --exit-on-error`;
6. compara cantidad y versión Flyway con el manifiesto.

## Restaurar también recibos

Restaurar recibos reemplaza el contenido actual del volumen. Requiere dos confirmaciones explícitas y detener el backend:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\ops\restore-postgres.ps1 `
  -BackupDirectory D:\Backups\Gestudio\gestudio-backup-20260720T190000Z-a1b2c3d4 `
  -TargetDatabase gestudio_restore_20260720 `
  -EnvFile .\.env `
  -ProjectName gestudio `
  -ConfirmDestructiveRestore `
  -RestoreReceipts `
  -ConfirmReceiptsOverwrite `
  -StopBackend
```

El archivo se valida con SHA-256 y `tar -tzf` antes de modificar el volumen.

## Restaurar sobre la base origen

Esta operación es destructiva y está bloqueada por defecto. Sólo después de probar el paquete en una base alternativa:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\ops\restore-postgres.ps1 `
  -BackupDirectory D:\Backups\Gestudio\gestudio-backup-20260720T190000Z-a1b2c3d4 `
  -TargetDatabase gestudio_db `
  -EnvFile .\.env `
  -ProjectName gestudio `
  -ConfirmDestructiveRestore `
  -AllowSourceDatabaseRestore `
  -RestoreReceipts `
  -ConfirmReceiptsOverwrite `
  -StopBackend
```

No se debe ejecutar contra una base real sin una ventana de mantenimiento, copia externa verificada, criterio de aceptación y autorización operativa.

## Drill descartable automatizado

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\ops\verify-backup-restore.ps1
```

El drill:

1. crea un proyecto Compose aislado con puertos y secretos aleatorios;
2. espera PostgreSQL y backend healthy;
3. verifica Flyway V1-V7;
4. crea un alumno y un recibo sintéticos;
5. ejecuta un backup consistente;
6. elimina la fixture del origen;
7. comprueba que un restore sin confirmación sea rechazado;
8. comprueba que sobrescribir el origen sin autorización sea rechazado;
9. restaura en otra base y repone recibos;
10. verifica datos, Flyway V7, tablas de integración y contenido del archivo;
11. elimina contenedores, red, volúmenes, imagen y temporales.

Usá `-KeepStack` sólo para investigar un fallo. El script mostrará el nombre del proyecto y el env temporal.

## Semántica de fallos

- Un paquete incompleto de backup se elimina automáticamente.
- El dump temporal dentro del contenedor se elimina en `finally`.
- Si el backup detuvo el backend, intenta reiniciarlo aun ante fallo.
- El restore valida los archivos antes de destruir la base destino.
- PostgreSQL y recibos no forman una única transacción distribuida. Un fallo al restaurar recibos puede ocurrir después de restaurar la base; por eso se exige backup verificado y ventana de mantenimiento.
- Después de aplicar una migración Flyway no se ejecutan migraciones descendentes. Una corrección de esquema debe ser forward-only.

## Custodia

Para un entorno no local:

- almacenar el paquete fuera del host de aplicación;
- cifrarlo en reposo y durante transferencia;
- limitar lectura y restauración a operadores autorizados;
- impedir que el directorio sea servido por HTTP;
- probar periódicamente la restauración;
- registrar fecha, HEAD, Flyway, duración, operador y resultado;
- definir retención y borrado seguro;
- no versionar backups, dumps ni recibos en Git.

## Estado de release

El drill automatizado permite cerrar el riesgo técnico de recuperación sólo cuando su workflow está verde. Aun con el drill aprobado permanecen separados:

- rollback de código y configuración;
- observabilidad;
- staging;
- autorización de producción;
- RPO/RTO contractuales.
