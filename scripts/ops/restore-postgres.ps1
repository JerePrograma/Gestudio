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

$backupRoot = (Resolve-Path -LiteralPath $BackupDirectory).Path
$manifestPath = Join-Path $backupRoot 'manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Falta manifest.json en $backupRoot"
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.formatVersion -ne 1) {
    throw "Versión de backup no soportada: $($manifest.formatVersion)"
}

$dumpPath = Join-Path $backupRoot $manifest.databaseDump.file
if (-not (Test-Path -LiteralPath $dumpPath -PathType Leaf)) {
    throw "Falta dump: $dumpPath"
}
if ((Get-Item $dumpPath).Length -ne [long]$manifest.databaseDump.bytes) {
    throw 'El tamaño del dump no coincide con el manifiesto.'
}
$dumpHash = (Get-FileHash -LiteralPath $dumpPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($dumpHash -ne $manifest.databaseDump.sha256) {
    throw 'El SHA-256 del dump no coincide con el manifiesto.'
}

$overwritesSource = $TargetDatabase -eq [string]$manifest.sourceDatabase
if ($overwritesSource -and -not $AllowSourceDatabaseRestore) {
    throw 'Se rechazó restaurar sobre la base origen. Use otra base o agregue -AllowSourceDatabaseRestore.'
}
if ($RestoreReceipts -and -not $ConfirmReceiptsOverwrite) {
    throw 'Restaurar recibos reemplaza el directorio actual. Agregue -ConfirmReceiptsOverwrite.'
}

$receiptsPath = $null
if ($RestoreReceipts) {
    if ($null -eq $manifest.receiptsArchive) {
        throw 'El backup no contiene archivo de recibos.'
    }
    $receiptsPath = Join-Path $backupRoot $manifest.receiptsArchive.file
    if (-not (Test-Path -LiteralPath $receiptsPath -PathType Leaf)) {
        throw "Falta archivo de recibos: $receiptsPath"
    }
    if ((Get-Item $receiptsPath).Length -ne [long]$manifest.receiptsArchive.bytes) {
        throw 'El tamaño del archivo de recibos no coincide con el manifiesto.'
    }
    $receiptsHash = (Get-FileHash -LiteralPath $receiptsPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($receiptsHash -ne $manifest.receiptsArchive.sha256) {
        throw 'El SHA-256 de recibos no coincide con el manifiesto.'
    }
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
if ([string]::IsNullOrWhiteSpace($dbEnvironment['POSTGRES_USER'])) {
    throw 'El contenedor no expone POSTGRES_USER.'
}

$backendContainer = Invoke-Compose -Arguments @('ps', '-q', $BackendService) -Capture
$backendWasRunning = Test-ContainerRunning -ContainerId $backendContainer
if (($RestoreReceipts -or $overwritesSource) -and $backendWasRunning -and -not $StopBackend) {
    throw 'El backend está ejecutándose. Agregue -StopBackend para detenerlo durante la restauración.'
}

if ($receiptsPath) {
    $mount = "${backupRoot}:/backup:ro"
    Invoke-Compose -Arguments @(
        'run', '--rm', '--no-deps', '--user', '0:0', '--volume', $mount,
        '--entrypoint', 'sh', $BackendService,
        '-ec', "tar -tzf /backup/$($manifest.receiptsArchive.file) >/dev/null"
    ) | Out-Null
}

$remoteDump = "/tmp/gestudio-restore-$([Guid]::NewGuid().ToString('N')).dump"
$backendStopped = $false
try {
    if (($RestoreReceipts -or $overwritesSource) -and $backendWasRunning) {
        Invoke-Compose -Arguments @('stop', $BackendService) | Out-Null
        $backendStopped = $true
    }

    Invoke-Native -FilePath 'docker' -Arguments @('cp', $dumpPath, "${dbContainer}:$remoteDump") | Out-Null
    Invoke-Native -FilePath 'docker' -Arguments @(
        'exec', $dbContainer, 'sh', '-ec',
        'PGPASSWORD="$POSTGRES_PASSWORD" dropdb --username="$POSTGRES_USER" --maintenance-db=postgres --if-exists --force "$1" && PGPASSWORD="$POSTGRES_PASSWORD" createdb --username="$POSTGRES_USER" --maintenance-db=postgres "$1" && PGPASSWORD="$POSTGRES_PASSWORD" pg_restore --exit-on-error --no-owner --no-privileges --username="$POSTGRES_USER" --dbname="$1" "$2"',
        'sh', $TargetDatabase, $remoteDump
    ) | Out-Null

    $sql = 'SELECT count(*)::text || ''|'' || coalesce(max(version::int)::text,'''') FROM flyway_schema_history WHERE success'
    $flyway = Invoke-Native -FilePath 'docker' -Arguments @(
        'exec', $dbContainer, 'sh', '-ec',
        'PGPASSWORD="$POSTGRES_PASSWORD" psql --no-psqlrc --tuples-only --no-align --username="$POSTGRES_USER" --dbname="$1" --command="$2"',
        'sh', $TargetDatabase, $sql
    ) -Capture
    $parts = $flyway.Trim().Split('|')
    if ($parts.Count -ne 2 -or
        [int]$parts[0] -ne [int]$manifest.flywaySuccessfulCount -or
        $parts[1] -ne [string]$manifest.flywayLatestVersion) {
        throw "Flyway restaurado no coincide. Esperado=$($manifest.flywaySuccessfulCount)|$($manifest.flywayLatestVersion), actual=$flyway"
    }

    if ($receiptsPath) {
        $mount = "${backupRoot}:/backup:ro"
        Invoke-Compose -Arguments @(
            'run', '--rm', '--no-deps', '--user', '0:0', '--volume', $mount,
            '--entrypoint', 'sh', $BackendService,
            '-ec', "rm -rf /app/data/receipts/* /app/data/receipts/.[!.]* /app/data/receipts/..?* 2>/dev/null || true; tar -C /app/data -xzf /backup/$($manifest.receiptsArchive.file)"
        ) | Out-Null
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
