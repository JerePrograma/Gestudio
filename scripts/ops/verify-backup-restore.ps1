[CmdletBinding()]
param(
    [string] $ComposeFile,
    [int] $TimeoutSeconds = 420,
    [switch] $KeepStack
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if ([string]::IsNullOrWhiteSpace($ComposeFile)) {
    $ComposeFile = Join-Path $repoRoot 'docker-compose.yml'
}
$backupScript = Join-Path $PSScriptRoot 'backup-postgres.ps1'
$restoreScript = Join-Path $PSScriptRoot 'restore-postgres.ps1'
$startedAt = Get-Date
$suffix = [Guid]::NewGuid().ToString('N').Substring(0, 10)
$project = "gestudio-backup-verify-$suffix"
$workRoot = Join-Path ([IO.Path]::GetTempPath()) $project
$envFile = Join-Path $workRoot 'verify.env'
$backupRoot = Join-Path $workRoot 'backups'
$sourceDatabase = 'gestudio_backup_verify'
$targetDatabase = 'gestudio_restore_verify'
$postgresUser = 'gestudio_verify'
$rng = [Security.Cryptography.RandomNumberGenerator]::Create()
try {
    $postgresPasswordBytes = New-Object byte[] 24
    $jwtSecretBytes = New-Object byte[] 64
    $rng.GetBytes($postgresPasswordBytes)
    $rng.GetBytes($jwtSecretBytes)
}
finally {
    $rng.Dispose()
}
$postgresPassword = ([BitConverter]::ToString($postgresPasswordBytes) -replace '-', '').ToLowerInvariant()
$jwtSecret = ([BitConverter]::ToString($jwtSecretBytes) -replace '-', '').ToLowerInvariant()
$backendImage = "gestudio-backend:backup-verify-$suffix"
$receiptFile = "backup-verify-$suffix.txt"
$marker = "GESTUDIO_BACKUP_VERIFY_$suffix"
$stackAttempted = $false
$passes = 0
$failures = 0

function Invoke-Native {
    param(
        [Parameter(Mandatory)][string] $FilePath,
        [Parameter(Mandatory)][string[]] $Arguments,
        [switch] $Capture,
        [switch] $IgnoreFailure
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
    if ($code -ne 0 -and -not $IgnoreFailure) {
        $tail = (($text -split "`r?`n") | Select-Object -Last 100) -join "`n"
        throw "El comando $FilePath falló con código ${code}: $tail"
    }
    if ($Capture) { return $text.Trim() }
    if (-not [string]::IsNullOrWhiteSpace($text)) { Write-Host $text }
    return $code
}

function Compose-Prefix {
    return @(
        'compose', '-f', (Resolve-Path -LiteralPath $ComposeFile).Path,
        '--env-file', (Resolve-Path -LiteralPath $envFile).Path,
        '-p', $project
    )
}

function Invoke-Compose {
    param([Parameter(Mandatory)][string[]] $Arguments, [switch] $Capture, [switch] $IgnoreFailure)
    return Invoke-Native -FilePath 'docker' -Arguments ((Compose-Prefix) + $Arguments) -Capture:$Capture -IgnoreFailure:$IgnoreFailure
}

function Get-FreePort {
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $listener.Start()
    try { return ([Net.IPEndPoint]$listener.LocalEndpoint).Port }
    finally { $listener.Stop() }
}

function Get-LocalMigrationManifest {
    $migrationRoot = Join-Path $script:repoRoot 'backend/src/main/resources/db/migration'
    $entries = @(Get-ChildItem -LiteralPath $migrationRoot -Filter 'V*__*.sql' -File | ForEach-Object {
        if ($_.Name -notmatch '^V(?<version>[0-9]+)__.+\.sql$') {
            throw "Nombre de migración Flyway inválido: $($_.Name)"
        }
        [pscustomobject]@{ Version = [int]$matches.version; Script = $_.Name }
    } | Sort-Object Version)

    if ($entries.Count -eq 0) { throw 'No hay migraciones Flyway locales.' }
    if (@($entries.Version | Select-Object -Unique).Count -ne $entries.Count) {
        throw 'Hay versiones Flyway locales duplicadas.'
    }
    for ($index = 0; $index -lt $entries.Count; $index++) {
        if ($entries[$index].Version -ne ($index + 1)) {
            throw 'La cadena Flyway local no es contigua desde V1.'
        }
    }

    return [pscustomobject]@{
        Count = $entries.Count
        LatestVersion = $entries[-1].Version
        Scripts = @($entries.Script)
    }
}

function Wait-ServiceHealthy {
    param([Parameter(Mandatory)][string] $Service)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $containerId = Invoke-Compose -Arguments @('ps', '-a', '-q', $Service) -Capture
        if (-not [string]::IsNullOrWhiteSpace($containerId)) {
            $status = Invoke-Native -FilePath 'docker' -Arguments @(
                'inspect', '--format', '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}',
                $containerId
            ) -Capture
            if ($status -in @('healthy', 'running')) { return $containerId }
            if ($status -in @('unhealthy', 'exited', 'dead')) {
                throw "El servicio '$Service' terminó en estado '$status'."
            }
        }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)

    throw "Timeout esperando que '$Service' quede healthy."
}

function Invoke-Sql {
    param(
        [Parameter(Mandatory)][string] $Database,
        [Parameter(Mandatory)][string] $Sql
    )

    $dbContainer = Invoke-Compose -Arguments @('ps', '-q', 'db') -Capture
    if ([string]::IsNullOrWhiteSpace($dbContainer)) { throw 'No se encontró el contenedor de PostgreSQL.' }
    $sqlBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Sql))
    return Invoke-Native -FilePath 'docker' -Arguments @(
        'exec', $dbContainer, 'sh', '-ec',
        'printf "%s" "$2" | base64 -d | PGPASSWORD="$POSTGRES_PASSWORD" psql --no-psqlrc --tuples-only --no-align --username="$POSTGRES_USER" --dbname="$1" --file=-',
        'sh', $Database, $sqlBase64
    ) -Capture
}

function Assert-Equal {
    param($Actual, $Expected, [Parameter(Mandatory)][string] $Message)
    if ([string]$Actual -ne [string]$Expected) {
        throw "$Message. Esperado='$Expected', actual='$Actual'."
    }
}

function Assert-True {
    param([bool] $Condition, [Parameter(Mandatory)][string] $Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Throws {
    param(
        [Parameter(Mandatory)][scriptblock] $Action,
        [Parameter(Mandatory)][string] $MessageContains,
        [Parameter(Mandatory)][string] $FailureMessage
    )

    $caught = $null
    try { & $Action }
    catch { $caught = $_ }
    if ($null -eq $caught) { throw $FailureMessage }
    if ($caught.Exception.Message -notlike "*$MessageContains*") {
        throw "$FailureMessage. Error inesperado: $($caught.Exception.Message)"
    }
}

function Pass {
    param([Parameter(Mandatory)][string] $Name)
    $script:passes++
    Write-Host "[PASS] $Name" -ForegroundColor Green
}

function Show-Diagnostics {
    try {
        $state = Invoke-Compose -Arguments @('ps', '-a') -Capture -IgnoreFailure
        if ($state) { Write-Host $state }
    }
    catch { }
    try {
        $logs = Invoke-Compose -Arguments @('logs', '--tail', '160', 'db', 'backend') -Capture -IgnoreFailure
        if ($logs) { Write-Host $logs }
    }
    catch { }
}

function Assert-NoProjectResources {
    $containers = Invoke-Native -FilePath 'docker' -Arguments @(
        'ps', '-a', '--filter', "label=com.docker.compose.project=$project", '-q'
    ) -Capture
    $volumes = Invoke-Native -FilePath 'docker' -Arguments @(
        'volume', 'ls', '--filter', "label=com.docker.compose.project=$project", '-q'
    ) -Capture
    $networks = Invoke-Native -FilePath 'docker' -Arguments @(
        'network', 'ls', '--filter', "label=com.docker.compose.project=$project", '-q'
    ) -Capture
    Assert-True -Condition ([string]::IsNullOrWhiteSpace($containers)) -Message 'Quedaron contenedores residuales.'
    Assert-True -Condition ([string]::IsNullOrWhiteSpace($volumes)) -Message 'Quedaron volúmenes residuales.'
    Assert-True -Condition ([string]::IsNullOrWhiteSpace($networks)) -Message 'Quedaron redes residuales.'
}

function Copy-BackupPackage {
    param(
        [Parameter(Mandatory)][string] $Source,
        [Parameter(Mandatory)][string] $Destination
    )

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    foreach ($name in @('database.dump', 'receipts.tar.gz', 'manifest.json')) {
        Copy-Item -LiteralPath (Join-Path $Source $name) -Destination (Join-Path $Destination $name)
    }
}

function Update-ReceiptsManifestIntegrity {
    param([Parameter(Mandatory)][string] $PackageDirectory)

    $manifestPath = Join-Path $PackageDirectory 'manifest.json'
    $archivePath = Join-Path $PackageDirectory 'receipts.tar.gz'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $manifest.receiptsArchive.bytes = (Get-Item -LiteralPath $archivePath).Length
    $manifest.receiptsArchive.sha256 = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
}

function Write-AdversarialReceiptsArchive {
    param(
        [Parameter(Mandatory)][string] $PackageDirectory,
        [Parameter(Mandatory)][ValidateSet('outside', 'symlink', 'hardlink', 'malformed', 'mismatch')][string] $Mode
    )

    $mount = "${PackageDirectory}:/backup"
    $script = @'
set -eu
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT HUP INT TERM
case "$1" in
  outside)
    mkdir -p "$work/outside"
    printf payload > "$work/outside/payload.txt"
    tar -C "$work" -czf /backup/receipts.tar.gz outside
    ;;
  symlink)
    mkdir -p "$work/receipts"
    ln -s /etc/passwd "$work/receipts/escape"
    tar -C "$work" -czf /backup/receipts.tar.gz receipts
    ;;
  hardlink)
    mkdir -p "$work/receipts"
    printf '00000000000000000000000000000000' > "$work/receipts/.gestudio-backup-set-id"
    printf payload > "$work/receipts/original"
    printf payload > "$work/receipts/hardlink"
    printf '%s\n' receipts receipts/.gestudio-backup-set-id receipts/original receipts/hardlink > "$work/list"
    tar --no-recursion -C "$work" -cf "$work/archive.tar" -T "$work/list"

    # BusyBox tar serializa inodes repetidos como archivos regulares. Convertimos
    # de forma determinista el cuarto header ustar al tipo hardlink (1).
    header=2560
    printf 1 | dd of="$work/archive.tar" bs=1 seek="$((header + 156))" conv=notrunc 2>/dev/null
    printf receipts/original | dd of="$work/archive.tar" bs=1 seek="$((header + 157))" conv=notrunc 2>/dev/null
    printf '00000000000\000' | dd of="$work/archive.tar" bs=1 seek="$((header + 124))" conv=notrunc 2>/dev/null
    printf '        ' | dd of="$work/archive.tar" bs=1 seek="$((header + 148))" conv=notrunc 2>/dev/null
    sum="$(dd if="$work/archive.tar" bs=1 skip="$header" count=512 2>/dev/null | od -An -tu1 | awk '{for(i=1;i<=NF;i++)s+=$i} END{print s}')"
    checksum="$(printf '%06o' "$sum")"
    printf "$checksum\000 " | dd of="$work/archive.tar" bs=1 seek="$((header + 148))" conv=notrunc 2>/dev/null
    dd if="$work/archive.tar" of="$work/short.tar" bs=1 count="$((header + 512))" 2>/dev/null
    dd if=/dev/zero bs=512 count=2 2>/dev/null >> "$work/short.tar"
    gzip -c "$work/short.tar" > /backup/receipts.tar.gz
    ;;
  malformed)
    printf 'not-a-tar-gzip' > /backup/receipts.tar.gz
    ;;
  mismatch)
    mkdir -p "$work/receipts"
    printf '00000000000000000000000000000000' > "$work/receipts/.gestudio-backup-set-id"
    printf payload > "$work/receipts/other-backup.pdf"
    tar -C "$work" -czf /backup/receipts.tar.gz receipts
    ;;
esac
'@
    $scriptBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($script))
    Invoke-Compose -Arguments @(
        'run', '--rm', '--no-deps', '--user', '0:0', '--volume', $mount,
        '--entrypoint', 'sh', 'backend', '-ec',
        'printf "%s" "$1" | base64 -d > /tmp/gestudio-adversarial.sh && exec sh /tmp/gestudio-adversarial.sh "$2"',
        'sh', $scriptBase64, $Mode
    ) | Out-Null
    Update-ReceiptsManifestIntegrity -PackageDirectory $PackageDirectory
}

if (-not (Test-Path -LiteralPath $ComposeFile -PathType Leaf)) { throw "No existe Compose: $ComposeFile" }
if (-not (Test-Path -LiteralPath $backupScript -PathType Leaf)) { throw "Falta script de backup: $backupScript" }
if (-not (Test-Path -LiteralPath $restoreScript -PathType Leaf)) { throw "Falta script de restore: $restoreScript" }

$dbPort = Get-FreePort
$backendPort = Get-FreePort
$environment = [ordered]@{
    COMPOSE_PROJECT_NAME = $project
    POSTGRES_DB = $sourceDatabase
    POSTGRES_USER = $postgresUser
    POSTGRES_PASSWORD = $postgresPassword
    POSTGRES_PORT = $dbPort
    BACKEND_PORT = $backendPort
    FRONTEND_PORT = (Get-FreePort)
    BACKEND_IMAGE = $backendImage
    SPRING_PROFILES_ACTIVE = 'dev'
    SPRING_JPA_HIBERNATE_DDL_AUTO = 'validate'
    SPRING_FLYWAY_ENABLED = 'true'
    SPRING_FLYWAY_BASELINE_ON_MIGRATE = 'false'
    APP_SCHEDULING_ENABLED = 'false'
    APP_BOOTSTRAP_SUPERADMIN_ENABLED = 'false'
    APP_LOCAL_ADMIN_PASSWORD_RESET_ENABLED = 'false'
    APP_LOCAL_ADMIN_PASSWORD_RESET_USERNAME = ''
    APP_LOCAL_ADMIN_PASSWORD_RESET_PASSWORD = ''
    JWT_SECRET = $jwtSecret
    JWT_ISSUER = 'gestudio-backup-verify'
    APP_TIME_ZONE = 'America/Argentina/Buenos_Aires'
    APP_CORS_ALLOWED_ORIGINS = "http://127.0.0.1:$backendPort"
    APP_JERE_PLATFORM_STUDENT_EXPORT_ENABLED = 'false'
}
$previousProcessEnvironment = @{}

try {
    $migrationManifest = Get-LocalMigrationManifest
    foreach ($entry in $environment.GetEnumerator()) {
        $previousProcessEnvironment[$entry.Key] = [Environment]::GetEnvironmentVariable($entry.Key, 'Process')
        [Environment]::SetEnvironmentVariable($entry.Key, [string]$entry.Value, 'Process')
    }
    New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    $environment.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" } |
        Set-Content -LiteralPath $envFile -Encoding ASCII

    Invoke-Native -FilePath 'docker' -Arguments @('info', '--format', '{{.ServerVersion}}') | Out-Null
    Invoke-Native -FilePath 'docker' -Arguments @('compose', 'version') | Out-Null
    Pass 'Docker disponible'

    Push-Location $repoRoot
    try {
        $stackAttempted = $true
        Invoke-Compose -Arguments @('up', '-d', '--build', 'db', 'backend') | Out-Null
        $dbContainer = Wait-ServiceHealthy -Service 'db'
        $backendContainer = Wait-ServiceHealthy -Service 'backend'
        Pass 'Stack descartable healthy'

        $flyway = Invoke-Sql -Database $sourceDatabase -Sql "SELECT count(*)::text || '|' || max(version::int)::text FROM flyway_schema_history WHERE success"
        Assert-Equal -Actual $flyway.Trim() -Expected "$($migrationManifest.Count)|$($migrationManifest.LatestVersion)" -Message 'Flyway origen inválido'
        Pass "Flyway V1-V$($migrationManifest.LatestVersion) en origen"

        $studentResult = Invoke-Sql -Database $sourceDatabase -Sql "INSERT INTO alumnos(nombre, apellido, fecha_incorporacion, activo) VALUES ('Backup', '$marker', DATE '2026-07-20', true) RETURNING id"
        $studentId = (($studentResult -split "`r?`n") | Select-Object -First 1).Trim()
        Assert-True -Condition ($studentId -match '^[0-9]+$') -Message "La inserción no devolvió un ID numérico: $studentResult"
        Invoke-Native -FilePath 'docker' -Arguments @(
            'exec', $backendContainer, 'sh', '-ec',
            'printf "%s" "$1" > "/app/data/receipts/$2"',
            'sh', $marker, $receiptFile
        ) | Out-Null
        Pass 'Fixture sintética creada'

        $backupOutput = @(& $backupScript `
            -ComposeFile $ComposeFile `
            -EnvFile $envFile `
            -ProjectName $project `
            -OutputDirectory $backupRoot `
            -StopBackend)
        $backupDirectory = [string]$backupOutput[-1]
        Assert-True -Condition (Test-Path -LiteralPath $backupDirectory -PathType Container) -Message 'El backup no devolvió un paquete válido.'
        Wait-ServiceHealthy -Service 'backend' | Out-Null

        $manifestPath = Join-Path $backupDirectory 'manifest.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        Assert-Equal -Actual $manifest.formatVersion -Expected 2 -Message 'Formato de manifiesto inválido'
        Assert-True -Condition ([string]$manifest.backupSetId -cmatch '^[a-f0-9]{32}$') -Message 'backupSetId inválido'
        Assert-Equal -Actual $manifest.flywayLatestVersion -Expected $migrationManifest.LatestVersion -Message 'Flyway del manifiesto inválido'
        Assert-Equal -Actual $manifest.flywaySuccessfulCount -Expected $migrationManifest.Count -Message 'Cantidad Flyway del manifiesto inválida'
        Assert-Equal -Actual $manifest.applicationConsistent -Expected $true -Message 'El backup no quedó marcado como consistente'
        Assert-True -Condition (-not [string]::IsNullOrWhiteSpace($manifest.gitHead)) -Message 'El manifiesto no registró Git HEAD.'
        Pass 'Backup y manifiesto verificados'

        $incompletePackage = Join-Path $workRoot 'adversarial-incomplete-manifest'
        Copy-BackupPackage -Source $backupDirectory -Destination $incompletePackage
        $incompleteManifestPath = Join-Path $incompletePackage 'manifest.json'
        $incompleteManifest = Get-Content -LiteralPath $incompleteManifestPath -Raw | ConvertFrom-Json
        $incompleteManifest.PSObject.Properties.Remove('databaseDump')
        $incompleteManifest | ConvertTo-Json -Depth 6 |
            Set-Content -LiteralPath $incompleteManifestPath -Encoding UTF8
        Assert-Throws -Action {
            & $restoreScript -BackupDirectory $incompletePackage -TargetDatabase $targetDatabase `
                -ComposeFile $ComposeFile -EnvFile $envFile -ProjectName $project `
                -ConfirmDestructiveRestore
        } -MessageContains 'manifiesto está incompleto' -FailureMessage 'El manifiesto incompleto no fue rechazado'

        $invalidHashPackage = Join-Path $workRoot 'adversarial-invalid-hash'
        Copy-BackupPackage -Source $backupDirectory -Destination $invalidHashPackage
        $invalidHashManifestPath = Join-Path $invalidHashPackage 'manifest.json'
        $invalidHashManifest = Get-Content -LiteralPath $invalidHashManifestPath -Raw | ConvertFrom-Json
        $invalidHashManifest.databaseDump.sha256 = (('0' * 64) -join '')
        $invalidHashManifest | ConvertTo-Json -Depth 6 |
            Set-Content -LiteralPath $invalidHashManifestPath -Encoding UTF8
        Assert-Throws -Action {
            & $restoreScript -BackupDirectory $invalidHashPackage -TargetDatabase $targetDatabase `
                -ComposeFile $ComposeFile -EnvFile $envFile -ProjectName $project `
                -ConfirmDestructiveRestore
        } -MessageContains 'SHA-256 de dump' -FailureMessage 'El hash incorrecto del manifiesto no fue rechazado'

        $alteredDumpPackage = Join-Path $workRoot 'adversarial-altered-dump'
        Copy-BackupPackage -Source $backupDirectory -Destination $alteredDumpPackage
        $alteredDumpPath = Join-Path $alteredDumpPackage 'database.dump'
        $stream = [IO.File]::Open($alteredDumpPath, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $stream.WriteByte(0) }
        finally { $stream.Dispose() }
        $alteredDumpManifestPath = Join-Path $alteredDumpPackage 'manifest.json'
        $alteredDumpManifest = Get-Content -LiteralPath $alteredDumpManifestPath -Raw | ConvertFrom-Json
        $alteredDumpManifest.databaseDump.bytes = (Get-Item -LiteralPath $alteredDumpPath).Length
        $alteredDumpManifest | ConvertTo-Json -Depth 6 |
            Set-Content -LiteralPath $alteredDumpManifestPath -Encoding UTF8
        Assert-Throws -Action {
            & $restoreScript -BackupDirectory $alteredDumpPackage -TargetDatabase $targetDatabase `
                -ComposeFile $ComposeFile -EnvFile $envFile -ProjectName $project `
                -ConfirmDestructiveRestore
        } -MessageContains 'SHA-256 de dump' -FailureMessage 'El dump alterado no fue rechazado'

        $missingDumpPackage = Join-Path $workRoot 'adversarial-missing-dump'
        Copy-BackupPackage -Source $backupDirectory -Destination $missingDumpPackage
        Remove-Item -LiteralPath (Join-Path $missingDumpPackage 'database.dump') -Force
        Assert-Throws -Action {
            & $restoreScript -BackupDirectory $missingDumpPackage -TargetDatabase $targetDatabase `
                -ComposeFile $ComposeFile -EnvFile $envFile -ProjectName $project `
                -ConfirmDestructiveRestore
        } -MessageContains 'Falta dump' -FailureMessage 'El paquete sin dump no fue rechazado'

        $missingReceiptsPackage = Join-Path $workRoot 'adversarial-missing-receipts'
        Copy-BackupPackage -Source $backupDirectory -Destination $missingReceiptsPackage
        Remove-Item -LiteralPath (Join-Path $missingReceiptsPackage 'receipts.tar.gz') -Force
        Assert-Throws -Action {
            & $restoreScript -BackupDirectory $missingReceiptsPackage -TargetDatabase $sourceDatabase `
                -ComposeFile $ComposeFile -EnvFile $envFile -ProjectName $project `
                -ConfirmDestructiveRestore -AllowSourceDatabaseRestore `
                -RestoreReceipts -ConfirmReceiptsOverwrite -StopBackend
        } -MessageContains 'Falta archivo de recibos' -FailureMessage 'El paquete sin recibos no fue rechazado'

        $partialPackage = Join-Path $workRoot 'adversarial-partial-backup'
        Copy-BackupPackage -Source $backupDirectory -Destination $partialPackage
        $partialManifestPath = Join-Path $partialPackage 'manifest.json'
        $partialManifest = Get-Content -LiteralPath $partialManifestPath -Raw | ConvertFrom-Json
        $partialManifest.applicationConsistent = $false
        $partialManifest | ConvertTo-Json -Depth 6 |
            Set-Content -LiteralPath $partialManifestPath -Encoding UTF8
        Assert-Throws -Action {
            & $restoreScript -BackupDirectory $partialPackage -TargetDatabase $sourceDatabase `
                -ComposeFile $ComposeFile -EnvFile $envFile -ProjectName $project `
                -ConfirmDestructiveRestore -AllowSourceDatabaseRestore `
                -RestoreReceipts -ConfirmReceiptsOverwrite -StopBackend
        } -MessageContains 'no está marcado como consistente' -FailureMessage 'El backup parcial no fue rechazado'
        Pass 'Manifiesto incompleto, hashes, archivos faltantes y backup parcial rechazados'

        $pathTraversalPackage = Join-Path $workRoot 'adversarial-path'
        Copy-BackupPackage -Source $backupDirectory -Destination $pathTraversalPackage
        $pathTraversalManifestPath = Join-Path $pathTraversalPackage 'manifest.json'
        $pathTraversalManifest = Get-Content -LiteralPath $pathTraversalManifestPath -Raw | ConvertFrom-Json
        $pathTraversalManifest.databaseDump.file = '../database.dump'
        $pathTraversalManifest | ConvertTo-Json -Depth 6 |
            Set-Content -LiteralPath $pathTraversalManifestPath -Encoding UTF8
        Assert-Throws -Action {
            & $restoreScript -BackupDirectory $pathTraversalPackage -TargetDatabase $targetDatabase `
                -ComposeFile $ComposeFile -EnvFile $envFile -ProjectName $project `
                -ConfirmDestructiveRestore
        } -MessageContains 'archivo canónico' -FailureMessage 'El manifiesto con path traversal no fue rechazado'

        $absolutePathPackage = Join-Path $workRoot 'adversarial-absolute-path'
        Copy-BackupPackage -Source $backupDirectory -Destination $absolutePathPackage
        $absolutePathManifestPath = Join-Path $absolutePathPackage 'manifest.json'
        $absolutePathManifest = Get-Content -LiteralPath $absolutePathManifestPath -Raw | ConvertFrom-Json
        $absolutePathManifest.databaseDump.file = [IO.Path]::GetFullPath((Join-Path $absolutePathPackage 'database.dump'))
        $absolutePathManifest | ConvertTo-Json -Depth 6 |
            Set-Content -LiteralPath $absolutePathManifestPath -Encoding UTF8
        Assert-Throws -Action {
            & $restoreScript -BackupDirectory $absolutePathPackage -TargetDatabase $targetDatabase `
                -ComposeFile $ComposeFile -EnvFile $envFile -ProjectName $project `
                -ConfirmDestructiveRestore
        } -MessageContains 'archivo canónico' -FailureMessage 'La ruta absoluta del manifiesto no fue rechazada'

        $injectionPackage = Join-Path $workRoot 'adversarial-injection'
        Copy-BackupPackage -Source $backupDirectory -Destination $injectionPackage
        $injectionManifestPath = Join-Path $injectionPackage 'manifest.json'
        $injectionManifest = Get-Content -LiteralPath $injectionManifestPath -Raw | ConvertFrom-Json
        $injectionManifest.receiptsArchive.file = 'receipts.tar.gz; touch /app/data/receipts/restore-injection'
        $injectionManifest | ConvertTo-Json -Depth 6 |
            Set-Content -LiteralPath $injectionManifestPath -Encoding UTF8
        Assert-Throws -Action {
            & $restoreScript -BackupDirectory $injectionPackage -TargetDatabase $targetDatabase `
                -ComposeFile $ComposeFile -EnvFile $envFile -ProjectName $project `
                -ConfirmDestructiveRestore -RestoreReceipts -ConfirmReceiptsOverwrite -StopBackend
        } -MessageContains 'archivo canónico' -FailureMessage 'El nombre con metacaracteres no fue rechazado'
        Invoke-Native -FilePath 'docker' -Arguments @(
            'exec', $backendContainer, 'sh', '-ec', 'test ! -e "$1"',
            'sh', '/app/data/receipts/restore-injection'
        ) | Out-Null

        $outsidePackage = Join-Path $workRoot 'adversarial-tar-outside'
        Copy-BackupPackage -Source $backupDirectory -Destination $outsidePackage
        Write-AdversarialReceiptsArchive -PackageDirectory $outsidePackage -Mode outside
        Assert-Throws -Action {
            & $restoreScript -BackupDirectory $outsidePackage -TargetDatabase $sourceDatabase `
                -ComposeFile $ComposeFile -EnvFile $envFile -ProjectName $project `
                -ConfirmDestructiveRestore -AllowSourceDatabaseRestore `
                -RestoreReceipts -ConfirmReceiptsOverwrite -StopBackend
        } -MessageContains 'miembro fuera de receipts/' `
          -FailureMessage 'El tar con miembro fuera de receipts/ no fue rechazado'

        $symlinkPackage = Join-Path $workRoot 'adversarial-tar-symlink'
        Copy-BackupPackage -Source $backupDirectory -Destination $symlinkPackage
        Write-AdversarialReceiptsArchive -PackageDirectory $symlinkPackage -Mode symlink
        Assert-Throws -Action {
            & $restoreScript -BackupDirectory $symlinkPackage -TargetDatabase $sourceDatabase `
                -ComposeFile $ComposeFile -EnvFile $envFile -ProjectName $project `
                -ConfirmDestructiveRestore -AllowSourceDatabaseRestore `
                -RestoreReceipts -ConfirmReceiptsOverwrite -StopBackend
        } -MessageContains 'tipo no permitido' `
          -FailureMessage 'El tar con symlink no fue rechazado'

        $hardlinkPackage = Join-Path $workRoot 'adversarial-tar-hardlink'
        Copy-BackupPackage -Source $backupDirectory -Destination $hardlinkPackage
        Write-AdversarialReceiptsArchive -PackageDirectory $hardlinkPackage -Mode hardlink
        Assert-Throws -Action {
            & $restoreScript -BackupDirectory $hardlinkPackage -TargetDatabase $sourceDatabase `
                -ComposeFile $ComposeFile -EnvFile $envFile -ProjectName $project `
                -ConfirmDestructiveRestore -AllowSourceDatabaseRestore `
                -RestoreReceipts -ConfirmReceiptsOverwrite -StopBackend
        } -MessageContains 'tipo no permitido' -FailureMessage 'El tar con hardlink no fue rechazado'

        $malformedPackage = Join-Path $workRoot 'adversarial-tar-malformed'
        Copy-BackupPackage -Source $backupDirectory -Destination $malformedPackage
        Write-AdversarialReceiptsArchive -PackageDirectory $malformedPackage -Mode malformed
        Assert-Throws -Action {
            & $restoreScript -BackupDirectory $malformedPackage -TargetDatabase $sourceDatabase `
                -ComposeFile $ComposeFile -EnvFile $envFile -ProjectName $project `
                -ConfirmDestructiveRestore -AllowSourceDatabaseRestore `
                -RestoreReceipts -ConfirmReceiptsOverwrite -StopBackend
        } -MessageContains 'tar' -FailureMessage 'El archivo tar malformado no fue rechazado'

        $mismatchedPackage = Join-Path $workRoot 'adversarial-receipts-mismatch'
        Copy-BackupPackage -Source $backupDirectory -Destination $mismatchedPackage
        Write-AdversarialReceiptsArchive -PackageDirectory $mismatchedPackage -Mode mismatch
        Assert-Throws -Action {
            & $restoreScript -BackupDirectory $mismatchedPackage -TargetDatabase $sourceDatabase `
                -ComposeFile $ComposeFile -EnvFile $envFile -ProjectName $project `
                -ConfirmDestructiveRestore -AllowSourceDatabaseRestore `
                -RestoreReceipts -ConfirmReceiptsOverwrite -StopBackend
        } -MessageContains 'otro conjunto de backup' `
          -FailureMessage 'El archivo de recibos perteneciente a otro backup no fue rechazado'
        Assert-Equal -Actual (Invoke-Sql -Database $sourceDatabase -Sql "SELECT count(*) FROM alumnos WHERE apellido = '$marker'").Trim() -Expected 1 -Message 'Una validación adversarial alteró la base origen'
        Pass 'Traversal, rutas absolutas, miembros externos, links y tar malformado rechazados'
        Pass 'Archivo de recibos de otro conjunto rechazado antes de mutar datos'

        Invoke-Sql -Database $sourceDatabase -Sql "DELETE FROM alumnos WHERE id = $studentId" | Out-Null
        $backendContainer = Wait-ServiceHealthy -Service 'backend'
        Invoke-Native -FilePath 'docker' -Arguments @('exec', $backendContainer, 'rm', '-f', "/app/data/receipts/$receiptFile") | Out-Null
        Assert-Equal -Actual (Invoke-Sql -Database $sourceDatabase -Sql "SELECT count(*) FROM alumnos WHERE apellido = '$marker'").Trim() -Expected 0 -Message 'No se mutó la base origen'
        Pass 'Origen mutado después del backup'

        Assert-Throws -Action {
            & $restoreScript -BackupDirectory $backupDirectory -TargetDatabase $targetDatabase `
                -ComposeFile $ComposeFile -EnvFile $envFile -ProjectName $project
        } -MessageContains 'ConfirmDestructiveRestore' -FailureMessage 'Restore sin confirmación no fue rechazado'

        Assert-Throws -Action {
            & $restoreScript -BackupDirectory $backupDirectory -TargetDatabase $sourceDatabase `
                -ComposeFile $ComposeFile -EnvFile $envFile -ProjectName $project `
                -ConfirmDestructiveRestore
        } -MessageContains 'base origen' -FailureMessage 'Restore sobre origen sin autorización no fue rechazado'

        Assert-Throws -Action {
            & $restoreScript -BackupDirectory $backupDirectory -TargetDatabase $targetDatabase `
                -ComposeFile $ComposeFile -EnvFile $envFile -ProjectName $project `
                -ConfirmDestructiveRestore -RestoreReceipts -ConfirmReceiptsOverwrite -StopBackend
        } -MessageContains 'base alternativa' -FailureMessage 'Restore de recibos sobre base alternativa no fue rechazado'
        Pass 'Guardas destructivas y consistencia DB-recibos verificadas'

        & $restoreScript -BackupDirectory $backupDirectory -TargetDatabase $targetDatabase `
            -ComposeFile $ComposeFile -EnvFile $envFile -ProjectName $project `
            -ConfirmDestructiveRestore
        & $restoreScript -BackupDirectory $backupDirectory -TargetDatabase $sourceDatabase `
            -ComposeFile $ComposeFile -EnvFile $envFile -ProjectName $project `
            -ConfirmDestructiveRestore -AllowSourceDatabaseRestore `
            -RestoreReceipts -ConfirmReceiptsOverwrite -StopBackend
        $backendContainer = Wait-ServiceHealthy -Service 'backend'

        Assert-Equal -Actual (Invoke-Sql -Database $targetDatabase -Sql "SELECT count(*) FROM alumnos WHERE apellido = '$marker'").Trim() -Expected 1 -Message 'El alumno no fue restaurado en destino'
        Assert-Equal -Actual (Invoke-Sql -Database $sourceDatabase -Sql "SELECT count(*) FROM alumnos WHERE apellido = '$marker'").Trim() -Expected 1 -Message 'La restauración consistente no repuso la base activa'
        Assert-Equal -Actual (Invoke-Sql -Database $targetDatabase -Sql "SELECT count(*)::text || '|' || max(version::int)::text FROM flyway_schema_history WHERE success").Trim() -Expected "$($migrationManifest.Count)|$($migrationManifest.LatestVersion)" -Message 'Flyway destino inválido'
        Assert-Equal -Actual (Invoke-Sql -Database $targetDatabase -Sql "SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_name IN ('jere_platform_student_export_snapshots','jere_platform_student_export_pages')").Trim() -Expected 2 -Message 'Las tablas V7 no fueron restauradas'
        $receipt = Invoke-Native -FilePath 'docker' -Arguments @('exec', $backendContainer, 'cat', "/app/data/receipts/$receiptFile") -Capture
        Assert-Equal -Actual $receipt -Expected $marker -Message 'El recibo no fue restaurado'
        Invoke-Native -FilePath 'docker' -Arguments @(
            'exec', $backendContainer, 'test', '!', '-e', '/app/data/receipts/.gestudio-backup-set-id'
        ) | Out-Null
        Pass 'Restore PostgreSQL y recibos verificado'
    }
    finally {
        Pop-Location
    }
}
catch {
    $failures++
    Write-Host "[FAIL] $($_.Exception.Message)" -ForegroundColor Red
    if ($stackAttempted) { Show-Diagnostics }
}
finally {
    if ($KeepStack) {
        Write-Host "[INFO] Stack conservado: $project"
        Write-Host "[INFO] Env temporal: $envFile"
    }
    else {
        if ($stackAttempted -and (Test-Path -LiteralPath $envFile)) {
            try { Invoke-Compose -Arguments @('down', '--volumes', '--remove-orphans') -IgnoreFailure | Out-Null }
            catch { $failures++; Write-Host "[FAIL] Cleanup Compose: $($_.Exception.Message)" -ForegroundColor Red }
        }
        try { Invoke-Native -FilePath 'docker' -Arguments @('image', 'rm', '-f', $backendImage) -IgnoreFailure | Out-Null } catch { }
        try { Assert-NoProjectResources; Pass 'Limpieza Docker' }
        catch { $failures++; Write-Host "[FAIL] $($_.Exception.Message)" -ForegroundColor Red }
        if (Test-Path -LiteralPath $workRoot) {
            Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    foreach ($entry in $previousProcessEnvironment.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process')
    }
}

$duration = (Get-Date) - $startedAt
Write-Host ''
Write-Host "Duración total: $($duration.ToString('hh\:mm\:ss'))"
Write-Host "Pasos aprobados: $passes"
Write-Host "Fallos: $failures"
Write-Host "Resultado global: $(if ($failures -eq 0) { 'PASS' } else { 'FAIL' })"

if ($failures -ne 0) { exit 1 }
