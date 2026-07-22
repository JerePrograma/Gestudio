[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $TargetBackendImage,
    [string] $ComposeFile,
    [string] $EnvFile,
    [string] $ProjectName = 'gestudio',
    [string] $DatabaseService = 'db',
    [string] $BackendService = 'backend',
    [string] $BackupOutputDirectory,
    [string] $ExpectedCurrentImage,
    [int] $TimeoutSeconds = 240,
    [switch] $SkipBackup,
    [switch] $ConfirmRollback
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if ([string]::IsNullOrWhiteSpace($ComposeFile)) {
    $ComposeFile = Join-Path $repoRoot 'docker-compose.yml'
}
if ([string]::IsNullOrWhiteSpace($BackupOutputDirectory)) {
    $BackupOutputDirectory = Join-Path $repoRoot 'backups/rollback'
}
$backupScript = Join-Path $PSScriptRoot 'backup-postgres.ps1'
$readinessHealthContract = 'actuator-readiness-v1'
$legacyHealthContract = 'legacy-api-401-v1'

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
    param([Parameter(Mandatory)][string[]] $Arguments, [switch] $Capture, [switch] $IgnoreFailure)
    return Invoke-Native -FilePath 'docker' -Arguments ((Compose-Prefix) + $Arguments) -Capture:$Capture -IgnoreFailure:$IgnoreFailure
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

function Get-ImageFlywayLatest {
    param([Parameter(Mandatory)][string] $Image)

    Invoke-Native -FilePath 'docker' -Arguments @('image', 'inspect', $Image) | Out-Null
    $value = Invoke-Native -FilePath 'docker' -Arguments @(
        'run', '--rm', '--entrypoint', 'cat', $Image, '/app/build-metadata/flyway-latest'
    ) -Capture
    if ($value -notmatch '^[0-9]+$') {
        throw "La imagen '$Image' no declara una versión Flyway válida en /app/build-metadata/flyway-latest."
    }
    return [int]$value
}

function Get-ImageHealthContract {
    param([Parameter(Mandatory)][string] $Image)

    $value = Invoke-Native -FilePath 'docker' -Arguments @(
        'run', '--rm', '--entrypoint', 'sh', $Image, '-ec',
        'if [ -f /app/build-metadata/health-contract ]; then cat /app/build-metadata/health-contract; else printf "__MISSING__"; fi'
    ) -Capture

    if ($value -eq '__MISSING__') {
        Write-Warning "La imagen '$Image' es anterior a la metadata de health. Se usará el contrato compatible '$legacyHealthContract'."
        return $legacyHealthContract
    }
    if ($value -notin @($readinessHealthContract, $legacyHealthContract)) {
        throw "La imagen '$Image' declara un contrato de health no soportado: '$value'."
    }
    return $value
}

function Get-DatabaseFlywayLatest {
    param([Parameter(Mandatory)][string] $DbContainer)

    $sql = 'SELECT coalesce(max(version::int),0) FROM flyway_schema_history WHERE success'
    $sqlBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($sql))
    $value = Invoke-Native -FilePath 'docker' -Arguments @(
        'exec', $DbContainer, 'sh', '-ec',
        'printf "%s" "$1" | base64 -d | PGPASSWORD="$POSTGRES_PASSWORD" psql --no-psqlrc --tuples-only --no-align --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" --file=-',
        'sh', $sqlBase64
    ) -Capture
    if ($value -notmatch '^[0-9]+$') {
        throw "No se pudo determinar la versión Flyway de la base: $value"
    }
    return [int]$value
}

function Wait-BackendHealthy {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $containerId = Invoke-Compose -Arguments @('ps', '-q', $BackendService) -Capture
        if (-not [string]::IsNullOrWhiteSpace($containerId)) {
            $status = Invoke-Native -FilePath 'docker' -Arguments @(
                'inspect', '--format', '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}',
                $containerId
            ) -Capture
            if ($status -eq 'healthy') { return $containerId }
            if ($status -in @('unhealthy', 'exited', 'dead')) {
                $logs = Invoke-Compose -Arguments @('logs', '--tail', '160', $BackendService) -Capture -IgnoreFailure
                throw "El backend terminó en estado '$status'. Logs: $logs"
            }
        }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)

    $logs = Invoke-Compose -Arguments @('logs', '--tail', '160', $BackendService) -Capture -IgnoreFailure
    throw "Timeout esperando backend healthy. Logs: $logs"
}

function Switch-BackendImage {
    param(
        [Parameter(Mandatory)][string] $Image,
        [Parameter(Mandatory)][string] $HealthContract
    )

    $hadImageOverride = Test-Path Env:BACKEND_IMAGE
    $previousImageOverride = if ($hadImageOverride) { $env:BACKEND_IMAGE } else { $null }
    $hadHealthOverride = Test-Path Env:BACKEND_HEALTHCHECK_MODE
    $previousHealthOverride = if ($hadHealthOverride) { $env:BACKEND_HEALTHCHECK_MODE } else { $null }
    try {
        $env:BACKEND_IMAGE = $Image
        $env:BACKEND_HEALTHCHECK_MODE = $HealthContract
        Invoke-Compose -Arguments @('up', '-d', '--no-deps', '--force-recreate', $BackendService) | Out-Null
        $containerId = Wait-BackendHealthy
        $actual = Invoke-Native -FilePath 'docker' -Arguments @(
            'inspect', '--format', '{{.Config.Image}}', $containerId
        ) -Capture
        if ($actual -ne $Image) {
            throw "Compose inició '$actual' en lugar de '$Image'."
        }
        $actualHealthContract = Invoke-Native -FilePath 'docker' -Arguments @(
            'inspect', '--format', '{{range .Config.Env}}{{println .}}{{end}}', $containerId
        ) -Capture
        if ($actualHealthContract -notmatch "(?m)^BACKEND_HEALTHCHECK_MODE=$([regex]::Escape($HealthContract))$") {
            throw "El contenedor no recibió el contrato de health '$HealthContract'."
        }
        return $containerId
    }
    finally {
        if ($hadImageOverride) { $env:BACKEND_IMAGE = $previousImageOverride }
        else { Remove-Item Env:BACKEND_IMAGE -ErrorAction SilentlyContinue }
        if ($hadHealthOverride) { $env:BACKEND_HEALTHCHECK_MODE = $previousHealthOverride }
        else { Remove-Item Env:BACKEND_HEALTHCHECK_MODE -ErrorAction SilentlyContinue }
    }
}

if (-not $ConfirmRollback) {
    throw 'El cambio de artefacto requiere -ConfirmRollback.'
}
if (-not (Test-Path -LiteralPath $ComposeFile -PathType Leaf)) {
    throw "No existe Compose: $ComposeFile"
}
if (-not $SkipBackup -and -not (Test-Path -LiteralPath $backupScript -PathType Leaf)) {
    throw "Falta el script de backup requerido: $backupScript"
}

Invoke-Native -FilePath 'docker' -Arguments @('version') | Out-Null
Invoke-Native -FilePath 'docker' -Arguments @('compose', 'version') | Out-Null

$dbContainer = Invoke-Compose -Arguments @('ps', '-q', $DatabaseService) -Capture
$backendContainer = Invoke-Compose -Arguments @('ps', '-q', $BackendService) -Capture
if ([string]::IsNullOrWhiteSpace($dbContainer) -or [string]::IsNullOrWhiteSpace($backendContainer)) {
    throw 'La base y el backend deben estar creados antes del rollback.'
}

$dbEnvironment = Get-ContainerEnvironment -ContainerId $dbContainer
if ([string]::IsNullOrWhiteSpace($dbEnvironment['POSTGRES_DB']) -or
    [string]::IsNullOrWhiteSpace($dbEnvironment['POSTGRES_USER'])) {
    throw 'El contenedor de base no expone POSTGRES_DB y POSTGRES_USER.'
}

$previousImage = Invoke-Native -FilePath 'docker' -Arguments @(
    'inspect', '--format', '{{.Config.Image}}', $backendContainer
) -Capture
if (-not [string]::IsNullOrWhiteSpace($ExpectedCurrentImage) -and $previousImage -ne $ExpectedCurrentImage) {
    throw "La imagen actual cambió. Esperada='$ExpectedCurrentImage', actual='$previousImage'."
}
if ($previousImage -eq $TargetBackendImage) {
    throw "La imagen objetivo ya está activa: $TargetBackendImage"
}

$databaseFlyway = Get-DatabaseFlywayLatest -DbContainer $dbContainer
$targetFlyway = Get-ImageFlywayLatest -Image $TargetBackendImage
if ($targetFlyway -ne $databaseFlyway) {
    throw "Rollback incompatible: la base está en Flyway V$databaseFlyway y la imagen objetivo declara V$targetFlyway. El artefacto debe contener exactamente todas las migraciones ya aplicadas."
}

$previousHealthContract = Get-ImageHealthContract -Image $previousImage
$targetHealthContract = Get-ImageHealthContract -Image $TargetBackendImage

$backupDirectory = $null
if (-not $SkipBackup) {
    New-Item -ItemType Directory -Path $BackupOutputDirectory -Force | Out-Null
    $backupOutput = @(& $backupScript `
        -ComposeFile $ComposeFile `
        -EnvFile $EnvFile `
        -ProjectName $ProjectName `
        -OutputDirectory $BackupOutputDirectory `
        -StopBackend)
    $backupDirectory = [string]$backupOutput[-1]
    if (-not (Test-Path -LiteralPath $backupDirectory -PathType Container)) {
        throw 'El backup previo no devolvió un paquete válido.'
    }
    Wait-BackendHealthy | Out-Null
}

Write-Host "Imagen actual: $previousImage"
Write-Host "Imagen objetivo: $TargetBackendImage"
Write-Host "Flyway base/objetivo: V$databaseFlyway"
Write-Host "Health actual/objetivo: $previousHealthContract -> $targetHealthContract"
if ($backupDirectory) { Write-Host "Backup previo: $backupDirectory" }

try {
    Switch-BackendImage -Image $TargetBackendImage -HealthContract $targetHealthContract | Out-Null
}
catch {
    $rollbackFailure = $_
    Write-Warning "La imagen objetivo no quedó operativa. Se intentará recuperar '$previousImage'."
    try {
        Switch-BackendImage -Image $previousImage -HealthContract $previousHealthContract | Out-Null
    }
    catch {
        throw "Falló el rollback y también la recuperación automática. Rollback: $($rollbackFailure.Exception.Message). Recuperación: $($_.Exception.Message)"
    }
    throw "La imagen objetivo falló y se recuperó la imagen anterior. Error original: $($rollbackFailure.Exception.Message)"
}

Write-Host "Rollback de aplicación completado: $previousImage -> $TargetBackendImage" -ForegroundColor Green
Write-Output ([ordered]@{
    previousImage = $previousImage
    previousHealthContract = $previousHealthContract
    targetImage = $TargetBackendImage
    targetHealthContract = $targetHealthContract
    flywayVersion = $databaseFlyway
    backupDirectory = $backupDirectory
} | ConvertTo-Json -Compress)
