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
$postgresPassword = [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(24)).ToLowerInvariant()
$jwtSecret = [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(64)).ToLowerInvariant()
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

function Wait-ServiceHealthy {
    param([Parameter(Mandatory)][string] $Service)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $containerId = Invoke-Compose -Arguments @('ps', '-q', $Service) -Capture
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
    return Invoke-Native -FilePath 'docker' -Arguments @(
        'exec', $dbContainer, 'sh', '-ec',
        'PGPASSWORD="$POSTGRES_PASSWORD" psql --no-psqlrc --tuples-only --no-align --username="$POSTGRES_USER" --dbname="$1" --command="$2"',
        'sh', $Database, $Sql
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
    APP_BOOTSTRAP_ADMIN_ENABLED = 'false'
    JWT_SECRET = $jwtSecret
    JWT_ISSUER = 'gestudio-backup-verify'
    APP_TIME_ZONE = 'America/Argentina/Buenos_Aires'
    APP_CORS_ALLOWED_ORIGINS = "http://127.0.0.1:$backendPort"
    APP_JERE_PLATFORM_STUDENT_EXPORT_ENABLED = 'false'
}

try {
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
        Assert-Equal -Actual $flyway.Trim() -Expected '7|7' -Message 'Flyway origen inválido'
        Pass 'Flyway V1-V7 en origen'

        $studentId = Invoke-Sql -Database $sourceDatabase -Sql "INSERT INTO alumnos(nombre, apellido, fecha_incorporacion, activo) VALUES ('Backup', '$marker', DATE '2026-07-20', true) RETURNING id"
        Assert-True -Condition (-not [string]::IsNullOrWhiteSpace($studentId)) -Message 'No se insertó el alumno sintético.'
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
        Assert-Equal -Actual $manifest.formatVersion -Expected 1 -Message 'Formato de manifiesto inválido'
        Assert-Equal -Actual $manifest.flywayLatestVersion -Expected 7 -Message 'Flyway del manifiesto inválido'
        Assert-Equal -Actual $manifest.flywaySuccessfulCount -Expected 7 -Message 'Cantidad Flyway del manifiesto inválida'
        Assert-Equal -Actual $manifest.applicationConsistent -Expected $true -Message 'El backup no quedó marcado como consistente'
        Assert-True -Condition (-not [string]::IsNullOrWhiteSpace($manifest.gitHead)) -Message 'El manifiesto no registró Git HEAD.'
        Pass 'Backup y manifiesto verificados'

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
        Pass 'Guardas destructivas verificadas'

        & $restoreScript -BackupDirectory $backupDirectory -TargetDatabase $targetDatabase `
            -ComposeFile $ComposeFile -EnvFile $envFile -ProjectName $project `
            -ConfirmDestructiveRestore -RestoreReceipts -ConfirmReceiptsOverwrite -StopBackend
        $backendContainer = Wait-ServiceHealthy -Service 'backend'

        Assert-Equal -Actual (Invoke-Sql -Database $targetDatabase -Sql "SELECT count(*) FROM alumnos WHERE apellido = '$marker'").Trim() -Expected 1 -Message 'El alumno no fue restaurado en destino'
        Assert-Equal -Actual (Invoke-Sql -Database $sourceDatabase -Sql "SELECT count(*) FROM alumnos WHERE apellido = '$marker'").Trim() -Expected 0 -Message 'La restauración alteró la base origen'
        Assert-Equal -Actual (Invoke-Sql -Database $targetDatabase -Sql "SELECT count(*)::text || '|' || max(version::int)::text FROM flyway_schema_history WHERE success").Trim() -Expected '7|7' -Message 'Flyway destino inválido'
        Assert-Equal -Actual (Invoke-Sql -Database $targetDatabase -Sql "SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_name IN ('jere_platform_student_export_snapshots','jere_platform_student_export_pages')").Trim() -Expected 2 -Message 'Las tablas V7 no fueron restauradas'
        $receipt = Invoke-Native -FilePath 'docker' -Arguments @('exec', $backendContainer, 'cat', "/app/data/receipts/$receiptFile") -Capture
        Assert-Equal -Actual $receipt -Expected $marker -Message 'El recibo no fue restaurado'
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
}

$duration = (Get-Date) - $startedAt
Write-Host ''
Write-Host "Duración total: $($duration.ToString('hh\:mm\:ss'))"
Write-Host "Pasos aprobados: $passes"
Write-Host "Fallos: $failures"
Write-Host "Resultado global: $(if ($failures -eq 0) { 'PASS' } else { 'FAIL' })"

if ($failures -ne 0) { exit 1 }
