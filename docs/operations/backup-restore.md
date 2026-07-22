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
$backupRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'GestudioBackups'
New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\ops\backup-postgres.ps1 `
  -EnvFile .\.env `
  -ProjectName gestudio `
  -OutputDirectory $backupRoot `
  -StopBackend
```

El resultado es un directorio similar a:

```text
<directorio-de-backups>\gestudio-backup-20260720T190000Z-a1b2c3d4\
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
$backupRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'GestudioBackups'
New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\ops\backup-postgres.ps1 `
  -EnvFile .\.env `
  -ProjectName gestudio `
  -OutputDirectory $backupRoot `
  -SkipReceipts
```

Este modo no preserva los archivos PDF ya generados. No debe usarse como único respaldo de una instalación que necesite reconstruir exactamente su archivo de recibos.

## Restaurar primero a una base nueva

La práctica segura es validar el paquete en una base distinta antes de considerar un reemplazo del origen:

```powershell
$backupDirectory = (Resolve-Path '<directorio-emitido-por-backup-postgres>').Path
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\ops\restore-postgres.ps1 `
  -BackupDirectory $backupDirectory `
  -TargetDatabase gestudio_restore_20260720 `
  -EnvFile .\.env `
  -ProjectName gestudio `
  -ConfirmDestructiveRestore
```

El script:

1. valida el manifiesto y exige los nombres canónicos `database.dump` y `receipts.tar.gz`;
2. compara tamaños y SHA-256;
3. confina cada archivo al directorio del paquete y rechaza enlaces o `reparse points`;
4. rechaza nombres PostgreSQL inseguros o bases reservadas;
5. elimina y recrea únicamente la base destino indicada;
6. ejecuta `pg_restore --exit-on-error`;
7. compara cantidad y versión Flyway con el manifiesto.

## Restaurar también recibos

Restaurar recibos reemplaza el contenido actual del volumen. Ese volumen pertenece a la base activa del proyecto Compose: por seguridad, el script rechaza combinar `-RestoreReceipts` con una base alternativa. Primero validá el dump en otra base sin recibos; después, dentro de la ventana de mantenimiento, restaurá base activa y recibos juntos con las dos confirmaciones y el backend detenido:

```powershell
$backupDirectory = (Resolve-Path '<directorio-emitido-por-backup-postgres>').Path
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\ops\restore-postgres.ps1 `
  -BackupDirectory $backupDirectory `
  -TargetDatabase gestudio_db `
  -EnvFile .\.env `
  -ProjectName gestudio `
  -ConfirmDestructiveRestore `
  -AllowSourceDatabaseRestore `
  -RestoreReceipts `
  -ConfirmReceiptsOverwrite `
  -StopBackend
```

Antes de modificar la base o el volumen, el archivo se copia a un temporal privado, se vuelve a validar por SHA-256 y se inspeccionan todos sus miembros. Sólo se aceptan directorios y archivos regulares bajo `receipts/`; se rechazan rutas absolutas, segmentos `..` o `.`, separadores inválidos, symlinks, hardlinks, dispositivos y FIFOs. La extracción se hace primero en un directorio temporal sin restaurar permisos privilegiados. Con el backend detenido, el contenido anterior se mueve dentro del mismo volumen y se repone automáticamente si falla la promoción del nuevo contenido.

## Restaurar sobre la base origen

Esta operación es destructiva y está bloqueada por defecto. Sólo después de probar el paquete en una base alternativa:

```powershell
$backupDirectory = (Resolve-Path '<directorio-emitido-por-backup-postgres>').Path
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\ops\restore-postgres.ps1 `
  -BackupDirectory $backupDirectory `
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
6. rechaza nombre manipulado, manifiesto incompleto y `backupSetId` ausente o inconsistente;
7. rechaza hash incorrecto, dump alterado, archivo faltante y backup parcial;
8. rechaza traversal, ruta absoluta y miembros fuera de `receipts/`;
9. rechaza symlink, hardlink POSIX real y entradas que declaran destino de enlace;
10. rechaza tar malformado, recibos de otra base y variables host adversariales;
11. comprueba tras cada rechazo que base/recibos sigan intactos y sin staging parcial;
12. restaura en base alternativa y luego base/recibos activos como una unidad operativa;
13. verifica datos, Flyway, tablas de integración, UTF-8, Base64 y quoting;
14. captura el TOC de `pg_restore --list` sin imprimirlo en éxito y conserva exit/stderr en fallo;
15. elimina contenedores, red, volúmenes, imagen, staging, credenciales y temporales.

Usá `-KeepStack` sólo para investigar un fallo. El script mostrará el nombre del proyecto y el env temporal.

### Evidencia local del hardening — 2026-07-22

Las ejecuciones posteriores a la captura silenciosa del TOC terminaron con:

- PowerShell 7.6.3: 12/12, exit 0, aproximadamente 163 s;
- Windows PowerShell 5.1: 12/12, exit 0, aproximadamente 168 s;
- limpieza completa de los recursos del proyecto aislado.

Esta evidencia cierra el drill local. El workflow del SHA final y las políticas
externas de custodia, cifrado y RPO/RTO se registran por separado.

## Semántica de fallos

- Un paquete incompleto de backup se elimina automáticamente.
- El dump temporal dentro del contenedor se elimina en `finally`.
- El dump se vuelve a verificar por SHA-256 después de copiarlo al contenedor y antes de eliminar la base destino.
- Si el backup detuvo el backend, intenta reiniciarlo aun ante fallo.
- El restore valida los archivos antes de destruir la base destino.
- Un restore con recibos sólo se admite sobre la base activa detectada desde el contenedor; una base alternativa no puede reemplazar el volumen del proyecto.
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

El drill local endurecido está aprobado en ambos shells. El workflow del SHA
publicado aporta la evidencia Linux separada. Aun con ambos aprobados permanecen
separados:

- rollback de código y configuración;
- observabilidad;
- staging;
- autorización de producción;
- RPO/RTO contractuales.
