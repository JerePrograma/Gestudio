[CmdletBinding()]
param(
    [string] $ComposeFile,
    [ValidateNotNullOrEmpty()][string] $HistoricalCommit = 'HEAD^',
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
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$workRoot = [IO.Path]::GetFullPath((Join-Path $tempRoot $project))
$envFile = Join-Path $workRoot 'verify.env'
$historicalArchive = Join-Path $workRoot 'historical-backend.zip'
$historicalSource = Join-Path $workRoot 'historical-source'
$backupRoot = Join-Path $workRoot 'backups'
$incompatibleContext = Join-Path $workRoot 'incompatible-image'
$database = 'gestudio_rollback_verify'
$postgresUser = 'gestudio_verify'
$rng = [Security.Cryptography.RandomNumberGenerator]::Create()
try {
    $postgresPasswordBytes = New-Object byte[] 24
    $jwtSecretBytes = New-Object byte[] 64
    $rng.GetBytes($postgresPasswordBytes)
    $rng.GetBytes($jwtSecretBytes)
}
finally { $rng.Dispose() }
$postgresPassword = ([BitConverter]::ToString($postgresPasswordBytes) -replace '-', '').ToLowerInvariant()
$jwtSecret = ([BitConverter]::ToString($jwtSecretBytes) -replace '-', '').ToLowerInvariant()
$currentHead = $null
$currentImage = "gestudio-backend:rollback-current-$suffix"
$rollbackImage = "gestudio-backend:rollback-compatible-$suffix"
$incompatibleImage = "gestudio-backend:rollback-incompatible-$suffix"
$marker = "GESTUDIO_ROLLBACK_VERIFY_$suffix"
$fixtureTenantId = [Guid]::NewGuid().ToString()
$fixtureTenantCode = "rollback-$suffix"
$stackAttempted = $false
$imageMutationAttempted = $false
$workRootCreated = $false
$passes = 0
$failures = 0
$previousProcessEnvironment = @{}
$dockerContextBackup = [Environment]::GetEnvironmentVariable('DOCKER_CONTEXT', 'Process')
$dockerContextApplied = $false
$protectedDemoBefore = $null
$protectedDemoSnapshotCaptured = $false
$projectBefore = $null
$projectSnapshotCaptured = $false

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

function Assert-SafeTemporaryChild {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $AllowedRoot
    )

    $trimChars = [char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $root = [IO.Path]::GetFullPath($AllowedRoot).TrimEnd($trimChars)
    $candidate = [IO.Path]::GetFullPath($Path)
    $prefix = $root + [IO.Path]::DirectorySeparatorChar
    if ($candidate -eq $root -or -not $candidate.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Ruta temporal fuera del directorio permitido: $candidate"
    }

    if (Test-Path -LiteralPath $candidate) {
        $item = Get-Item -LiteralPath $candidate -Force
        $resolved = [IO.Path]::GetFullPath($item.FullName)
        if ($resolved -eq $root -or -not $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Ruta temporal resuelta fuera del directorio permitido: $resolved"
        }
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "No se admite un reparse point como ruta temporal: $resolved"
        }
    }

    return $candidate
}

function Copy-FileExact {
    param(
        [Parameter(Mandatory)][string] $Source,
        [Parameter(Mandatory)][string] $Destination,
        [Parameter(Mandatory)][string] $AllowedDestinationRoot
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw "No existe el archivo de compatibilidad: $Source"
    }
    $destinationPath = Assert-SafeTemporaryChild -Path $Destination -AllowedRoot $AllowedDestinationRoot
    $destinationParent = Split-Path $destinationPath -Parent
    Assert-SafeTemporaryChild -Path $destinationParent -AllowedRoot $AllowedDestinationRoot | Out-Null
    Copy-Item -LiteralPath $Source -Destination $destinationPath -Force
    $sourceHash = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash
    $destinationHash = (Get-FileHash -LiteralPath $destinationPath -Algorithm SHA256).Hash
    Assert-Equal -Actual $destinationHash -Expected $sourceHash `
        -Message "La copia temporal no coincide con su fuente: $Source"
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

function Assert-LocalDockerTarget {
    if (-not [string]::IsNullOrWhiteSpace(
            [Environment]::GetEnvironmentVariable('DOCKER_HOST', 'Process'))) {
        throw 'DOCKER_HOST está definido; el drill rechaza overrides de daemon.'
    }
    $context = Invoke-Native -FilePath 'docker' -Arguments @('context', 'show') -Capture
    if ([string]::IsNullOrWhiteSpace($context) -or
        $context -match '(?i)(prod|production|stage|staging|remote|demo)') {
        throw 'El contexto Docker activo es vacío o posee un nombre protegido.'
    }
    $endpointRaw = Invoke-Native -FilePath 'docker' -Arguments @(
        'context', 'inspect', '--format', '{{json .Endpoints.docker.Host}}', $context
    ) -Capture
    try { $endpoint = [string]($endpointRaw | ConvertFrom-Json) }
    catch { throw 'El contexto Docker no devolvió un endpoint válido.' }
    if ($endpoint -notmatch '^npipe://' -and $endpoint -cne 'unix:///var/run/docker.sock') {
        throw 'El contexto Docker no apunta a un endpoint local permitido.'
    }
    $osType = Invoke-Native -FilePath 'docker' -Arguments @(
        '--context', $context, 'info', '--format', '{{.OSType}}'
    ) -Capture
    if ($osType.Trim() -cne 'linux') {
        throw 'El daemon Docker del drill debe ser Linux.'
    }
    return $context
}

function Get-DockerProjectSnapshot {
    param([Parameter(Mandatory)][string] $ProjectName)

    if ($ProjectName -cne 'gestudio-remote-demo' -and
        $ProjectName -notmatch '^gestudio-rollback-verify-[a-f0-9]{10}$') {
        throw 'Snapshot Docker rechazado para un proyecto fuera del scope permitido.'
    }
    $containerIds = @((Invoke-Native -FilePath 'docker' -Arguments @(
        'ps', '-aq', '--no-trunc', '--filter', "label=com.docker.compose.project=$ProjectName"
    ) -Capture) -split '[\r\n]+' | Where-Object { $_ } | Sort-Object)
    $containers = @($containerIds | ForEach-Object {
        Invoke-Native -FilePath 'docker' -Arguments @(
            'inspect', '--format',
            '{{.Id}}|{{.Image}}|{{.Config.Image}}|{{.Created}}|{{.State.Status}}|{{.State.Running}}|{{.State.Restarting}}|{{.State.Paused}}|{{.State.Dead}}|{{.State.StartedAt}}|{{.State.FinishedAt}}|{{.RestartCount}}|{{json .Mounts}}|{{json .NetworkSettings.Networks}}',
            $_
        ) -Capture
    } | Sort-Object)
    $volumeNames = @((Invoke-Native -FilePath 'docker' -Arguments @(
        'volume', 'ls', '-q', '--filter', "label=com.docker.compose.project=$ProjectName"
    ) -Capture) -split '[\r\n]+' | Where-Object { $_ } | Sort-Object)
    $volumes = @($volumeNames | ForEach-Object {
        Invoke-Native -FilePath 'docker' -Arguments @(
            'volume', 'inspect', '--format',
            '{{.Name}}|{{.CreatedAt}}|{{.Driver}}|{{.Mountpoint}}|{{.Scope}}|{{json .Labels}}|{{json .Options}}',
            $_
        ) -Capture
    } | Sort-Object)
    $networkIds = @((Invoke-Native -FilePath 'docker' -Arguments @(
        'network', 'ls', '-q', '--no-trunc', '--filter', "label=com.docker.compose.project=$ProjectName"
    ) -Capture) -split '[\r\n]+' | Where-Object { $_ } | Sort-Object)
    $networks = @($networkIds | ForEach-Object {
        Invoke-Native -FilePath 'docker' -Arguments @(
            'network', 'inspect', '--format',
            '{{.Id}}|{{.Created}}|{{.Driver}}|{{.Scope}}|{{.Internal}}|{{.Attachable}}|{{.Ingress}}|{{json .Labels}}|{{json .Options}}|{{json .Containers}}',
            $_
        ) -Capture
    } | Sort-Object)
    return [pscustomobject]@{
        Containers = $containers
        Volumes = $volumes
        Networks = $networks
    }
}

function Test-DockerProjectSnapshotInvariant {
    param(
        [Parameter(Mandatory)] $Before,
        [Parameter(Mandatory)] $After
    )
    return (($Before | ConvertTo-Json -Compress -Depth 8) -ceq
        ($After | ConvertTo-Json -Compress -Depth 8))
}

function Get-FreePort {
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $listener.Start()
    try { return ([Net.IPEndPoint]$listener.LocalEndpoint).Port }
    finally { $listener.Stop() }
}

function Get-LocalMigrationManifest {
    param([string] $SourceRoot = $script:repoRoot)

    $migrationRoot = Join-Path $SourceRoot 'backend/src/main/resources/db/migration'
    $entries = @(Get-ChildItem -LiteralPath $migrationRoot -Filter 'V*__*.sql' -File | ForEach-Object {
        if ($_.Name -notmatch '^V(?<version>[0-9]+)__.+\.sql$') {
            throw "Nombre de migración Flyway inválido: $($_.Name)"
        }
        [pscustomobject]@{ Version = [int]$matches.version; Script = $_.Name }
    } | Sort-Object Version)

    if ($entries.Count -lt 2) { throw 'La verificación de rollback requiere al menos dos migraciones Flyway.' }
    if (@($entries.Version | Select-Object -Unique).Count -ne $entries.Count) {
        throw 'Hay versiones Flyway locales duplicadas.'
    }
    for ($index = 0; $index -lt $entries.Count; $index++) {
        if ($entries[$index].Version -ne ($index + 1)) {
            throw 'La cadena Flyway local no es contigua desde V1.'
        }
    }
    $baselines = @(Get-ChildItem -LiteralPath $migrationRoot -Filter 'B*__*.sql' -File | ForEach-Object {
        if ($_.Name -notmatch '^B(?<version>[0-9]+)__.+\.sql$') {
            throw "Nombre de baseline Flyway inválido: $($_.Name)"
        }
        [pscustomobject]@{ Version = [int]$matches.version; Script = $_.Name }
    })
    if ($baselines.Count -ne 1 -or $baselines[0].Version -ne $entries[-1].Version) {
        throw 'La baseline Flyway debe existir una sola vez y corresponder a la última versión.'
    }

    $resourceNames = [string[]]@(Get-ChildItem -LiteralPath $migrationRoot -File |
        ForEach-Object { $_.Name })
    [Array]::Sort($resourceNames, [StringComparer]::Ordinal)
    if ($resourceNames.Count -eq 0) { throw 'No existen recursos Flyway locales.' }
    $resourceEntries = @($resourceNames | ForEach-Object {
        if ($_ -match "[\t\r\n]" -or $_.Contains('/') -or $_.Contains('\')) {
            throw "Nombre de recurso Flyway no canonizable: $_"
        }
        [pscustomobject]@{
            Script = $_
            Sha256 = (Get-FileHash -LiteralPath (Join-Path $migrationRoot $_) -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    })
    $canonicalLines = @('gestudio-flyway-manifest-v1') + @($resourceEntries | ForEach-Object {
        "$($_.Sha256)`t$($_.Script)"
    })

    return [pscustomobject]@{
        Count = $entries.Count
        LatestVersion = $entries[-1].Version
        Scripts = $resourceNames
        Entries = $entries
        Baseline = $baselines[0]
        Resources = $resourceEntries
        ResourceManifest = $canonicalLines -join "`n"
    }
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
    $sqlBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Sql))
    return Invoke-Native -FilePath 'docker' -Arguments @(
        'exec', $dbContainer, 'sh', '-ec',
        'printf "%s" "$1" | base64 -d | PGPASSWORD="$POSTGRES_PASSWORD" psql --no-psqlrc --tuples-only --no-align --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" --file=-',
        'sh', $sqlBase64
    ) -Capture
}

function Assert-FlywayHistory {
    param([Parameter(Mandatory)] $Manifest)
    $failed = [int](Invoke-Sql -Sql 'SELECT count(*) FROM flyway_schema_history WHERE NOT success;')
    $raw = Invoke-Sql -Sql "SELECT version || '|' || type || '|' || script FROM flyway_schema_history WHERE success ORDER BY installed_rank;"
    $installed = @(($raw -split "`r?`n") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object {
        $parts = $_.Split('|', 3)
        [pscustomobject]@{ Version = [int]$parts[0]; Type = $parts[1]; Script = $parts[2] }
    })
    $versioned = $installed.Count -eq $Manifest.Entries.Count
    if ($versioned) {
        for ($index = 0; $index -lt $Manifest.Entries.Count; $index++) {
            $versioned = $versioned -and
                $installed[$index].Version -eq $Manifest.Entries[$index].Version -and
                $installed[$index].Type -ceq 'SQL' -and
                $installed[$index].Script -ceq $Manifest.Entries[$index].Script
        }
    }
    $baseline = $null -ne $Manifest.Baseline -and $installed.Count -eq 1 -and
        $installed[0].Version -eq $Manifest.LatestVersion -and
        $installed[0].Type -ceq 'SQL_BASELINE' -and
        $installed[0].Script -ceq $Manifest.Baseline.Script
    Assert-True -Condition ($failed -eq 0 -and ($versioned -or $baseline)) -Message "Historial Flyway inválido: $raw"
    if ($baseline) { return 'BASELINE' }
    return 'VERSIONED'
}

function Assert-ControlPlaneDatabaseContract {
    $contract = (Invoke-Sql -Sql @'
SELECT
  pg_has_role('gestudio_rollback_control', 'gestudio_platform', 'MEMBER')::text || '|' ||
  (to_regclass('public.platform_admins') IS NOT NULL AND
   to_regclass('public.platform_refresh_sessions') IS NOT NULL AND
   to_regclass('public.platform_mfa_credentials') IS NOT NULL AND
   to_regclass('public.platform_audit_events') IS NOT NULL AND
   to_regprocedure('public.gestudio_multitenancy_health()') IS NOT NULL)::text || '|' ||
  (has_table_privilege('gestudio_rollback_control', 'public.tenants', 'SELECT') AND
   has_table_privilege('gestudio_rollback_control', 'public.tenants', 'INSERT') AND
   has_table_privilege('gestudio_rollback_control', 'public.tenants', 'UPDATE'))::text || '|' ||
  has_table_privilege('gestudio_rollback_control', 'public.alumnos', 'SELECT')::text || '|' ||
  (has_table_privilege('gestudio_rollback_runtime', 'public.tenants', 'INSERT') OR
   has_table_privilege('gestudio_rollback_runtime', 'public.tenants', 'UPDATE') OR
   has_table_privilege('gestudio_rollback_runtime', 'public.tenants', 'DELETE'))::text;
'@).Trim()
    Assert-Equal -Actual $contract -Expected 'true|true|true|false|false' `
        -Message 'El rollback alteró los grants de control-plane'
}

function Get-BackendImageId {
    $containerId = Invoke-Compose -Arguments @('ps', '-q', 'backend') -Capture
    if ([string]::IsNullOrWhiteSpace($containerId)) { throw 'No se encontró el backend.' }
    return Invoke-Native -FilePath 'docker' -Arguments @(
        'inspect', '--format', '{{.Image}}', $containerId
    ) -Capture
}

function Resolve-ImageId {
    param([Parameter(Mandatory)][string] $Image)
    $imageId = Invoke-Native -FilePath 'docker' -Arguments @(
        'image', 'inspect', '--format', '{{.Id}}', $Image
    ) -Capture
    Assert-True -Condition ($imageId -match '^sha256:[a-f0-9]{64}$') `
        -Message "Docker no resolvió una identidad inmutable para $Image"
    return $imageId
}

function Get-ImageFlywayLatest {
    param([Parameter(Mandatory)][string] $Image)
    return Invoke-Native -FilePath 'docker' -Arguments @(
        'run', '--rm', '--entrypoint', 'cat', $Image, '/app/build-metadata/flyway-latest'
    ) -Capture
}

function Get-ImageFlywayBaselineScript {
    param([Parameter(Mandatory)][string] $Image)
    return Invoke-Native -FilePath 'docker' -Arguments @(
        'run', '--rm', '--entrypoint', 'cat', $Image, '/app/build-metadata/flyway-baseline-script'
    ) -Capture
}

function Get-ImageFlywayResourceManifest {
    param([Parameter(Mandatory)][string] $Image)
    return Invoke-Native -FilePath 'docker' -Arguments @(
        'run', '--rm', '--entrypoint', 'cat', $Image, '/app/build-metadata/flyway-resources.sha256'
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
    $migrationManifest = Get-LocalMigrationManifest
    $incompatibleFlyway = $migrationManifest.LatestVersion - 1
    $currentHead = Invoke-Native -FilePath 'git' -Arguments @('-C', $repoRoot, 'rev-parse', 'HEAD') -Capture
    $resolvedHistoricalCommit = Invoke-Native -FilePath 'git' -Arguments @(
        '-C', $repoRoot, 'rev-parse', '--verify', '--end-of-options', "${HistoricalCommit}^{commit}"
    ) -Capture
    Assert-True -Condition ($currentHead -match '^[0-9a-f]{40}$') -Message 'HEAD no resolvió a un commit SHA-1 completo.'
    Assert-True -Condition ($resolvedHistoricalCommit -match '^[0-9a-f]{40}$') -Message 'HistoricalCommit no resolvió a un commit SHA-1 completo.'
    Assert-True -Condition ($resolvedHistoricalCommit -ne $currentHead) -Message 'HistoricalCommit debe ser anterior a HEAD.'
    $ancestorExitCode = Invoke-Native -FilePath 'git' -Arguments @(
        '-C', $repoRoot, 'merge-base', '--is-ancestor', $resolvedHistoricalCommit, $currentHead
    ) -IgnoreFailure
    Assert-Equal -Actual $ancestorExitCode -Expected 0 -Message 'HistoricalCommit no es ancestro de HEAD'

    Assert-True -Condition ($project -cne 'gestudio-remote-demo' -and
        $project -match '^gestudio-rollback-verify-[a-f0-9]{10}$') `
        -Message 'Nombre de proyecto rollback inválido o protegido'
    $dockerContext = Assert-LocalDockerTarget
    [Environment]::SetEnvironmentVariable('DOCKER_CONTEXT', $dockerContext, 'Process')
    $dockerContextApplied = $true
    Invoke-Native -FilePath 'docker' -Arguments @('version', '--format', '{{.Server.Version}}') | Out-Null
    Invoke-Native -FilePath 'docker' -Arguments @('compose', 'version', '--short') | Out-Null
    $protectedDemoBefore = Get-DockerProjectSnapshot -ProjectName 'gestudio-remote-demo'
    $protectedDemoSnapshotCaptured = $true
    $projectBefore = Get-DockerProjectSnapshot -ProjectName $project
    $projectSnapshotCaptured = $true
    Assert-True -Condition ($projectBefore.Containers.Count -eq 0 -and
        $projectBefore.Volumes.Count -eq 0 -and
        $projectBefore.Networks.Count -eq 0) `
        -Message 'El proyecto efímero del drill ya posee recursos Docker.'
    Pass "Docker local Linux fijado en contexto '$dockerContext'; proyecto efímero ausente"

    Assert-SafeTemporaryChild -Path $workRoot -AllowedRoot $tempRoot | Out-Null
    New-Item -ItemType Directory -Path $workRoot | Out-Null
    $workRootCreated = $true
    Assert-SafeTemporaryChild -Path $workRoot -AllowedRoot $tempRoot | Out-Null
    foreach ($temporaryDirectory in @($backupRoot, $incompatibleContext)) {
        Assert-SafeTemporaryChild -Path $temporaryDirectory -AllowedRoot $workRoot | Out-Null
        New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null
    }
    Assert-SafeTemporaryChild -Path $historicalArchive -AllowedRoot $workRoot | Out-Null
    Assert-SafeTemporaryChild -Path $historicalSource -AllowedRoot $workRoot | Out-Null

    $environment = [ordered]@{
        COMPOSE_PROJECT_NAME = $project
        POSTGRES_DB = $database
        POSTGRES_USER = $postgresUser
        POSTGRES_PASSWORD = $postgresPassword
        POSTGRES_APP_USER = 'gestudio_rollback_runtime'
        POSTGRES_APP_PASSWORD = "${postgresPassword}app"
        POSTGRES_CONTROL_USER = 'gestudio_rollback_control'
        POSTGRES_CONTROL_PASSWORD = "${postgresPassword}control"
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
        APP_LOCAL_ADMIN_PASSWORD_RESET_ENABLED = 'false'
        APP_LOCAL_ADMIN_PASSWORD_RESET_USERNAME = ''
        APP_LOCAL_ADMIN_PASSWORD_RESET_PASSWORD = ''
        JWT_SECRET = $jwtSecret
        JWT_ISSUER = 'gestudio-rollback-verify'
        JWT_PLATFORM_AUDIENCE = 'gestudio-rollback-platform-web'
        APP_PLATFORM_MFA_ENCRYPTION_KEY = 'MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY='
        APP_PLATFORM_REFRESH_COOKIE_SECURE = 'false'
        APP_TIME_ZONE = 'America/Argentina/Buenos_Aires'
        APP_CORS_ALLOWED_ORIGINS = 'http://127.0.0.1:18080'
    }
    foreach ($entry in $environment.GetEnumerator()) {
        $previousProcessEnvironment[$entry.Key] = [Environment]::GetEnvironmentVariable($entry.Key, 'Process')
        [Environment]::SetEnvironmentVariable($entry.Key, [string]$entry.Value, 'Process')
    }
    $environment.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" } |
        Set-Content -LiteralPath $envFile -Encoding ASCII

    Invoke-Native -FilePath 'git' -Arguments @(
        '-C', $repoRoot, 'archive', '--format=zip', "--output=$historicalArchive",
        $resolvedHistoricalCommit, '--', 'backend'
    ) | Out-Null
    Assert-True -Condition ((Get-Item -LiteralPath $historicalArchive).Length -gt 0) `
        -Message 'git archive produjo un archivo histórico vacío.'
    Expand-Archive -LiteralPath $historicalArchive -DestinationPath $historicalSource
    Assert-SafeTemporaryChild -Path $historicalSource -AllowedRoot $workRoot | Out-Null
    $historicalBackend = Join-Path $historicalSource 'backend'
    Assert-SafeTemporaryChild -Path $historicalBackend -AllowedRoot $historicalSource | Out-Null
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $historicalBackend 'pom.xml') -PathType Leaf) `
        -Message 'El commit histórico no contiene backend/pom.xml.'

    $historicalMigrationRoot = Join-Path $historicalBackend 'src/main/resources/db/migration'
    if (Test-Path -LiteralPath $historicalMigrationRoot) {
        Assert-SafeTemporaryChild -Path $historicalMigrationRoot -AllowedRoot $historicalSource | Out-Null
        Remove-Item -LiteralPath $historicalMigrationRoot -Recurse -Force
    }
    Assert-SafeTemporaryChild -Path $historicalMigrationRoot -AllowedRoot $historicalSource | Out-Null
    New-Item -ItemType Directory -Path $historicalMigrationRoot | Out-Null

    Copy-FileExact -Source (Join-Path $repoRoot 'backend/Dockerfile') `
        -Destination (Join-Path $historicalBackend 'Dockerfile') `
        -AllowedDestinationRoot $historicalSource
    foreach ($migration in $migrationManifest.Scripts) {
        Copy-FileExact -Source (Join-Path $repoRoot "backend/src/main/resources/db/migration/$migration") `
            -Destination (Join-Path $historicalMigrationRoot $migration) `
            -AllowedDestinationRoot $historicalSource
    }
    $rollbackManifest = Get-LocalMigrationManifest -SourceRoot $historicalSource
    Assert-Equal -Actual $rollbackManifest.ResourceManifest -Expected $migrationManifest.ResourceManifest `
        -Message 'El artefacto histórico no contiene nombres y SHA-256 Flyway exactos'
    Pass "Commit histórico $resolvedHistoricalCommit extraído sin modificar el estado Git"

    $incompatibleManifestPath = Join-Path $incompatibleContext 'flyway-resources.sha256'
    [IO.File]::WriteAllText(
        $incompatibleManifestPath,
        $migrationManifest.ResourceManifest + "`n",
        [Text.UTF8Encoding]::new($false))
    $incompatibleDockerfile = @"
FROM alpine:3.20
RUN mkdir -p /app/build-metadata \
 && printf '$incompatibleFlyway\n' > /app/build-metadata/flyway-latest \
 && printf '$incompatibleFlyway\n' > /app/build-metadata/flyway-versioned-latest \
 && printf '$($migrationManifest.Baseline.Script)\n' > /app/build-metadata/flyway-baseline-script \
 && printf 'legacy-api-401-v1\n' > /app/build-metadata/health-contract
COPY flyway-resources.sha256 /app/build-metadata/flyway-resources.sha256
ENTRYPOINT ["sh"]
"@
    Set-Content -LiteralPath (Join-Path $incompatibleContext 'Dockerfile') -Value $incompatibleDockerfile -Encoding UTF8

    foreach ($tag in @($currentImage, $rollbackImage, $incompatibleImage)) {
        $existingImage = Invoke-Native -FilePath 'docker' -Arguments @(
            'image', 'ls', '-q', '--no-trunc', $tag
        ) -Capture
        Assert-True -Condition ([string]::IsNullOrWhiteSpace($existingImage)) `
            -Message "El tag efímero ya existe y no será sobrescrito: $tag"
    }

    $imageMutationAttempted = $true
    Invoke-Native -FilePath 'docker' -Arguments @(
        'build', '--build-arg', "VCS_REF=$currentHead", '-t', $currentImage,
        (Join-Path $repoRoot 'backend')
    ) | Out-Null
    Invoke-Native -FilePath 'docker' -Arguments @(
        'build', '--build-arg', "VCS_REF=$resolvedHistoricalCommit-compatible-v$($migrationManifest.LatestVersion)", '-t', $rollbackImage,
        $historicalBackend
    ) | Out-Null
    Invoke-Native -FilePath 'docker' -Arguments @('build', '-t', $incompatibleImage, $incompatibleContext) | Out-Null

    $currentImageId = Resolve-ImageId -Image $currentImage
    $rollbackImageId = Resolve-ImageId -Image $rollbackImage
    $incompatibleImageId = Resolve-ImageId -Image $incompatibleImage
    Assert-Equal -Actual (Get-ImageFlywayLatest -Image $currentImageId) -Expected $migrationManifest.LatestVersion -Message 'Metadata Flyway de imagen actual inválida'
    Assert-Equal -Actual (Get-ImageFlywayLatest -Image $rollbackImageId) -Expected $migrationManifest.LatestVersion -Message 'Metadata Flyway de rollback compatible inválida'
    Assert-Equal -Actual (Get-ImageFlywayBaselineScript -Image $currentImageId) -Expected $migrationManifest.Baseline.Script -Message 'Baseline Flyway de imagen actual inválida'
    Assert-Equal -Actual (Get-ImageFlywayBaselineScript -Image $rollbackImageId) -Expected $migrationManifest.Baseline.Script -Message 'Baseline Flyway de rollback compatible inválida'
    Assert-Equal -Actual (Get-ImageFlywayResourceManifest -Image $currentImageId) -Expected $migrationManifest.ResourceManifest -Message 'Manifiesto Flyway de imagen actual inválido'
    Assert-Equal -Actual (Get-ImageFlywayResourceManifest -Image $rollbackImageId) -Expected $migrationManifest.ResourceManifest -Message 'Manifiesto Flyway de rollback compatible inválido'
    Assert-Equal -Actual (Get-ImageFlywayLatest -Image $incompatibleImageId) -Expected $incompatibleFlyway -Message 'Fixture incompatible inválida'
    Pass 'Artefactos construidos, fijados por ID y con manifiesto Flyway exacto'

    Push-Location $repoRoot
    try {
        $stackAttempted = $true
        Invoke-Compose -Arguments @('up', '-d', 'db', 'backend') | Out-Null
        Wait-ServiceHealthy -Service 'db' | Out-Null
        Wait-ServiceHealthy -Service 'backend' | Out-Null
        Assert-Equal -Actual (Get-BackendImageId) -Expected $currentImageId -Message 'La identidad actual no quedó activa'
        $flywayMode = Assert-FlywayHistory -Manifest $migrationManifest
        Assert-ControlPlaneDatabaseContract
        Pass "Versión actual healthy con Flyway $flywayMode en $($migrationManifest.LatestVersion)"

        Invoke-Sql -Sql "INSERT INTO tenants(id, code, name, status) VALUES ('$fixtureTenantId', '$fixtureTenantCode', 'Rollback verification', 'ACTIVE')" | Out-Null
        $studentResult = Invoke-Sql -Sql "INSERT INTO alumnos(tenant_id, nombre, apellido, fecha_incorporacion, activo) VALUES ('$fixtureTenantId', 'Rollback', '$marker', CURRENT_DATE, true) RETURNING id"
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
        } -MessageContains 'Metadata Flyway inconsistente' -FailureMessage "Imagen con Flyway V$incompatibleFlyway no fue rechazada"
        Assert-Equal -Actual (Get-BackendImageId) -Expected $currentImageId -Message 'Las guardas alteraron la identidad activa'
        Pass 'Guardas de confirmación y compatibilidad Flyway'

        $rollbackResult = @(& $rollbackScript -TargetBackendImage $rollbackImage `
            -ComposeFile $ComposeFile -EnvFile $envFile -ProjectName $project `
            -ExpectedCurrentImage $currentImage -BackupOutputDirectory $backupRoot `
            -ConfirmRollback)
        $rollbackJson = $rollbackResult[-1] | ConvertFrom-Json
        Assert-True -Condition (Test-Path -LiteralPath $rollbackJson.backupDirectory -PathType Container) -Message 'El rollback no produjo backup previo.'
        Assert-Equal -Actual $rollbackJson.targetImageId -Expected $rollbackImageId -Message 'El runtime no fijó la identidad objetivo construida'
        Assert-Equal -Actual (Get-BackendImageId) -Expected $rollbackImageId -Message 'La identidad rollback no quedó activa'
        Assert-Equal -Actual (Invoke-Sql -Sql "SELECT count(*) FROM alumnos WHERE id = $studentId AND apellido = '$marker'").Trim() -Expected 1 -Message 'El dato no sobrevivió al rollback'
        Assert-Equal -Actual (Assert-FlywayHistory -Manifest $migrationManifest) -Expected $flywayMode -Message 'Flyway cambió durante rollback'
        Assert-ControlPlaneDatabaseContract
        Pass "Rollback compatible con datos, control-plane y Flyway $($migrationManifest.LatestVersion) preservados"

        & $rollbackScript -TargetBackendImage $currentImage `
            -ComposeFile $ComposeFile -EnvFile $envFile -ProjectName $project `
            -ExpectedCurrentImage $rollbackImage -SkipBackup -ConfirmRollback | Out-Null
        Assert-Equal -Actual (Get-BackendImageId) -Expected $currentImageId -Message 'La identidad actual no fue restaurada'
        Assert-Equal -Actual (Invoke-Sql -Sql "SELECT count(*) FROM alumnos WHERE id = $studentId AND apellido = '$marker'").Trim() -Expected 1 -Message 'El dato no sobrevivió al retorno'
        Assert-Equal -Actual (Assert-FlywayHistory -Manifest $migrationManifest) -Expected $flywayMode -Message 'Flyway cambió al volver a actual'
        Assert-ControlPlaneDatabaseContract
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
        if ($dockerContextApplied -and $stackAttempted -and (Test-Path -LiteralPath $envFile)) {
            try { Invoke-Compose -Arguments @('down', '--volumes', '--remove-orphans') -IgnoreFailure | Out-Null }
            catch { $failures++; Write-Host "[FAIL] Cleanup Compose: $($_.Exception.Message)" -ForegroundColor Red }
        }
        if ($dockerContextApplied -and $imageMutationAttempted) {
            foreach ($image in @($currentImage, $rollbackImage, $incompatibleImage)) {
                try { Invoke-Native -FilePath 'docker' -Arguments @('image', 'rm', '-f', $image) -IgnoreFailure | Out-Null } catch { }
            }
        }
        if ($dockerContextApplied -and $projectSnapshotCaptured) {
            try {
                $projectAfter = Get-DockerProjectSnapshot -ProjectName $project
                Assert-True -Condition (Test-DockerProjectSnapshotInvariant -Before $projectBefore -After $projectAfter) `
                    -Message 'El proyecto efímero no volvió a su snapshot ausente exacto.'
                Assert-NoProjectResources
                Pass 'Proyecto efímero ausente antes y después del drill'
            }
            catch { $failures++; Write-Host "[FAIL] $($_.Exception.Message)" -ForegroundColor Red }
        }
        if ($workRootCreated -and (Test-Path -LiteralPath $workRoot)) {
            try {
                Assert-SafeTemporaryChild -Path $workRoot -AllowedRoot $tempRoot | Out-Null
                Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction Stop
            }
            catch { $failures++; Write-Host "[FAIL] Cleanup temporal: $($_.Exception.Message)" -ForegroundColor Red }
        }
    }
    if ($dockerContextApplied -and $protectedDemoSnapshotCaptured) {
        try {
            $protectedDemoAfter = Get-DockerProjectSnapshot -ProjectName 'gestudio-remote-demo'
            Assert-True -Condition (Test-DockerProjectSnapshotInvariant -Before $protectedDemoBefore -After $protectedDemoAfter) `
                -Message 'El proyecto protegido gestudio-remote-demo cambió durante el drill.'
            Pass 'Demo protegida invariante antes/después'
        }
        catch { $failures++; Write-Host "[FAIL] $($_.Exception.Message)" -ForegroundColor Red }
    }
    if ($dockerContextApplied) {
        try { [Environment]::SetEnvironmentVariable('DOCKER_CONTEXT', $dockerContextBackup, 'Process') }
        catch { $failures++; Write-Host '[FAIL] No se pudo restaurar DOCKER_CONTEXT.' -ForegroundColor Red }
        $dockerContextApplied = $false
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
