[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $BackupDirectory,
    [Parameter(Mandatory)][string] $TargetDatabase,
    [string] $ComposeFile,
    [string] $EnvFile,
    [string] $ProjectName = 'gestudio',
    [string] $DatabaseService = 'db',
    [string] $BackendService = 'backend',
    [switch] $ConfirmDestructiveRestore,
    [switch] $AllowSourceDatabaseRestore,
    [switch] $RestoreReceipts,
    [switch] $ConfirmReceiptsOverwrite,
    [switch] $StopBackend
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if ([string]::IsNullOrWhiteSpace($ComposeFile)) {
    $ComposeFile = Join-Path $repoRoot 'docker-compose.yml'
}

function Invoke-Native {
    param(
        [Parameter(Mandatory)][string] $FilePath,
        [Parameter(Mandatory)][string[]] $Arguments,
        [switch] $Capture
    )

    $previous = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $FilePath @Arguments 2>&1)
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previous
    }

    $text = ($output | ForEach-Object { $_.ToString() }) -join "`n"
    if ($code -ne 0) {
        $tail = (($text -split "`r?`n") | Select-Object -Last 80) -join "`n"
        throw "El comando $FilePath falló con código ${code}: $tail"
    }
    if ($Capture) { return $text.Trim() }
    if (-not [string]::IsNullOrWhiteSpace($text)) { Write-Host $text }
}

function Compose-Prefix {
    $arguments = @('compose', '-f', (Resolve-Path -LiteralPath $ComposeFile).Path)
    if (-not [string]::IsNullOrWhiteSpace($EnvFile)) {
        if (-not (Test-Path -LiteralPath $EnvFile -PathType Leaf)) {
            throw "No existe el env file: $EnvFile"
        }
        $arguments += @('--env-file', (Resolve-Path -LiteralPath $EnvFile).Path)
    }
    if (-not [string]::IsNullOrWhiteSpace($ProjectName)) {
        $arguments += @('-p', $ProjectName)
    }
    return $arguments
}

function Invoke-Compose {
    param([Parameter(Mandatory)][string[]] $Arguments, [switch] $Capture)
    return Invoke-Native -FilePath 'docker' -Arguments ((Compose-Prefix) + $Arguments) -Capture:$Capture
}

function Get-ContainerEnvironment {
    param([Parameter(Mandatory)][string] $ContainerId)

    $raw = Invoke-Native -FilePath 'docker' -Arguments @(
        'inspect', '--format', '{{range .Config.Env}}{{println .}}{{end}}', $ContainerId
    ) -Capture
    $result = @{}
    foreach ($line in ($raw -split "`r?`n")) {
        $index = $line.IndexOf('=')
        if ($index -gt 0) {
            $result[$line.Substring(0, $index)] = $line.Substring($index + 1)
        }
    }
    return $result
}

function Test-ContainerRunning {
    param([string] $ContainerId)
    if ([string]::IsNullOrWhiteSpace($ContainerId)) { return $false }
    return (Invoke-Native -FilePath 'docker' -Arguments @(
        'inspect', '--format', '{{.State.Running}}', $ContainerId
    ) -Capture) -eq 'true'
}

function Resolve-ConfinedBackupFile {
    param(
        [Parameter(Mandatory)][string] $BackupRoot,
        [Parameter(Mandatory)][string] $ManifestFileName,
        [Parameter(Mandatory)][string] $ExpectedFileName
    )

    if ($ManifestFileName -cne $ExpectedFileName -or
        [IO.Path]::GetFileName($ManifestFileName) -cne $ManifestFileName) {
        throw "El manifiesto debe referenciar el archivo canónico '$ExpectedFileName'."
    }

    $root = [IO.Path]::GetFullPath($BackupRoot).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar)
    $candidate = [IO.Path]::GetFullPath((Join-Path $root $ManifestFileName))
    $comparison = if ($env:OS -eq 'Windows_NT') {
        [StringComparison]::OrdinalIgnoreCase
    }
    else {
        [StringComparison]::Ordinal
    }
    $rootPrefix = $root + [IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith($rootPrefix, $comparison)) {
        throw "El archivo '$ManifestFileName' queda fuera del directorio de backup."
    }
    return $candidate
}

function Assert-ManifestFileIntegrity {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)] $ExpectedBytes,
        [Parameter(Mandatory)][string] $ExpectedSha256,
        [Parameter(Mandatory)][string] $Description
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Falta ${Description}: $Path"
    }
    $item = Get-Item -LiteralPath $Path
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "El ${Description} no puede ser un enlace o reparse point."
    }
    $bytes = 0L
    if (-not [long]::TryParse([string]$ExpectedBytes, [ref]$bytes) -or $bytes -le 0) {
        throw "El tamaño declarado para ${Description} no es válido."
    }
    if ($item.Length -ne $bytes) {
        throw "El tamaño de ${Description} no coincide con el manifiesto."
    }
    if ($ExpectedSha256 -cnotmatch '^[a-f0-9]{64}$') {
        throw "El SHA-256 declarado para ${Description} no es válido."
    }
    $actualHash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -cne $ExpectedSha256) {
        throw "El SHA-256 de ${Description} no coincide con el manifiesto."
    }
    return $actualHash
}

$receiptsArchiveScript = @'
set -eu
archive="/backup/$1"
action="$2"
expected_hash="$3"
expected_backup_set_id="$4"
scratch="$(mktemp -d)"
stage=''
previous=''
promotion_phase=0
cleanup() {
  status=$?
  trap - EXIT HUP INT TERM
  set +e
  if [ "$promotion_phase" -eq 2 ]; then
    for current in /app/data/receipts/* /app/data/receipts/.[!.]* /app/data/receipts/..?*; do
      [ -e "$current" ] || [ -L "$current" ] || continue
      [ "$current" = "$stage" ] && continue
      [ "$current" = "$previous" ] && continue
      rm -rf "$current"
    done
  fi
  if [ "$promotion_phase" -ne 0 ] && [ -n "$previous" ] && [ -d "$previous" ]; then
    for old in "$previous"/* "$previous"/.[!.]* "$previous"/..?*; do
      [ -e "$old" ] || [ -L "$old" ] || continue
      mv "$old" /app/data/receipts/ || status=43
    done
  fi
  rm -rf "$scratch"
  if [ -n "$stage" ]; then rm -rf "$stage"; fi
  if [ -n "$previous" ]; then rm -rf "$previous"; fi
  exit "$status"
}
trap cleanup EXIT HUP INT TERM

trusted_archive="$scratch/receipts.tar.gz"
cp "$archive" "$trusted_archive"
actual_hash="$(sha256sum "$trusted_archive")"
actual_hash="${actual_hash%% *}"
[ "$actual_hash" = "$expected_hash" ] || {
  echo 'El SHA-256 de recibos cambió antes de su uso.' >&2
  exit 39
}
archive="$trusted_archive"

tar -tzf "$archive" > "$scratch/names"
found_root=0
while IFS= read -r member || [ -n "$member" ]; do
  [ -n "$member" ] || {
    echo 'Archivo de recibos inseguro: miembro vacío.' >&2
    exit 40
  }
  path="${member%/}"
  case "$path" in
    /*|*\\*)
      echo "Archivo de recibos inseguro: ruta absoluta o separador inválido: $member" >&2
      exit 40
      ;;
  esac
  case "$path" in
    receipts) found_root=1 ;;
    receipts/*) ;;
    *)
      echo "Archivo de recibos inseguro: miembro fuera de receipts/: $member" >&2
      exit 40
      ;;
  esac
  case "$path" in
    *[!A-Za-z0-9._/-]*)
      echo "Archivo de recibos inseguro: caracteres no portables: $member" >&2
      exit 40
      ;;
  esac
  case "/$path/" in
    *'/../'*|*'/./'*|*'//'*)
      echo "Archivo de recibos inseguro: segmento de ruta inválido: $member" >&2
      exit 40
      ;;
  esac
done < "$scratch/names"
[ "$found_root" -eq 1 ] || {
  echo 'Archivo de recibos inseguro: falta el directorio receipts/.' >&2
  exit 40
}

tar -tvzf "$archive" > "$scratch/types"
while IFS= read -r entry || [ -n "$entry" ]; do
  type="${entry%"${entry#?}"}"
  case "$entry" in
    *' -> '*)
      echo "Archivo de recibos inseguro: tipo no permitido: $entry" >&2
      exit 41
      ;;
  esac
  case "$type" in
    -|d) ;;
    *)
      echo "Archivo de recibos inseguro: tipo no permitido: $entry" >&2
      exit 41
      ;;
  esac
done < "$scratch/types"

name_count="$(wc -l < "$scratch/names" | tr -d ' ')"
type_count="$(wc -l < "$scratch/types" | tr -d ' ')"
[ "$name_count" = "$type_count" ] || {
  echo 'Archivo de recibos inseguro: listado inconsistente.' >&2
  exit 41
}

case "$expected_backup_set_id" in
  *[!a-f0-9]*|'')
    echo 'El identificador del conjunto de backup es inválido.' >&2
    exit 41
    ;;
esac
[ "${#expected_backup_set_id}" -eq 32 ] || {
  echo 'El identificador del conjunto de backup es inválido.' >&2
  exit 41
}
archive_backup_set_id="$(tar -xOzf "$archive" receipts/.gestudio-backup-set-id)" || {
  echo 'El archivo de recibos no contiene su identificador de conjunto.' >&2
  exit 41
}
[ "$archive_backup_set_id" = "$expected_backup_set_id" ] || {
  echo 'El archivo de recibos pertenece a otro conjunto de backup.' >&2
  exit 41
}

if [ "$action" = validate ]; then
  exit 0
fi
[ "$action" = extract ] || exit 64
[ -d /app/data/receipts ] && [ ! -L /app/data/receipts ] || {
  echo 'El destino de recibos no es un directorio físico seguro.' >&2
  exit 42
}

stage="$(mktemp -d /app/data/receipts/.restore-next.XXXXXX)"
previous="$(mktemp -d /app/data/receipts/.restore-previous.XXXXXX)"
tar -xzf "$archive" -C "$stage" --no-same-permissions
[ -d "$stage/receipts" ] && [ ! -L "$stage/receipts" ] || {
  echo 'El archivo no produjo un directorio receipts/ seguro.' >&2
  exit 42
}
rm -f "$stage/receipts/.gestudio-backup-set-id"

promotion_phase=1
for current in /app/data/receipts/* /app/data/receipts/.[!.]* /app/data/receipts/..?*; do
  [ -e "$current" ] || [ -L "$current" ] || continue
  [ "$current" = "$stage" ] && continue
  [ "$current" = "$previous" ] && continue
  mv "$current" "$previous/"
done
promotion_phase=2
for next in "$stage/receipts"/* "$stage/receipts"/.[!.]* "$stage/receipts"/..?*; do
  [ -e "$next" ] || [ -L "$next" ] || continue
  mv "$next" /app/data/receipts/
done
chown -R gestudio:gestudio /app/data/receipts
promotion_phase=0
rm -rf "$previous" "$stage"
previous=''
stage=''
'@
$receiptsArchiveScriptBase64 = [Convert]::ToBase64String(
    [Text.Encoding]::UTF8.GetBytes($receiptsArchiveScript))

function Invoke-ReceiptsArchive {
    param(
        [Parameter(Mandatory)][string] $BackupRoot,
        [Parameter(Mandatory)][string] $ArchiveName,
        [Parameter(Mandatory)][string] $ExpectedSha256,
        [Parameter(Mandatory)][string] $BackupSetId,
        [Parameter(Mandatory)][ValidateSet('validate', 'extract')][string] $Action
    )

    $mount = "${BackupRoot}:/backup:ro"
    Invoke-Compose -Arguments @(
        'run', '--rm', '--no-deps', '--user', '0:0', '--volume', $mount,
        '--entrypoint', 'sh', $BackendService,
        '-ec',
        'printf "%s" "$1" | base64 -d > /tmp/gestudio-restore-receipts.sh && exec sh /tmp/gestudio-restore-receipts.sh "$2" "$3" "$4" "$5"',
        'sh', $receiptsArchiveScriptBase64, $ArchiveName, $Action, $ExpectedSha256, $BackupSetId
    ) | Out-Null
}

$restoreDatabaseScript = @'
set -eu
PGPASSWORD="$POSTGRES_PASSWORD" dropdb --username="$POSTGRES_USER" --maintenance-db=postgres --if-exists --force "$1"
PGPASSWORD="$POSTGRES_PASSWORD" createdb --username="$POSTGRES_USER" --maintenance-db=postgres "$1"
PGPASSWORD="$POSTGRES_PASSWORD" pg_restore --exit-on-error --no-owner --no-privileges --username="$POSTGRES_USER" --dbname="$1" "$2"
'@
$restoreDatabaseScriptBase64 = [Convert]::ToBase64String(
    [Text.Encoding]::UTF8.GetBytes($restoreDatabaseScript))

if (-not $ConfirmDestructiveRestore) {
    throw 'La restauración elimina y recrea la base destino. Reejecute con -ConfirmDestructiveRestore.'
}
if ($TargetDatabase -notmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}$') {
    throw 'TargetDatabase debe ser un identificador PostgreSQL simple de hasta 63 caracteres.'
}
if ($TargetDatabase -in @('postgres', 'template0', 'template1')) {
    throw "No se permite restaurar sobre la base reservada '$TargetDatabase'."
}
if (-not (Test-Path -LiteralPath $ComposeFile -PathType Leaf)) {
    throw "No existe Compose: $ComposeFile"
}

if (-not (Test-Path -LiteralPath $BackupDirectory -PathType Container)) {
    throw "No existe el directorio de backup: $BackupDirectory"
}
$backupRoot = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $BackupDirectory).Path)
$manifestPath = Join-Path $backupRoot 'manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Falta manifest.json en $backupRoot"
}
$manifestItem = Get-Item -LiteralPath $manifestPath
if (($manifestItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'manifest.json no puede ser un enlace o reparse point.'
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$requiredManifestProperties = @(
    'formatVersion', 'createdAtUtc', 'sourceDatabase', 'applicationConsistent',
    'flywaySuccessfulCount', 'flywayLatestVersion', 'databaseDump'
)
foreach ($property in $requiredManifestProperties) {
    if ($manifest.PSObject.Properties.Name -notcontains $property -or $null -eq $manifest.$property) {
        throw "El manifiesto está incompleto: falta '$property'."
    }
}
$formatVersion = 0
if (-not [int]::TryParse([string]$manifest.formatVersion, [ref]$formatVersion) -or
    $formatVersion -notin @(1, 2)) {
    throw "Versión de backup no soportada: $($manifest.formatVersion)"
}
$backupSetId = $null
if ($formatVersion -eq 2) {
    if ($manifest.PSObject.Properties.Name -notcontains 'backupSetId' -or
        [string]$manifest.backupSetId -cnotmatch '^[a-f0-9]{32}$') {
        throw "El manifiesto está incompleto: falta un backupSetId válido."
    }
    $backupSetId = [string]$manifest.backupSetId
}
elseif ($RestoreReceipts) {
    throw 'Los backups de formato v1 no vinculan de forma segura la base y los recibos; restaure sólo PostgreSQL o genere un backup v2.'
}
if ([string]$manifest.sourceDatabase -notmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}$') {
    throw 'El manifiesto contiene una base de origen inválida.'
}
$flywayCount = 0
$flywayLatest = 0
if (-not [int]::TryParse([string]$manifest.flywaySuccessfulCount, [ref]$flywayCount) -or $flywayCount -le 0 -or
    -not [int]::TryParse([string]$manifest.flywayLatestVersion, [ref]$flywayLatest) -or $flywayLatest -le 0) {
    throw 'El manifiesto contiene metadata Flyway inválida.'
}

$dumpPath = Resolve-ConfinedBackupFile -BackupRoot $backupRoot `
    -ManifestFileName ([string]$manifest.databaseDump.file) -ExpectedFileName 'database.dump'
$dumpHash = Assert-ManifestFileIntegrity -Path $dumpPath `
    -ExpectedBytes $manifest.databaseDump.bytes `
    -ExpectedSha256 ([string]$manifest.databaseDump.sha256) `
    -Description 'dump'

$overwritesSource = $TargetDatabase -eq [string]$manifest.sourceDatabase
if ($overwritesSource -and -not $AllowSourceDatabaseRestore) {
    throw 'Se rechazó restaurar sobre la base origen. Use otra base o agregue -AllowSourceDatabaseRestore.'
}
if ($RestoreReceipts -and -not $ConfirmReceiptsOverwrite) {
    throw 'Restaurar recibos reemplaza el directorio actual. Agregue -ConfirmReceiptsOverwrite.'
}

$receiptsPath = $null
if ($RestoreReceipts) {
    if ($manifest.applicationConsistent -ne $true) {
        throw 'El backup no está marcado como consistente para restaurar base y recibos.'
    }
    if ($null -eq $manifest.receiptsArchive) {
        throw 'El backup no contiene archivo de recibos.'
    }
    $receiptsPath = Resolve-ConfinedBackupFile -BackupRoot $backupRoot `
        -ManifestFileName ([string]$manifest.receiptsArchive.file) -ExpectedFileName 'receipts.tar.gz'
    $receiptsHash = Assert-ManifestFileIntegrity -Path $receiptsPath `
        -ExpectedBytes $manifest.receiptsArchive.bytes `
        -ExpectedSha256 ([string]$manifest.receiptsArchive.sha256) `
        -Description 'archivo de recibos'
}

Invoke-Native -FilePath 'docker' -Arguments @('version') | Out-Null
Invoke-Native -FilePath 'docker' -Arguments @('compose', 'version') | Out-Null

$dbContainer = Invoke-Compose -Arguments @('ps', '-q', $DatabaseService) -Capture
if ([string]::IsNullOrWhiteSpace($dbContainer)) {
    throw "El servicio '$DatabaseService' no está creado."
}
if (-not (Test-ContainerRunning -ContainerId $dbContainer)) {
    throw 'El contenedor de base no está ejecutándose.'
}
$dbEnvironment = Get-ContainerEnvironment -ContainerId $dbContainer
if ([string]::IsNullOrWhiteSpace($dbEnvironment['POSTGRES_USER']) -or
    [string]::IsNullOrWhiteSpace($dbEnvironment['POSTGRES_DB'])) {
    throw 'El contenedor no expone POSTGRES_USER y POSTGRES_DB.'
}
$overwritesActiveDatabase = $TargetDatabase -eq [string]$dbEnvironment['POSTGRES_DB']
if ($overwritesActiveDatabase -and -not $AllowSourceDatabaseRestore) {
    throw 'Se rechazó restaurar sobre la base activa. Use otra base o agregue -AllowSourceDatabaseRestore.'
}
if ($RestoreReceipts -and -not $overwritesActiveDatabase) {
    throw 'Se rechazó restaurar recibos junto a una base alternativa: el volumen pertenece a la base activa del proyecto.'
}

$backendContainer = Invoke-Compose -Arguments @('ps', '-q', $BackendService) -Capture
$backendWasRunning = Test-ContainerRunning -ContainerId $backendContainer
if (($RestoreReceipts -or $overwritesSource -or $overwritesActiveDatabase) -and $backendWasRunning -and -not $StopBackend) {
    throw 'El backend está ejecutándose. Agregue -StopBackend para detenerlo durante la restauración.'
}

if ($receiptsPath) {
    Invoke-ReceiptsArchive -BackupRoot $backupRoot `
        -ArchiveName ([string]$manifest.receiptsArchive.file) `
        -ExpectedSha256 ([string]$manifest.receiptsArchive.sha256) `
        -BackupSetId $backupSetId -Action validate
}

$remoteDump = "/tmp/gestudio-restore-$([Guid]::NewGuid().ToString('N')).dump"
$backendStopped = $false
try {
    if (($RestoreReceipts -or $overwritesSource -or $overwritesActiveDatabase) -and $backendWasRunning) {
        Invoke-Compose -Arguments @('stop', $BackendService) | Out-Null
        $backendStopped = $true
    }

    Invoke-Native -FilePath 'docker' -Arguments @('cp', $dumpPath, "${dbContainer}:$remoteDump") | Out-Null
    $remoteDumpHashOutput = Invoke-Native -FilePath 'docker' -Arguments @(
        'exec', $dbContainer, 'sha256sum', $remoteDump
    ) -Capture
    $remoteDumpHashMatch = [regex]::Match($remoteDumpHashOutput, '^(?<hash>[a-f0-9]{64})(?:\s|$)')
    if (-not $remoteDumpHashMatch.Success) {
        throw 'sha256sum devolvió una salida inválida para el dump copiado.'
    }
    $remoteDumpHash = $remoteDumpHashMatch.Groups['hash'].Value
    if ($remoteDumpHash -cne $dumpHash) {
        throw 'El SHA-256 del dump cambió durante la copia al contenedor.'
    }
    Invoke-Native -FilePath 'docker' -Arguments @(
        'exec', $dbContainer, 'pg_restore', '--list', $remoteDump
    ) -Capture | Out-Null
    Invoke-Native -FilePath 'docker' -Arguments @(
        'exec', $dbContainer, 'sh', '-ec',
        'printf "%s" "$1" | base64 -d > /tmp/gestudio-restore-database.sh && exec sh /tmp/gestudio-restore-database.sh "$2" "$3"',
        'sh', $restoreDatabaseScriptBase64, $TargetDatabase, $remoteDump
    ) | Out-Null

    $sql = 'SELECT count(*)::text || ''|'' || coalesce(max(version::int)::text,'''') FROM flyway_schema_history WHERE success'
    $sqlBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($sql))
    $flyway = Invoke-Native -FilePath 'docker' -Arguments @(
        'exec', $dbContainer, 'sh', '-ec',
        'printf "%s" "$2" | base64 -d | PGPASSWORD="$POSTGRES_PASSWORD" psql --no-psqlrc --tuples-only --no-align --username="$POSTGRES_USER" --dbname="$1" --file=-',
        'sh', $TargetDatabase, $sqlBase64
    ) -Capture
    $parts = $flyway.Trim().Split('|')
    if ($parts.Count -ne 2 -or
        [int]$parts[0] -ne [int]$manifest.flywaySuccessfulCount -or
        $parts[1] -ne [string]$manifest.flywayLatestVersion) {
        throw "Flyway restaurado no coincide. Esperado=$($manifest.flywaySuccessfulCount)|$($manifest.flywayLatestVersion), actual=$flyway"
    }

    if ($receiptsPath) {
        Invoke-ReceiptsArchive -BackupRoot $backupRoot `
            -ArchiveName ([string]$manifest.receiptsArchive.file) `
            -ExpectedSha256 ([string]$manifest.receiptsArchive.sha256) `
            -BackupSetId $backupSetId -Action extract
    }
}
finally {
    try {
        Invoke-Native -FilePath 'docker' -Arguments @('exec', $dbContainer, 'rm', '-f', $remoteDump) | Out-Null
    }
    catch {
        Write-Warning 'No se pudo eliminar el dump temporal del contenedor.'
    }

    if ($backendStopped) {
        try {
            Invoke-Compose -Arguments @('start', $BackendService) | Out-Null
        }
        catch {
            Write-Warning 'La restauración terminó, pero no se pudo reiniciar el backend.'
        }
    }
}

Write-Host "Restore verificado en base: $TargetDatabase" -ForegroundColor Green
Write-Host "Flyway: $($manifest.flywayLatestVersion) | Dump SHA-256: $dumpHash"
