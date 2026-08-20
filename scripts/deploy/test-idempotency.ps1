[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$runId = [Guid]::NewGuid().ToString('N').Substring(0, 10)
$testRoot = Join-Path ([IO.Path]::GetTempPath()) "Gestudio Deploy Test $runId"
$resultRoot = Join-Path $repoRoot '.gestudio-deploy\test-results'
$resultPath = Join-Path $resultRoot "idempotency-$runId.json"
$startedAt = [DateTime]::UtcNow
$projects = New-Object System.Collections.Generic.List[string]
$images = New-Object System.Collections.Generic.List[string]
$results = [ordered]@{ runId = $runId; startedAtUtc = $startedAt.ToString('o') }

function Write-TestStatus {
    param([ValidateSet('INFO', 'PASS', 'WARN')][string] $Level, [string] $Message)
    Write-Host ('{0} [{1}] {2}' -f [DateTime]::UtcNow.ToString('o'), $Level, $Message)
}

function Invoke-Native {
    param(
        [Parameter(Mandatory)][string] $FilePath,
        [Parameter(Mandatory)][string[]] $Arguments,
        [switch] $Capture,
        [int[]] $ExpectedExitCodes = @(0)
    )

    $previous = $ErrorActionPreference
    $output = @()
    $nativeExitCode = -1
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $FilePath @Arguments 2>&1)
        $nativeExitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previous }
    $text = ($output | ForEach-Object { $_.ToString() }) -join "`n"
    if ($nativeExitCode -notin $ExpectedExitCodes) {
        $tail = (($text -split "`r?`n") | Select-Object -Last 80) -join "`n"
        throw "$FilePath fallo con codigo ${nativeExitCode}: $tail"
    }
    if ($Capture) { return $text.Trim() }
    if (-not [string]::IsNullOrWhiteSpace($text)) { Write-Host $text }
}

function Assert-LocalDockerTarget {
    param([Parameter(Mandatory)][string] $ProjectName)

    if ($ProjectName -ceq 'gestudio-remote-demo') {
        throw 'El proyecto gestudio-remote-demo está protegido.'
    }
    if (-not [string]::IsNullOrWhiteSpace($env:DOCKER_HOST)) {
        throw 'DOCKER_HOST no está permitido para este gate Docker local.'
    }
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'Docker CLI no está disponible.'
    }

    $context = Invoke-Native docker @('context', 'show') -Capture
    if ([string]::IsNullOrWhiteSpace($context) -or $context -match '(?i)(prod|production|stage|staging|remote|demo)') {
        throw "El contexto Docker '$context' no está permitido para este gate local."
    }
    $endpointJson = Invoke-Native docker @(
        'context', 'inspect', $context, '--format', '{{json .Endpoints.docker.Host}}'
    ) -Capture
    try { $endpoint = [string]($endpointJson | ConvertFrom-Json) }
    catch { throw 'No se pudo interpretar el endpoint del contexto Docker.' }
    $allowedEndpoints = @(
        'npipe:////./pipe/docker_engine',
        'npipe:////./pipe/dockerDesktopLinuxEngine',
        'unix:///var/run/docker.sock'
    )
    if (-not ($allowedEndpoints -contains $endpoint)) {
        throw "El endpoint Docker '$endpoint' no es local."
    }
    $osType = Invoke-Native docker @('--context', $context, 'info', '--format', '{{.OSType}}') -Capture
    if ($osType -cne 'linux') {
        throw "El daemon Docker debe ser Linux; OSType='$osType'."
    }
    return $context
}

function Get-TextHash {
    param([Parameter(Mandatory)][string] $Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function New-SyntheticSecret {
    $bytes = New-Object byte[] 48
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return ([BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
}

function New-SyntheticBase64Key {
    $bytes = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return [Convert]::ToBase64String($bytes)
}

function Get-FreePorts {
    param([int] $Count)
    $ports = New-Object System.Collections.Generic.List[int]
    while ($ports.Count -lt $Count) {
        $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
        try {
            $listener.Start()
            $port = ([Net.IPEndPoint]$listener.LocalEndpoint).Port
            if (-not $ports.Contains($port)) { $ports.Add($port) }
        }
        finally { $listener.Stop() }
    }
    return @($ports)
}

function Copy-WorkingSources {
    param([Parameter(Mandatory)][string] $Destination)
    [IO.Directory]::CreateDirectory($Destination) | Out-Null
    $files = Invoke-Native -FilePath 'git' -Arguments @(
        '-c', 'core.quotepath=false', '-C', $repoRoot, 'ls-files', '--cached', '--others', '--exclude-standard'
    ) -Capture
    foreach ($relative in ($files -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($relative)) { continue }
        $source = Join-Path $repoRoot ($relative -replace '/', '\')
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }
        $target = Join-Path $Destination ($relative -replace '/', '\')
        [IO.Directory]::CreateDirectory((Split-Path $target -Parent)) | Out-Null
        Copy-Item -LiteralPath $source -Destination $target -Force
    }
    Initialize-TestRepository -Path $Destination -Message 'Synthetic current deployment checkout'
}

function New-BaseSources {
    param([Parameter(Mandatory)][string] $Destination, [Parameter(Mandatory)][string] $Commit)
    [IO.Directory]::CreateDirectory($Destination) | Out-Null
    $archive = Join-Path $testRoot 'base.zip'
    Invoke-Native -FilePath 'git' -Arguments @('-C', $repoRoot, 'archive', '--format=zip', '--output', $archive, $Commit)
    Expand-Archive -LiteralPath $archive -DestinationPath $Destination
    Remove-Item -LiteralPath $archive -Force

    foreach ($relative in @(
        'deploy.cmd', '.gitignore', 'docker-compose.yml',
        'scripts\deploy', 'scripts\ops\backup-postgres.ps1',
        'scripts\ops\restore-postgres.ps1', 'scripts\db\10-create-application-role.sh',
        'backend\src\main\resources\application-dev.yml'
    )) {
        $source = Join-Path $repoRoot $relative
        $target = Join-Path $Destination $relative
        if (Test-Path -LiteralPath $source -PathType Container) {
            [IO.Directory]::CreateDirectory($target) | Out-Null
            Copy-Item -Path (Join-Path $source '*') -Destination $target -Recurse -Force
        }
        else {
            [IO.Directory]::CreateDirectory((Split-Path $target -Parent)) | Out-Null
            Copy-Item -LiteralPath $source -Destination $target -Force
        }
    }
    # V7 predates the application-role grants introduced by the tenant/RLS upgrade.
    # The compatibility fixture uses the migrator only for the historical base boot;
    # the current deployment must and does switch back to the restricted runtime role.
    $composePath = Join-Path $Destination 'docker-compose.yml'
    $compose = [IO.File]::ReadAllText($composePath)
    $compose = $compose.Replace(
        'SPRING_DATASOURCE_USERNAME: ${POSTGRES_APP_USER:-gestudio_app_local}',
        'SPRING_DATASOURCE_USERNAME: ${POSTGRES_USER:-postgres}'
    ).Replace(
        'SPRING_DATASOURCE_PASSWORD: ${POSTGRES_APP_PASSWORD:-local-only-app-change-me}',
        'SPRING_DATASOURCE_PASSWORD: ${POSTGRES_PASSWORD:-local-only-change-me}'
    )
    [IO.File]::WriteAllText($composePath, $compose, [Text.UTF8Encoding]::new($false))
    Initialize-TestRepository -Path $Destination -Message "Synthetic V7 checkout from $Commit"
}

function Initialize-TestRepository {
    param([Parameter(Mandatory)][string] $Path, [Parameter(Mandatory)][string] $Message)
    Invoke-Native -FilePath 'git' -Arguments @('-C', $Path, 'init', '-q')
    Invoke-Native -FilePath 'git' -Arguments @('-C', $Path, 'config', 'core.autocrlf', 'false')
    Invoke-Native -FilePath 'git' -Arguments @('-C', $Path, 'add', '-A')
    Invoke-Native -FilePath 'git' -Arguments @(
        '-c', 'core.autocrlf=false', '-C', $Path, '-c', 'user.name=Gestudio Deployment Test',
        '-c', 'user.email=deploy-test@invalid.local', 'commit', '-q', '-m', $Message
    )
}

function New-TestConfiguration {
    param(
        [Parameter(Mandatory)][string] $SourceRoot,
        [Parameter(Mandatory)][string] $StateRoot,
        [Parameter(Mandatory)][string] $ProjectName,
        [Parameter(Mandatory)][int[]] $Ports
    )
    $configPath = Join-Path $StateRoot 'config\deploy.env'
    [IO.Directory]::CreateDirectory((Split-Path $configPath -Parent)) | Out-Null
    $overrides = @{
        COMPOSE_PROJECT_NAME = $ProjectName
        POSTGRES_DB = 'gestudio_test'
        POSTGRES_USER = 'gestudio_migrator'
        POSTGRES_PASSWORD = New-SyntheticSecret
        POSTGRES_APP_USER = 'gestudio_runtime'
        POSTGRES_APP_PASSWORD = New-SyntheticSecret
        POSTGRES_CONTROL_USER = 'gestudio_control_runtime'
        POSTGRES_CONTROL_PASSWORD = New-SyntheticSecret
        POSTGRES_PORT = [string]$Ports[0]
        BACKEND_PORT = [string]$Ports[1]
        FRONTEND_PORT = [string]$Ports[2]
        BACKEND_IMAGE = "gestudio-backend:$ProjectName"
        FRONTEND_IMAGE = "gestudio-frontend:$ProjectName"
        VITE_API_BASE_URL = "http://127.0.0.1:$($Ports[1])/api"
        JWT_SECRET = New-SyntheticSecret
        JWT_ISSUER = $ProjectName
        APP_PLATFORM_MFA_ENCRYPTION_KEY = New-SyntheticBase64Key
        APP_CORS_ALLOWED_ORIGINS = "http://127.0.0.1:$($Ports[2])"
        APP_OBSERVABILITY_METRICS_TOKEN = New-SyntheticSecret
        APP_SECURITY_REFRESH_COOKIE_NAME = "${ProjectName}_refresh"
    }
    $lines = foreach ($line in [IO.File]::ReadAllLines((Join-Path $SourceRoot 'scripts\deploy\deploy.env.example'))) {
        $separator = $line.IndexOf('=')
        if ($separator -gt 0) {
            $name = $line.Substring(0, $separator).Trim()
            if ($overrides.ContainsKey($name)) { "$name=$($overrides[$name])"; continue }
        }
        $line
    }
    [IO.File]::WriteAllText($configPath, (($lines -join [Environment]::NewLine) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    $images.Add($overrides.BACKEND_IMAGE)
    $images.Add($overrides.FRONTEND_IMAGE)
    return $configPath
}

function Invoke-Launcher {
    param(
        [Parameter(Mandatory)][string] $SourceRoot,
        [string] $StateRoot,
        [string] $Mode,
        [string] $DockerHost,
        [int[]] $ExpectedExitCodes = @(0)
    )
    $oldStateRoot = $env:GESTUDIO_DEPLOY_STATE_ROOT
    $oldDockerHost = $env:DOCKER_HOST
    try {
        if ([string]::IsNullOrWhiteSpace($StateRoot)) { Remove-Item Env:GESTUDIO_DEPLOY_STATE_ROOT -ErrorAction SilentlyContinue }
        else { $env:GESTUDIO_DEPLOY_STATE_ROOT = $StateRoot }
        if ([string]::IsNullOrWhiteSpace($DockerHost)) { Remove-Item Env:DOCKER_HOST -ErrorAction SilentlyContinue }
        else { $env:DOCKER_HOST = $DockerHost }
        $command = 'call "' + (Join-Path $SourceRoot 'deploy.cmd') + '"'
        if (-not [string]::IsNullOrWhiteSpace($Mode)) { $command += " $Mode" }
        Push-Location ([IO.Path]::GetTempPath())
        try {
            & cmd.exe /d /c $command | ForEach-Object { Write-Host $_ }
            $code = $LASTEXITCODE
        }
        finally { Pop-Location }
        if ($code -notin $ExpectedExitCodes) { throw "deploy.cmd devolvio $code; se esperaba $($ExpectedExitCodes -join ',')." }
        return $code
    }
    finally {
        if ($null -eq $oldStateRoot) { Remove-Item Env:GESTUDIO_DEPLOY_STATE_ROOT -ErrorAction SilentlyContinue }
        else { $env:GESTUDIO_DEPLOY_STATE_ROOT = $oldStateRoot }
        if ($null -eq $oldDockerHost) { Remove-Item Env:DOCKER_HOST -ErrorAction SilentlyContinue }
        else { $env:DOCKER_HOST = $oldDockerHost }
    }
}

function Get-ProjectIds {
    param([Parameter(Mandatory)][string] $ProjectName, [ValidateSet('container', 'volume', 'network')][string] $Kind)
    $arguments = switch ($Kind) {
        container { @('ps', '-a', '--filter', "label=com.docker.compose.project=$ProjectName", '-q') }
        volume { @('volume', 'ls', '--filter', "label=com.docker.compose.project=$ProjectName", '-q') }
        network { @('network', 'ls', '--filter', "label=com.docker.compose.project=$ProjectName", '-q') }
    }
    $raw = Invoke-Native -FilePath 'docker' -Arguments $arguments -Capture
    return @(($raw -split "`r?`n") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object)
}

function Invoke-DatabaseQuery {
    param([Parameter(Mandatory)][string] $ContainerId, [Parameter(Mandatory)][string] $Sql, [ValidateSet('migration', 'runtime', 'control')][string] $Role = 'migration')
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Sql))
    $shell = if ($Role -eq 'runtime') {
        'printf "%s" "$1" | base64 -d | PGPASSWORD="$POSTGRES_APP_PASSWORD" psql --no-psqlrc -h 127.0.0.1 -U "$POSTGRES_APP_USER" -d "$POSTGRES_DB" -Atq -f -'
    }
    elseif ($Role -eq 'control') {
        'printf "%s" "$1" | base64 -d | PGPASSWORD="$POSTGRES_CONTROL_PASSWORD" psql --no-psqlrc -h 127.0.0.1 -U "$POSTGRES_CONTROL_USER" -d "$POSTGRES_DB" -Atq -f -'
    }
    else {
        'printf "%s" "$1" | base64 -d | PGPASSWORD="$POSTGRES_PASSWORD" psql --no-psqlrc -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atq -f -'
    }
    return Invoke-Native -FilePath 'docker' -Arguments @('exec', $ContainerId, 'sh', '-ec', $shell, 'sh', $encoded) -Capture
}

function Get-DeploymentSnapshot {
    param([Parameter(Mandatory)][string] $ProjectName, [Parameter(Mandatory)][string] $StateRoot)
    $statePath = Join-Path $StateRoot 'state\deployment.json'
    $configPath = Join-Path $StateRoot 'config\deploy.env'
    $state = ConvertFrom-Json ([IO.File]::ReadAllText($statePath))
    $db = Invoke-Native -FilePath 'docker' -Arguments @(
        'ps', '--filter', "label=com.docker.compose.project=$ProjectName", '--filter', 'label=com.docker.compose.service=db', '-q'
    ) -Capture
    $volume = Invoke-Native -FilePath 'docker' -Arguments @(
        'inspect', '--format', '{{range .Mounts}}{{if eq .Destination "/var/lib/postgresql/data"}}{{.Name}}{{end}}{{end}}', $db
    ) -Capture
    $network = Invoke-Native -FilePath 'docker' -Arguments @(
        'inspect', '--format', '{{range $name, $value := .NetworkSettings.Networks}}{{$name}}{{end}}', $db
    ) -Capture
    $secretNames = @(
        'POSTGRES_PASSWORD', 'POSTGRES_APP_PASSWORD', 'POSTGRES_CONTROL_PASSWORD',
        'JWT_SECRET', 'APP_PLATFORM_MFA_ENCRYPTION_KEY', 'APP_OBSERVABILITY_METRICS_TOKEN'
    )
    $secretLines = [IO.File]::ReadAllLines($configPath) | Where-Object {
        $name = ($_ -split '=', 2)[0]
        $name -in $secretNames
    } | Sort-Object
    return [pscustomobject]@{
        containers = @(Get-ProjectIds -ProjectName $ProjectName -Kind container)
        volume = $volume
        network = $network
        secretHash = Get-TextHash -Text ($secretLines -join "`n")
        configHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $configPath).Hash.ToLowerInvariant()
        stateHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $statePath).Hash.ToLowerInvariant()
        fingerprint = [string]$state.fingerprint
        flyway = Invoke-DatabaseQuery -ContainerId $db -Sql "SELECT count(*)::text || '|' || max(version::int)::text FROM flyway_schema_history WHERE success;"
        bootstrap = [pscustomobject]@{
            tenants = [int]$state.bootstrap.tenants
            memberships = [int]$state.bootstrap.memberships
            bootstrapUsers = [int]$state.bootstrap.bootstrapUsers
            bootstrapLinkedAdmins = [int]$state.bootstrap.bootstrapLinkedAdmins
            platformAdmins = [int]$state.bootstrap.platformAdmins
            roles = [int]$state.bootstrap.roles
            permissions = [int]$state.bootstrap.permissions
            membershipRoles = [int]$state.bootstrap.membershipRoles
        }
        lastBackupPath = [string]$state.lastBackupPath
    }
}

function Assert-Equal {
    param([Parameter(Mandatory)] $Expected, [Parameter(Mandatory)] $Actual, [Parameter(Mandatory)][string] $Message)
    if (($Expected | ConvertTo-Json -Compress -Depth 10) -cne ($Actual | ConvertTo-Json -Compress -Depth 10)) {
        throw "$Message Esperado='$Expected' Actual='$Actual'."
    }
}

function Assert-SnapshotStable {
    param([Parameter(Mandatory)] $Before, [Parameter(Mandatory)] $After)
    Assert-Equal $Before.containers $After.containers 'Se recrearon contenedores sin necesidad.'
    Assert-Equal $Before.volume $After.volume 'Cambio el volumen PostgreSQL.'
    Assert-Equal $Before.network $After.network 'Cambio la red Compose.'
    Assert-Equal $Before.secretHash $After.secretHash 'Cambiaron los secretos.'
    Assert-Equal $Before.configHash $After.configHash 'Cambio la configuracion efectiva.'
    Assert-Equal $Before.fingerprint $After.fingerprint 'Cambio el fingerprint.'
    Assert-Equal $Before.flyway $After.flyway 'Cambio el historial Flyway.'
    Assert-Equal $Before.bootstrap $After.bootstrap 'Cambiaron los datos bootstrap.'
}

function Set-TestEnvironmentValue {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $Value
    )

    $content = [IO.File]::ReadAllText($Path)
    $pattern = '(?m)^' + [regex]::Escape($Name) + '=.*$'
    $matcher = [regex]::new($pattern)
    if (-not $matcher.IsMatch($content)) {
        throw "No existe $Name en la configuración sintética."
    }
    $updated = $matcher.Replace($content, "$Name=$Value", 1)
    [IO.File]::WriteAllText($Path, $updated, [Text.UTF8Encoding]::new($false))
}

function Get-ProjectSnapshot {
    param([Parameter(Mandatory)][string] $ProjectName)
    return [pscustomobject]@{
        containers = @(Get-ProjectIds -ProjectName $ProjectName -Kind container)
        volumes = @(Get-ProjectIds -ProjectName $ProjectName -Kind volume)
        networks = @(Get-ProjectIds -ProjectName $ProjectName -Kind network)
    }
}

function Remove-TestProject {
    param([Parameter(Mandatory)][string] $ProjectName)
    $snapshot = Get-ProjectSnapshot -ProjectName $ProjectName
    if ($snapshot.containers.Count -gt 0) { $null = Invoke-Native -FilePath 'docker' -Arguments (@('container', 'rm', '-f') + $snapshot.containers) -Capture }
    if ($snapshot.volumes.Count -gt 0) { $null = Invoke-Native -FilePath 'docker' -Arguments (@('volume', 'rm') + $snapshot.volumes) -Capture }
    if ($snapshot.networks.Count -gt 0) { $null = Invoke-Native -FilePath 'docker' -Arguments (@('network', 'rm') + $snapshot.networks) -Capture }
}

function Assert-PreservedResources {
    param([Parameter(Mandatory)][string[]] $Before, [Parameter(Mandatory)][string[]] $After, [Parameter(Mandatory)][string] $Kind)
    $missing = @($Before | Where-Object { $_ -notin $After })
    if ($missing.Count -gt 0) { throw "Se eliminaron recursos ajenos de tipo ${Kind}: $($missing -join ',')." }
}

function Get-AllDockerResources {
    return [pscustomobject]@{
        containers = @((Invoke-Native docker @('ps', '-a', '-q') -Capture) -split "`r?`n" | Where-Object { $_ } | Sort-Object)
        volumes = @((Invoke-Native docker @('volume', 'ls', '-q') -Capture) -split "`r?`n" | Where-Object { $_ } | Sort-Object)
        networks = @((Invoke-Native docker @('network', 'ls', '-q') -Capture) -split "`r?`n" | Where-Object { $_ } | Sort-Object)
    }
}

function Invoke-IdempotencyScenario {
    $sourceRoot = Join-Path $testRoot 'Checkout With Spaces'
    Copy-WorkingSources -Destination $sourceRoot
    $project = "gestudio-idem-$runId"
    $projects.Add($project)
    $ports = Get-FreePorts 3
    $stateRoot = Join-Path $sourceRoot '.gestudio-deploy'
    $configPath = New-TestConfiguration -SourceRoot $sourceRoot -StateRoot $stateRoot -ProjectName $project -Ports $ports
    $backupRoot = Join-Path $stateRoot 'backups'

    $watch = [Diagnostics.Stopwatch]::StartNew()
    $null = Invoke-Launcher -SourceRoot $sourceRoot -Mode '--help'
    $watch.Stop()
    $helpDuration = [Math]::Round($watch.Elapsed.TotalSeconds, 2)
    $configHashBeforeDryRun = (Get-FileHash -Algorithm SHA256 -LiteralPath $configPath).Hash
    $watch.Restart()
    $null = Invoke-Launcher -SourceRoot $sourceRoot -Mode '--dry-run'
    $watch.Stop()
    $dryRunDuration = [Math]::Round($watch.Elapsed.TotalSeconds, 2)
    Assert-Equal $configHashBeforeDryRun (Get-FileHash -Algorithm SHA256 -LiteralPath $configPath).Hash '--dry-run modifico la configuracion.'
    $dryRunResources = Get-ProjectSnapshot -ProjectName $project
    Assert-Equal 0 $dryRunResources.containers.Count '--dry-run creo contenedores.'
    Assert-Equal 0 $dryRunResources.volumes.Count '--dry-run creo volumenes.'
    Assert-Equal 0 $dryRunResources.networks.Count '--dry-run creo redes.'
    if (Test-Path -LiteralPath (Join-Path $stateRoot 'state\deployment.json') -PathType Leaf) { throw '--dry-run escribio estado exitoso.' }

    $watch.Restart()
    $null = Invoke-Launcher -SourceRoot $sourceRoot
    $watch.Stop()
    $first = Get-DeploymentSnapshot -ProjectName $project -StateRoot $stateRoot
    $firstDuration = [Math]::Round($watch.Elapsed.TotalSeconds, 2)

    $backupCount = @(Get-ChildItem -LiteralPath $backupRoot -Directory -ErrorAction SilentlyContinue).Count
    $watch.Restart()
    $null = Invoke-Launcher -SourceRoot $sourceRoot
    $watch.Stop()
    $second = Get-DeploymentSnapshot -ProjectName $project -StateRoot $stateRoot
    Assert-SnapshotStable -Before $first -After $second
    Assert-Equal $backupCount @(Get-ChildItem -LiteralPath $backupRoot -Directory -ErrorAction SilentlyContinue).Count 'Se creo un backup sin cambios.'
    Assert-Equal '' (Invoke-Native git @('-C', $sourceRoot, 'status', '--porcelain') -Capture) 'El despliegue modifico archivos versionados.'
    $secondDuration = [Math]::Round($watch.Elapsed.TotalSeconds, 2)

    $generatedArtifacts = [ordered]@{
        'frontend\coverage\synthetic-coverage.json' = '{"generated":true}'
        'frontend\quality-reports\synthetic-report.json' = '{"generated":true}'
        'frontend\frontend-sbom.cdx.json' = '{"bomFormat":"CycloneDX"}'
        'frontend\e2e\tsconfig.tsbuildinfo' = 'synthetic generated build metadata'
    }
    foreach ($entry in $generatedArtifacts.GetEnumerator()) {
        $artifactPath = Join-Path $sourceRoot $entry.Key
        [IO.Directory]::CreateDirectory((Split-Path $artifactPath -Parent)) | Out-Null
        [IO.File]::WriteAllText($artifactPath, [string]$entry.Value, [Text.UTF8Encoding]::new($false))
    }
    Assert-Equal '' (Invoke-Native git @('-C', $sourceRoot, 'status', '--porcelain') -Capture) `
        'Los artefactos generados no quedaron ignorados por Git.'
    $null = Invoke-Launcher -SourceRoot $sourceRoot
    $afterGeneratedArtifacts = Get-DeploymentSnapshot -ProjectName $project -StateRoot $stateRoot
    Assert-SnapshotStable -Before $second -After $afterGeneratedArtifacts
    Assert-Equal $backupCount @(Get-ChildItem -LiteralPath $backupRoot -Directory -ErrorAction SilentlyContinue).Count `
        'Los artefactos generados cambiaron el plan o crearon un backup.'

    $beforeVerifyStateHash = $second.stateHash
    $watch.Restart()
    $null = Invoke-Launcher -SourceRoot $sourceRoot -Mode '--verify-only'
    $watch.Stop()
    $verified = Get-DeploymentSnapshot -ProjectName $project -StateRoot $stateRoot
    Assert-SnapshotStable -Before $second -After $verified
    Assert-Equal $beforeVerifyStateHash $verified.stateHash '--verify-only modifico el estado.'
    $verifyDuration = [Math]::Round($watch.Elapsed.TotalSeconds, 2)

    $oldMode = $env:GESTUDIO_DEPLOY_TEST_MODE
    $oldDelay = $env:GESTUDIO_DEPLOY_TEST_LOCK_DELAY_SECONDS
    $firstOutput = Join-Path $testRoot 'concurrent-first.stdout.log'
    $firstError = Join-Path $testRoot 'concurrent-first.stderr.log'
    try {
        $env:GESTUDIO_DEPLOY_TEST_MODE = '1'
        $env:GESTUDIO_DEPLOY_TEST_LOCK_DELAY_SECONDS = '6'
        $command = 'call "' + (Join-Path $sourceRoot 'deploy.cmd') + '"'
        $process = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/d', '/c', $command) -PassThru -WindowStyle Hidden `
            -RedirectStandardOutput $firstOutput -RedirectStandardError $firstError
        Start-Sleep -Seconds 2
        $secondLockExit = Invoke-Launcher -SourceRoot $sourceRoot -ExpectedExitCodes @(8)
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw "El despliegue que tenia el lock devolvio $($process.ExitCode)." }
    }
    finally {
        if ($null -eq $oldMode) { Remove-Item Env:GESTUDIO_DEPLOY_TEST_MODE -ErrorAction SilentlyContinue } else { $env:GESTUDIO_DEPLOY_TEST_MODE = $oldMode }
        if ($null -eq $oldDelay) { Remove-Item Env:GESTUDIO_DEPLOY_TEST_LOCK_DELAY_SECONDS -ErrorAction SilentlyContinue } else { $env:GESTUDIO_DEPLOY_TEST_LOCK_DELAY_SECONDS = $oldDelay }
    }
    Assert-SnapshotStable -Before $verified -After (Get-DeploymentSnapshot -ProjectName $project -StateRoot $stateRoot)

    $dbBeforeRotation = Invoke-Native docker @(
        'ps', '--filter', "label=com.docker.compose.project=$project",
        '--filter', 'label=com.docker.compose.service=db', '-q'
    ) -Capture
    $controlPasswordHashBefore = Invoke-DatabaseQuery -ContainerId $dbBeforeRotation `
        -Sql "SELECT rolpassword FROM pg_catalog.pg_authid WHERE rolname = 'gestudio_control_runtime';"
    Set-TestEnvironmentValue -Path $configPath -Name 'POSTGRES_CONTROL_PASSWORD' -Value (New-SyntheticSecret)
    $null = Invoke-Launcher -SourceRoot $sourceRoot
    $rotated = Get-DeploymentSnapshot -ProjectName $project -StateRoot $stateRoot
    $dbAfterRotation = Invoke-Native docker @(
        'ps', '--filter', "label=com.docker.compose.project=$project",
        '--filter', 'label=com.docker.compose.service=db', '-q'
    ) -Capture
    $controlPasswordHashAfter = Invoke-DatabaseQuery -ContainerId $dbAfterRotation `
        -Sql "SELECT rolpassword FROM pg_catalog.pg_authid WHERE rolname = 'gestudio_control_runtime';"
    if ($controlPasswordHashBefore -ceq $controlPasswordHashAfter) {
        throw 'La rotación no cambió el hash SCRAM del login control-plane.'
    }
    if ($verified.secretHash -ceq $rotated.secretHash -or $verified.fingerprint -ceq $rotated.fingerprint) {
        throw 'La rotación no cambió secretos y fingerprint como se esperaba.'
    }
    Assert-Equal $verified.volume $rotated.volume 'La rotación reemplazó el volumen PostgreSQL.'
    Assert-Equal $verified.flyway $rotated.flyway 'La rotación cambió Flyway.'
    Assert-Equal $verified.bootstrap $rotated.bootstrap 'La rotación cambió el bootstrap.'
    Assert-Equal $backupCount @(Get-ChildItem -LiteralPath $backupRoot -Directory -ErrorAction SilentlyContinue).Count `
        'La rotación de credenciales creó un backup de esquema innecesario.'
    $null = Invoke-Launcher -SourceRoot $sourceRoot
    Assert-SnapshotStable -Before $rotated -After (Get-DeploymentSnapshot -ProjectName $project -StateRoot $stateRoot)

    $stateHashBeforeInvalidDocker = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $stateRoot 'state\deployment.json')).Hash
    $resourceBeforeInvalidDocker = Get-ProjectSnapshot -ProjectName $project
    $invalidDockerExit = Invoke-Launcher -SourceRoot $sourceRoot -Mode '--verify-only' `
        -DockerHost "npipe:////./pipe/gestudio-missing-$runId" -ExpectedExitCodes @(4)
    $stateHashAfterInvalidDocker = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $stateRoot 'state\deployment.json')).Hash
    Assert-Equal $stateHashBeforeInvalidDocker $stateHashAfterInvalidDocker 'Docker inaccesible modifico el estado exitoso.'
    Assert-Equal $resourceBeforeInvalidDocker (Get-ProjectSnapshot -ProjectName $project) 'Docker inaccesible modifico recursos.'

    Write-TestStatus PASS 'Idempotencia, rotación, verify-only, lock, ruta con espacios y Docker inaccesible verificados'
    return [ordered]@{
        project = $project
        sourcePath = $sourceRoot
        help = [ordered]@{ durationSeconds = $helpDuration; exitCode = 0 }
        dryRun = [ordered]@{ durationSeconds = $dryRunDuration; exitCode = 0; resourcesCreated = 0; configUnchanged = $true }
        first = [ordered]@{ durationSeconds = $firstDuration; fingerprint = $first.fingerprint; volume = $first.volume; secretHash = $first.secretHash; flyway = $first.flyway; bootstrap = $first.bootstrap; containers = $first.containers }
        second = [ordered]@{ durationSeconds = $secondDuration; fingerprint = $second.fingerprint; volume = $second.volume; secretHash = $second.secretHash; flyway = $second.flyway; bootstrap = $second.bootstrap; containers = $second.containers }
        generatedArtifacts = [ordered]@{ ignored = $true; fingerprintStable = $true; backupCountStable = $true }
        verifyOnly = [ordered]@{ durationSeconds = $verifyDuration; stateUnchanged = $true }
        concurrency = [ordered]@{ competingExitCode = $secondLockExit; ownerExitCode = 0 }
        credentialRotation = [ordered]@{ controlPlane = $true; volumePreserved = $true; flywayPreserved = $true; reexecutionStable = $true }
        invalidDocker = [ordered]@{ exitCode = $invalidDockerExit; stateUnchanged = $true; resourcesUnchanged = $true }
    }
}

function Invoke-UpgradeScenario {
    $currentVersions = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'backend/src/main/resources/db/migration') -Filter 'V*__*.sql' -File | ForEach-Object {
        if ($_.Name -match '^V(?<version>[0-9]+)__') { [int]$matches.version }
    } | Sort-Object)
    if ($currentVersions.Count -eq 0) { throw 'No se pudo derivar la versión Flyway actual.' }
    $currentLatest = $currentVersions[-1]
    $v8Commit = (Invoke-Native git @(
        '-C', $repoRoot, 'log', '-1', '--diff-filter=A', '--format=%H', '--',
        'backend/src/main/resources/db/migration/V8__tenant_control_plane.sql'
    ) -Capture).Trim()
    if ([string]::IsNullOrWhiteSpace($v8Commit)) { throw 'No se pudo derivar el commit que introdujo V8.' }
    $baseCommit = (Invoke-Native git @('-C', $repoRoot, 'rev-parse', "${v8Commit}^") -Capture).Trim()
    $baseRoot = Join-Path $testRoot 'Upgrade Base V7'
    $currentRoot = Join-Path $testRoot "Upgrade Current V$currentLatest"
    New-BaseSources -Destination $baseRoot -Commit $baseCommit
    Copy-WorkingSources -Destination $currentRoot

    $project = "gestudio-upgrade-$runId"
    $projects.Add($project)
    $ports = Get-FreePorts 3
    $stateRoot = Join-Path $testRoot 'Upgrade Shared State'
    $null = New-TestConfiguration -SourceRoot $currentRoot -StateRoot $stateRoot -ProjectName $project -Ports $ports

    $null = Invoke-Launcher -SourceRoot $baseRoot -StateRoot $stateRoot
    $base = Get-DeploymentSnapshot -ProjectName $project -StateRoot $stateRoot
    $baseFlywayParts = $base.flyway.Split('|')
    if ($baseFlywayParts.Count -ne 2 -or $baseFlywayParts[0] -ne $baseFlywayParts[1]) {
        throw "La versión histórica base no quedó en una cadena V completa: $($base.flyway)"
    }
    $baseVersion = [int]$baseFlywayParts[1]
    $db = Invoke-Native docker @('ps', '--filter', "label=com.docker.compose.project=$project", '--filter', 'label=com.docker.compose.service=db', '-q') -Capture
    $sentinel = "UPGRADE_SENTINEL_$runId"
    $null = Invoke-DatabaseQuery -ContainerId $db -Sql "INSERT INTO metodo_pagos(descripcion, activo, recargo) VALUES ('$sentinel', true, 0);"
    $databaseAclBefore = Invoke-DatabaseQuery -ContainerId $db -Sql "SELECT coalesce(datacl::text, '') FROM pg_database WHERE datname = current_database();"
    $migratorGrantBefore = Invoke-DatabaseQuery -ContainerId $db -Sql "SELECT has_table_privilege('gestudio_migrator','public.metodo_pagos','SELECT,INSERT,UPDATE,DELETE');"
    Assert-Equal 't' $migratorGrantBefore 'El migrador base no tenia los grants esperados.'

    $backupCountBefore = @(Get-ChildItem -LiteralPath (Join-Path $stateRoot 'backups') -Directory -ErrorAction SilentlyContinue).Count
    $null = Invoke-Launcher -SourceRoot $currentRoot -StateRoot $stateRoot
    $upgraded = Get-DeploymentSnapshot -ProjectName $project -StateRoot $stateRoot
    $db = Invoke-Native docker @('ps', '--filter', "label=com.docker.compose.project=$project", '--filter', 'label=com.docker.compose.service=db', '-q') -Capture
    Assert-Equal "$currentLatest|$currentLatest" $upgraded.flyway "El upgrade no convergió a V$currentLatest."
    Assert-Equal $base.volume $upgraded.volume 'El upgrade reemplazo el volumen PostgreSQL.'
    Assert-Equal $base.secretHash $upgraded.secretHash 'El upgrade roto secretos.'
    Assert-Equal '1' (Invoke-DatabaseQuery -ContainerId $db -Sql "SELECT count(*) FROM metodo_pagos WHERE descripcion = '$sentinel';") 'El upgrade no conservo los datos representativos.'
    Assert-Equal $databaseAclBefore (Invoke-DatabaseQuery -ContainerId $db -Sql "SELECT coalesce(datacl::text, '') FROM pg_database WHERE datname = current_database();") 'El upgrade cambio las ACL de la base.'
    Assert-Equal 't' (Invoke-DatabaseQuery -ContainerId $db -Sql "SELECT has_table_privilege('gestudio_migrator','public.metodo_pagos','SELECT,INSERT,UPDATE,DELETE');") 'El upgrade no conservo los grants del migrador.'
    Assert-Equal 't' (Invoke-DatabaseQuery -ContainerId $db -Sql "SELECT has_table_privilege('gestudio_runtime','public.metodo_pagos','SELECT,INSERT,UPDATE,DELETE');") 'El upgrade no establecio los grants runtime.'
    Assert-Equal 'f' (Invoke-DatabaseQuery -ContainerId $db -Sql "SELECT has_table_privilege('gestudio_control_runtime','public.metodo_pagos','SELECT');") 'El runtime de control-plane obtuvo acceso al dominio tenant.'
    Assert-Equal 't' (Invoke-DatabaseQuery -ContainerId $db -Sql "SELECT has_table_privilege('gestudio_control_runtime','public.tenants','SELECT') AND has_table_privilege('gestudio_control_runtime','public.tenants','INSERT') AND has_table_privilege('gestudio_control_runtime','public.tenants','UPDATE');") 'Faltan grants mínimos del runtime de control-plane.'
    Assert-Equal 'GREEN' (Invoke-DatabaseQuery -ContainerId $db -Role runtime -Sql 'SELECT status FROM public.v_multitenancy_migration_health;') 'RLS no quedo GREEN.'
    $backupCountAfter = @(Get-ChildItem -LiteralPath (Join-Path $stateRoot 'backups') -Directory -ErrorAction SilentlyContinue).Count
    Assert-Equal ($backupCountBefore + 1) $backupCountAfter 'El upgrade no creo exactamente un backup.'
    if ([string]::IsNullOrWhiteSpace($upgraded.lastBackupPath) -or -not (Test-Path -LiteralPath $upgraded.lastBackupPath -PathType Container)) {
        throw 'El backup del upgrade no quedo registrado o no existe.'
    }
    $manifest = ConvertFrom-Json ([IO.File]::ReadAllText((Join-Path $upgraded.lastBackupPath 'manifest.json')))
    Assert-Equal $baseVersion ([int]$manifest.flywayLatestVersion) 'El backup no corresponde al estado histórico previo.'

    $null = Invoke-Launcher -SourceRoot $currentRoot -StateRoot $stateRoot
    $third = Get-DeploymentSnapshot -ProjectName $project -StateRoot $stateRoot
    Assert-SnapshotStable -Before $upgraded -After $third
    Assert-Equal $backupCountAfter @(Get-ChildItem -LiteralPath (Join-Path $stateRoot 'backups') -Directory).Count 'La reejecucion posterior creo otro backup.'
    Assert-Equal '1' (Invoke-DatabaseQuery -ContainerId $db -Sql "SELECT count(*) FROM metodo_pagos WHERE descripcion = '$sentinel';") 'La reejecucion duplico o elimino datos.'

    Write-TestStatus PASS "Upgrade V$baseVersion a V$currentLatest con backup, ACL, grants, datos y RLS verificado"
    return [ordered]@{
        project = $project
        baseVersion = $baseVersion
        finalVersion = $currentLatest
        volumeBefore = $base.volume
        volumeAfter = $upgraded.volume
        secretHashBefore = $base.secretHash
        secretHashAfter = $upgraded.secretHash
        backupPath = $upgraded.lastBackupPath
        backupValidated = $true
        databaseAclPreserved = $true
        migratorGrantsPreserved = $true
        runtimeGrantsEstablished = $true
        controlPlaneLeastPrivilege = $true
        dataPreserved = $true
        rls = 'GREEN'
        finalReexecutionStable = $true
    }
}

try {
    Write-TestStatus INFO "Inicio de gate Docker aislado $runId"
    $null = Assert-LocalDockerTarget -ProjectName "gestudio-idempotency-$runId"
    $null = Invoke-Native docker @('version') -Capture
    $null = Invoke-Native docker @('compose', 'version') -Capture
    $protectedBefore = Get-ProjectSnapshot -ProjectName 'gestudio-remote-demo'
    $allBefore = Get-AllDockerResources

    [IO.Directory]::CreateDirectory($testRoot) | Out-Null
    $results.idempotency = Invoke-IdempotencyScenario
    $results.upgrade = Invoke-UpgradeScenario

    foreach ($project in $projects) { Remove-TestProject -ProjectName $project }
    foreach ($imageName in $images) {
        $null = Invoke-Native docker @('image', 'rm', $imageName) -Capture -ExpectedExitCodes @(0, 1)
    }
    $protectedAfter = Get-ProjectSnapshot -ProjectName 'gestudio-remote-demo'
    Assert-Equal $protectedBefore $protectedAfter 'La demo protegida cambio durante la prueba.'
    $allAfter = Get-AllDockerResources
    Assert-PreservedResources $allBefore.containers $allAfter.containers 'contenedor'
    Assert-PreservedResources $allBefore.volumes $allAfter.volumes 'volumen'
    Assert-PreservedResources $allBefore.networks $allAfter.networks 'red'

    $results.cleanup = [ordered]@{
        testProjectsRemoved = $true
        protectedDemoUnchanged = $true
        foreignContainersRemoved = 0
        foreignVolumesRemoved = 0
        foreignNetworksRemoved = 0
    }
    $results.completedAtUtc = [DateTime]::UtcNow.ToString('o')
    $results.durationSeconds = [Math]::Round(([DateTime]::UtcNow - $startedAt).TotalSeconds, 2)
    $results.status = 'PASS'
    [IO.Directory]::CreateDirectory($resultRoot) | Out-Null
    [IO.File]::WriteAllText($resultPath, (($results | ConvertTo-Json -Depth 12) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    Write-TestStatus PASS "Gate completo en $($results.durationSeconds) s. Evidencia: $resultPath"
}
catch {
    Write-Host ('{0} [ERROR] {1} (linea {2})' -f [DateTime]::UtcNow.ToString('o'), $_.Exception.Message, $_.InvocationInfo.ScriptLineNumber)
    throw
}
finally {
    foreach ($project in $projects) {
        try { Remove-TestProject -ProjectName $project } catch { Write-TestStatus WARN "No se pudo limpiar ${project}: $($_.Exception.Message)" }
    }
    foreach ($imageName in $images) {
        try { $null = Invoke-Native docker @('image', 'rm', $imageName) -Capture -ExpectedExitCodes @(0, 1) } catch { Write-TestStatus WARN "No se pudo limpiar la imagen ${imageName}: $($_.Exception.Message)" }
    }
    if (Test-Path -LiteralPath $testRoot -PathType Container) {
        $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
        $resolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if ($resolvedTestRoot.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase) -and $resolvedTestRoot -ne $resolvedTemp) {
            Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
        }
    }
}
