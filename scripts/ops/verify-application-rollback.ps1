[CmdletBinding()]
param(
    [string] $ComposeFile,
    [string] $HistoricalCommit = 'ef4f9c31dab9a3dfce43f913177089f80ae0205a',
    [int] $TimeoutSeconds = 480,
    [switch] $KeepStack
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if ([string]::IsNullOrWhiteSpace($ComposeFile)) {
    $ComposeFile = Join-Path $repoRoot 'docker-compose.yml'
}
$rollbackScript = Join-Path $PSScriptRoot 'rollback-backend.ps1'
$startedAt = Get-Date
$suffix = [Guid]::NewGuid().ToString('N').Substring(0, 10)
$project = "gestudio-rollback-verify-$suffix"
$workRoot = Join-Path ([IO.Path]::GetTempPath()) $project
$envFile = Join-Path $workRoot 'verify.env'
$rollbackWorktree = Join-Path $workRoot 'historical-source'
$backupRoot = Join-Path $workRoot 'backups'
$incompatibleContext = Join-Path $workRoot 'incompatible-image'
$database = 'gestudio_rollback_verify'
$postgresUser = 'gestudio_verify'
$postgresPassword = [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(24)).ToLowerInvariant()
$jwtSecret = [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(64)).ToLowerInvariant()
$currentHead = $null
$currentImage = "gestudio-backend:rollback-current-$suffix"
$rollbackImage = "gestudio-backend:rollback-compatible-$suffix"
$incompatibleImage = "gestudio-backend:rollback-incompatible-$suffix"
$marker = "GESTUDIO_ROLLBACK_VERIFY_$suffix"
$stackAttempted = $false
$worktreeAdded = $false
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
        $tail = (($text -split "`r?`n") | Select-Object -Last 120) -join "`n"
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
    param([Parameter(Mandatory)][string] $Sql)

    $dbContainer = Invoke-Compose -Arguments @('ps', '-q', 'db') -Capture
    if ([string]::IsNullOrWhiteSpace($dbContainer)) { throw 'No se encontró PostgreSQL.' }
    return Invoke-Native -FilePath 'docker' -Arguments @(
        'exec', $dbContainer, 'sh', '-ec',
        'PGPASSWORD="$POSTGRES_PASSWORD" psql --no-psqlrc --tuples-only --no-align --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" --command="$1"',
        'sh', $Sql
    ) -Capture
}

function Get-BackendImage {
    $containerId = Invoke-Compose -Arguments @('ps', '-q', 'backend') -Capture
    if ([string]::IsNullOrWhiteSpace($containerId)) { throw 'No se encontró el backend.' }
    return Invoke-Native -FilePath 'docker' -Arguments @(
        'inspect', '--format', '{{.Config.Image}}', $containerId
    ) -Capture
}

function Get-ImageFlywayLatest {
    param([Parameter(Mandatory)][string] $Image)
    return Invoke-Native -FilePath 'docker' -Arguments @(
        'run', '--rm', '--entrypoint', 'cat', $Image, '/app/build-metadata/flyway-latest'
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
        $logs = Invoke-Compose -Arguments @('logs', '--tail', '200', 'db', 'backend') -Capture -IgnoreFailure
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
if (-not (Test-Path -LiteralPath $rollbackScript -PathType Leaf)) { throw "Falta rollback-backend.ps1: $rollbackScript" }

try {
    New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $incompatibleContext -Force | Out-Null

    $currentHead = Invoke-Native -FilePath 'git' -Arguments @('-C', $repoRoot, 'rev-parse', 'HEAD') -Capture
    Invoke-Native -FilePath 'git' -Arguments @('-C', $repoRoot, 'cat-file', '-e', "${HistoricalCommit}^{commit}") | Out-Null

    $environment = [ordered]@{
        COMPOSE_PROJECT_NAME = $project
        POSTGRES_DB = $database
        POSTGRES_USER = $postgresUser
        POSTGRES_PASSWORD = $postgresPassword
        POSTGRES_PORT = (Get-FreePort)
        BACKEND_PORT = (Get-FreePort)
        FRONTEND_PORT = (Get-FreePort)
        BACKEND_IMAGE = $currentImage
        SPRING_PROFILES_ACTIVE = 'dev'
        SPRING_JPA_HIBERNATE_DDL_AUTO = 'validate'
        SPRING_FLYWAY_ENABLED = 'true'
        SPRING_FLYWAY_BASELINE_ON_MIGRATE = 'false'
        APP_SCHEDULING_ENABLED = 'false'
        APP_BOOTSTRAP_SUPERADMIN_ENABLED = 'false'
        APP_BOOTSTRAP_ADMIN_ENABLED = 'false'
        JWT_SECRET = $jwtSecret
        JWT_ISSUER = 'gestudio-rollback-verify'
        APP_TIME_ZONE = 'America/Argentina/Buenos_Aires'
        APP_CORS_ALLOWED_ORIGINS = 'http://127.0.0.1:18080'
        APP_JERE_PLATFORM_STUDENT_EXPORT_ENABLED = 'false'
    }
    $environment.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" } |
        Set-Content -LiteralPath $envFile -Encoding ASCII

    Invoke-Native -FilePath 'docker' -Arguments @('info', '--format', '{{.ServerVersion}}') | Out-Null
    Invoke-Native -FilePath 'docker' -Arguments @('compose', 'version') | Out-Null
    Pass 'Docker disponible'

    Invoke-Native -FilePath 'git' -Arguments @(
        '-C', $repoRoot, 'worktree', 'add', '--detach', $rollbackWorktree, $HistoricalCommit
    ) | Out-Null
    $worktreeAdded = $true
    Copy-Item -LiteralPath (Join-Path $repoRoot 'backend/Dockerfile') `
        -Destination (Join-Path $rollbackWorktree 'backend/Dockerfile') -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot 'backend/src/main/resources/db/migration/V7__jere_platform_student_source_exports.sql') `
        -Destination (Join-Path $rollbackWorktree 'backend/src/main/resources/db/migration/V7__jere_platform_student_source_exports.sql') -Force

    $incompatibleDockerfile = @'
FROM alpine:3.20
RUN mkdir -p /app/build-metadata && printf '6\n' > /app/build-metadata/flyway-latest
ENTRYPOINT ["sh"]
'@
    Set-Content -LiteralPath (Join-Path $incompatibleContext 'Dockerfile') -Value $incompatibleDockerfile -Encoding UTF8

    Invoke-Native -FilePath 'docker' -Arguments @(
        'build', '--build-arg', "VCS_REF=$currentHead", '-t', $currentImage,
        (Join-Path $repoRoot 'backend')
    ) | Out-Null
    Invoke-Native -FilePath 'docker' -Arguments @(
        'build', '--build-arg', "VCS_REF=$HistoricalCommit-compatible-v7", '-t', $rollbackImage,
        (Join-Path $rollbackWorktree 'backend')
    ) | Out-Null
    Invoke-Native -FilePath 'docker' -Arguments @('build', '-t', $incompatibleImage, $incompatibleContext) | Out-Null

    Assert-Equal -Actual (Get-ImageFlywayLatest -Image $currentImage) -Expected 7 -Message 'Metadata Flyway de imagen actual inválida'
    Assert-Equal -Actual (Get-ImageFlywayLatest -Image $rollbackImage) -Expected 7 -Message 'Metadata Flyway de rollback compatible inválida'
    Assert-Equal -Actual (Get-ImageFlywayLatest -Image $incompatibleImage) -Expected 6 -Message 'Fixture incompatible inválida'
    Pass 'Artefactos actual, rollback e incompatible construidos'

    Push-Location $repoRoot
    try {
        $stackAttempted = $true
        Invoke-Compose -Arguments @('up', '-d', 'db', 'backend') | Out-Null
        Wait-ServiceHealthy -Service 'db' | Out-Null
        Wait-ServiceHealthy -Service 'backend' | Out-Null
        Assert-Equal -Actual (Get-BackendImage) -Expected $currentImage -Message 'La imagen actual no quedó activa'
        Assert-Equal -Actual (Invoke-Sql -Sql "SELECT count(*)::text || '|' || max(version::int)::text FROM flyway_schema_history WHERE success").Trim() -Expected '7|7' -Message 'Flyway inicial inválida'
        Pass 'Versión actual healthy con V1-V7'

        $studentResult = Invoke-Sql -Sql "INSERT INTO alumnos(nombre, apellido, fecha_incorporacion, activo) VALUES ('Rollback', '$marker', DATE '2026-07-20', true) RETURNING id"
        $studentId = (($studentResult -split "`r?`n") | Select-Object -First 1).Trim()
        Assert-True -Condition ($studentId -match '^[0-9]+$') -Message "La fixture no devolvió ID numérico: $studentResult"
        Pass 'Dato sintético persistido antes del rollback'

        Assert-Throws -Action {
            & $rollbackScript -TargetBackendImage $rollbackImage `
                -ComposeFile $ComposeFile -EnvFile $envFile -ProjectName $project `
                -SkipBackup
        } -MessageContains 'ConfirmRollback' -FailureMessage 'Rollback sin confirmación no fue rechazado'

        Assert-Throws -Action {
            & $rollbackScript -TargetBackendImage $incompatibleImage `
                -ComposeFile $ComposeFile -EnvFile $envFile -ProjectName $project `
                -ExpectedCurrentImage $currentImage -SkipBackup -ConfirmRollback
        } -MessageContains 'Rollback incompatible' -FailureMessage 'Imagen con Flyway V6 no fue rechazada'
        Assert-Equal -Actual (Get-BackendImage) -Expected $currentImage -Message 'Las guardas alteraron la imagen activa'
        Pass 'Guardas de confirmación y compatibilidad Flyway'

        $rollbackResult = @(& $rollbackScript -TargetBackendImage $rollbackImage `
            -ComposeFile $ComposeFile -EnvFile $envFile -ProjectName $project `
            -ExpectedCurrentImage $currentImage -BackupOutputDirectory $backupRoot `
            -ConfirmRollback)
        $rollbackJson = $rollbackResult[-1] | ConvertFrom-Json
        Assert-True -Condition (Test-Path -LiteralPath $rollbackJson.backupDirectory -PathType Container) -Message 'El rollback no produjo backup previo.'
        Assert-Equal -Actual (Get-BackendImage) -Expected $rollbackImage -Message 'El artefacto rollback no quedó activo'
        Assert-Equal -Actual (Invoke-Sql -Sql "SELECT count(*) FROM alumnos WHERE id = $studentId AND apellido = '$marker'").Trim() -Expected 1 -Message 'El dato no sobrevivió al rollback'
        Assert-Equal -Actual (Invoke-Sql -Sql "SELECT count(*)::text || '|' || max(version::int)::text FROM flyway_schema_history WHERE success").Trim() -Expected '7|7' -Message 'Flyway cambió durante rollback'
        Assert-Equal -Actual (Invoke-Sql -Sql "SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_name IN ('jere_platform_student_export_snapshots','jere_platform_student_export_pages')").Trim() -Expected 2 -Message 'El rollback eliminó estructuras V7'
        Pass 'Rollback compatible con datos y V7 preservados'

        & $rollbackScript -TargetBackendImage $currentImage `
            -ComposeFile $ComposeFile -EnvFile $envFile -ProjectName $project `
            -ExpectedCurrentImage $rollbackImage -SkipBackup -ConfirmRollback | Out-Null
        Assert-Equal -Actual (Get-BackendImage) -Expected $currentImage -Message 'La versión actual no fue restaurada'
        Assert-Equal -Actual (Invoke-Sql -Sql "SELECT count(*) FROM alumnos WHERE id = $studentId AND apellido = '$marker'").Trim() -Expected 1 -Message 'El dato no sobrevivió al retorno'
        Assert-Equal -Actual (Invoke-Sql -Sql "SELECT count(*)::text || '|' || max(version::int)::text FROM flyway_schema_history WHERE success").Trim() -Expected '7|7' -Message 'Flyway cambió al volver a actual'
        Pass 'Retorno al artefacto actual verificado'
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
        Write-Host "[INFO] Directorio temporal: $workRoot"
    }
    else {
        if ($stackAttempted -and (Test-Path -LiteralPath $envFile)) {
            try { Invoke-Compose -Arguments @('down', '--volumes', '--remove-orphans') -IgnoreFailure | Out-Null }
            catch { $failures++; Write-Host "[FAIL] Cleanup Compose: $($_.Exception.Message)" -ForegroundColor Red }
        }
        foreach ($image in @($currentImage, $rollbackImage, $incompatibleImage)) {
            try { Invoke-Native -FilePath 'docker' -Arguments @('image', 'rm', '-f', $image) -IgnoreFailure | Out-Null } catch { }
        }
        if ($worktreeAdded) {
            try { Invoke-Native -FilePath 'git' -Arguments @('-C', $repoRoot, 'worktree', 'remove', '--force', $rollbackWorktree) -IgnoreFailure | Out-Null } catch { }
            try { Invoke-Native -FilePath 'git' -Arguments @('-C', $repoRoot, 'worktree', 'prune') -IgnoreFailure | Out-Null } catch { }
        }
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
