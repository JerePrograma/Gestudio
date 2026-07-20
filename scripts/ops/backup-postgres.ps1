[CmdletBinding()]
param(
    [string] $ComposeFile,
    [string] $EnvFile,
    [string] $ProjectName = 'gestudio',
    [string] $OutputDirectory,
    [string] $DatabaseService = 'db',
    [string] $BackendService = 'backend',
    [switch] $SkipReceipts,
    [switch] $StopBackend
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if ([string]::IsNullOrWhiteSpace($ComposeFile)) {
    $ComposeFile = Join-Path $repoRoot 'docker-compose.yml'
}
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $repoRoot 'backups'
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

if (-not (Test-Path -LiteralPath $ComposeFile -PathType Leaf)) {
    throw "No existe Compose: $ComposeFile"
}
Invoke-Native -FilePath 'docker' -Arguments @('version') | Out-Null
Invoke-Native -FilePath 'docker' -Arguments @('compose', 'version') | Out-Null

$dbContainer = Invoke-Compose -Arguments @('ps', '-q', $DatabaseService) -Capture
if ([string]::IsNullOrWhiteSpace($dbContainer)) {
    throw "El servicio '$DatabaseService' no está creado. Levante la base antes de respaldar."
}
if (-not (Test-ContainerRunning -ContainerId $dbContainer)) {
    throw "El contenedor de base no está ejecutándose: $dbContainer"
}

$dbEnvironment = Get-ContainerEnvironment -ContainerId $dbContainer
$database = $dbEnvironment['POSTGRES_DB']
$user = $dbEnvironment['POSTGRES_USER']
if ([string]::IsNullOrWhiteSpace($database) -or [string]::IsNullOrWhiteSpace($user)) {
    throw 'El contenedor no expone POSTGRES_DB y POSTGRES_USER.'
}

$backendContainer = Invoke-Compose -Arguments @('ps', '-q', $BackendService) -Capture
$backendWasRunning = Test-ContainerRunning -ContainerId $backendContainer
if (-not $SkipReceipts -and $backendWasRunning -and -not $StopBackend) {
    throw 'Un backup con recibos requiere consistencia de aplicación. Reejecute con -StopBackend o use -SkipReceipts para un backup sólo de PostgreSQL.'
}

$timestamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$packageName = "gestudio-backup-$timestamp-$([Guid]::NewGuid().ToString('N').Substring(0, 8))"
$root = [IO.Path]::GetFullPath($OutputDirectory)
$packageDirectory = Join-Path $root $packageName
$dumpName = 'database.dump'
$dumpPath = Join-Path $packageDirectory $dumpName
$remoteDump = "/tmp/$packageName.dump"
$receiptsName = if ($SkipReceipts) { $null } else { 'receipts.tar.gz' }
$receiptsPath = if ($receiptsName) { Join-Path $packageDirectory $receiptsName } else { $null }
$backendStopped = $false
$completed = $false

try {
    New-Item -ItemType Directory -Path $packageDirectory -Force | Out-Null

    if ($StopBackend -and $backendWasRunning) {
        Invoke-Compose -Arguments @('stop', $BackendService) | Out-Null
        $backendStopped = $true
    }

    Invoke-Native -FilePath 'docker' -Arguments @(
        'exec', $dbContainer, 'sh', '-ec',
        'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump --format=custom --compress=9 --no-owner --no-privileges --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" --file="$1"',
        'sh', $remoteDump
    ) | Out-Null
    Invoke-Native -FilePath 'docker' -Arguments @('cp', "${dbContainer}:$remoteDump", $dumpPath) | Out-Null

    if (-not (Test-Path -LiteralPath $dumpPath -PathType Leaf) -or (Get-Item $dumpPath).Length -eq 0) {
        throw 'pg_dump no produjo un archivo válido.'
    }

    $sql = 'SELECT count(*)::text || ''|'' || coalesce(max(version::int)::text,'''') FROM flyway_schema_history WHERE success'
    $flyway = Invoke-Native -FilePath 'docker' -Arguments @(
        'exec', $dbContainer, 'sh', '-ec',
        'PGPASSWORD="$POSTGRES_PASSWORD" psql --no-psqlrc --tuples-only --no-align --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" --command="$1"',
        'sh', $sql
    ) -Capture
    $flywayParts = $flyway.Trim().Split('|')
    if ($flywayParts.Count -ne 2) {
        throw "No se pudo leer el historial Flyway: $flyway"
    }

    if ($receiptsPath) {
        $mount = "${packageDirectory}:/backup"
        Invoke-Compose -Arguments @(
            'run', '--rm', '--no-deps', '--user', '0:0', '--volume', $mount,
            '--entrypoint', 'sh', $BackendService,
            '-ec', 'mkdir -p /app/data/receipts && tar -C /app/data -czf /backup/receipts.tar.gz receipts'
        ) | Out-Null
        if (-not (Test-Path -LiteralPath $receiptsPath -PathType Leaf) -or (Get-Item $receiptsPath).Length -eq 0) {
            throw 'No se generó un archivo válido de recibos.'
        }
    }

    $gitHead = $null
    try {
        $gitHead = Invoke-Native -FilePath 'git' -Arguments @('-C', $repoRoot, 'rev-parse', 'HEAD') -Capture
    }
    catch {
        Write-Warning 'No se pudo registrar el HEAD de Git en el manifiesto.'
    }

    $dumpHash = (Get-FileHash -LiteralPath $dumpPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $receiptsHash = if ($receiptsPath) {
        (Get-FileHash -LiteralPath $receiptsPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    else {
        $null
    }

    $manifest = [ordered]@{
        formatVersion = 1
        createdAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        projectName = $ProjectName
        sourceDatabase = $database
        sourceUser = $user
        gitHead = $gitHead
        applicationConsistent = (-not $backendWasRunning) -or $backendStopped
        flywaySuccessfulCount = [int]$flywayParts[0]
        flywayLatestVersion = $flywayParts[1]
        databaseDump = [ordered]@{
            file = $dumpName
            bytes = (Get-Item $dumpPath).Length
            sha256 = $dumpHash
            format = 'PostgreSQL custom'
        }
        receiptsArchive = if ($receiptsPath) {
            [ordered]@{
                file = $receiptsName
                bytes = (Get-Item $receiptsPath).Length
                sha256 = $receiptsHash
            }
        }
        else {
            $null
        }
    }
    $manifestPath = Join-Path $packageDirectory 'manifest.json'
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    $completed = $true
    Write-Host "Backup creado: $packageDirectory" -ForegroundColor Green
    Write-Host "Base: $database | Flyway: $($manifest.flywayLatestVersion) | Dump SHA-256: $dumpHash"
    if ($receiptsPath) { Write-Host "Recibos SHA-256: $receiptsHash" }
    Write-Output $packageDirectory
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
            Write-Warning 'El backup terminó, pero no se pudo reiniciar el backend.'
        }
    }

    if (-not $completed -and (Test-Path -LiteralPath $packageDirectory)) {
        Remove-Item -LiteralPath $packageDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}
