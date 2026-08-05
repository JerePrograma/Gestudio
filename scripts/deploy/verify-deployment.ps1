[CmdletBinding()]
param(
    [string] $VerifyComposeFile,
    [string] $VerifyEnvFile,
    [string] $VerifyProjectName,
    [int] $VerifyBackendPort,
    [int] $VerifyFrontendPort,
    [string] $VerifyExpectedCommit,
    [int] $VerifyTimeoutSeconds = 300
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-DeploymentFailure {
    param([Parameter(Mandatory)][string] $Message, [Parameter(Mandatory)][int] $ExitCode)

    $exception = [InvalidOperationException]::new($Message)
    $exception.Data['ExitCode'] = $ExitCode
    return $exception
}

function Invoke-DeploymentNative {
    param(
        [Parameter(Mandatory)][string] $FilePath,
        [Parameter(Mandatory)][string[]] $Arguments,
        [switch] $Capture
    )

    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $FilePath @Arguments 2>&1)
        $nativeExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    $text = ($output | ForEach-Object { $_.ToString() }) -join "`n"
    if ($nativeExitCode -ne 0) {
        $tail = (($text -split "`r?`n") | Select-Object -Last 60) -join "`n"
        throw (New-DeploymentFailure -Message "$FilePath fallo con codigo ${nativeExitCode}: $tail" -ExitCode 7)
    }
    if ($Capture) { return $text.Trim() }
    if (-not [string]::IsNullOrWhiteSpace($text)) { Write-Host $text }
}

function Get-DeploymentComposeArguments {
    param(
        [Parameter(Mandatory)][string] $ComposeFile,
        [Parameter(Mandatory)][string] $EnvFile,
        [Parameter(Mandatory)][string] $ProjectName
    )

    return @(
        'compose', '-f', ([IO.Path]::GetFullPath($ComposeFile)),
        '--env-file', ([IO.Path]::GetFullPath($EnvFile)),
        '-p', $ProjectName
    )
}

function Invoke-DeploymentCompose {
    param(
        [Parameter(Mandatory)][string] $ComposeFile,
        [Parameter(Mandatory)][string] $EnvFile,
        [Parameter(Mandatory)][string] $ProjectName,
        [Parameter(Mandatory)][string[]] $Arguments,
        [switch] $Capture
    )

    $prefix = Get-DeploymentComposeArguments -ComposeFile $ComposeFile -EnvFile $EnvFile -ProjectName $ProjectName
    return Invoke-DeploymentNative -FilePath 'docker' -Arguments ($prefix + $Arguments) -Capture:$Capture
}

function Read-DeploymentEnvFile {
    param([Parameter(Mandatory)][string] $Path)

    $values = @{}
    foreach ($line in [IO.File]::ReadAllLines([IO.Path]::GetFullPath($Path))) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) { continue }
        $separator = $line.IndexOf('=')
        if ($separator -lt 1) { throw "Linea invalida en $Path" }
        $name = $line.Substring(0, $separator).Trim()
        if ($name -notmatch '^[A-Z][A-Z0-9_]*$' -or $values.ContainsKey($name)) {
            throw "Variable invalida o duplicada en ${Path}: $name"
        }
        $values[$name] = $line.Substring($separator + 1)
    }
    return $values
}

function Get-ExpectedMigrationVersions {
    param([Parameter(Mandatory)][string] $RepositoryRoot)

    $migrationRoot = Join-Path $RepositoryRoot 'backend\src\main\resources\db\migration'
    $versions = @(
        Get-ChildItem -LiteralPath $migrationRoot -File |
            Where-Object { $_.Name -match '^V([0-9]+)__.+\.sql$' } |
            ForEach-Object { [int]$Matches[1] } |
            Sort-Object
    )
    if ($versions.Count -eq 0) { throw 'No se encontraron migraciones Flyway versionadas.' }
    for ($index = 0; $index -lt $versions.Count; $index++) {
        if ($versions[$index] -ne ($index + 1)) {
            throw "El historial Flyway no es contiguo en V$($index + 1)."
        }
    }
    return $versions
}

function Invoke-DeploymentSql {
    param(
        [Parameter(Mandatory)][string] $ContainerId,
        [Parameter(Mandatory)][ValidateSet('migration', 'runtime')][string] $Role,
        [Parameter(Mandatory)][string] $Sql
    )

    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Sql))
    if ($Role -eq 'runtime') {
        $command = 'printf "%s" "$1" | base64 -d | PGPASSWORD="$POSTGRES_APP_PASSWORD" psql --no-psqlrc --tuples-only --no-align --set ON_ERROR_STOP=1 --username="$POSTGRES_APP_USER" --dbname="$POSTGRES_DB" --file=-'
    }
    else {
        $command = 'printf "%s" "$1" | base64 -d | PGPASSWORD="$POSTGRES_PASSWORD" psql --no-psqlrc --tuples-only --no-align --set ON_ERROR_STOP=1 --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" --file=-'
    }
    return Invoke-DeploymentNative -FilePath 'docker' -Arguments @(
        'exec', $ContainerId, 'sh', '-ec', $command, 'sh', $encoded
    ) -Capture
}

function Get-DeploymentServiceContainer {
    param(
        [Parameter(Mandatory)][string] $ComposeFile,
        [Parameter(Mandatory)][string] $EnvFile,
        [Parameter(Mandatory)][string] $ProjectName,
        [Parameter(Mandatory)][string] $Service
    )

    $containerId = Invoke-DeploymentCompose -ComposeFile $ComposeFile -EnvFile $EnvFile `
        -ProjectName $ProjectName -Arguments @('ps', '--all', '-q', $Service) -Capture
    if ([string]::IsNullOrWhiteSpace($containerId)) {
        throw (New-DeploymentFailure -Message "Falta el contenedor del servicio '$Service'." -ExitCode 6)
    }
    if (($containerId -split "`r?`n").Count -ne 1) {
        throw (New-DeploymentFailure -Message "El servicio '$Service' tiene mas de un contenedor." -ExitCode 10)
    }
    return $containerId.Trim()
}

function Get-DeploymentContainerState {
    param([Parameter(Mandatory)][string] $ContainerId, [Parameter(Mandatory)][string] $ProjectName)

    $inspection = Invoke-DeploymentNative -FilePath 'docker' -Arguments @(
        'inspect', '--format',
        '{{.Id}}|{{.Image}}|{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}|{{index .Config.Labels "com.docker.compose.project"}}|{{index .Config.Labels "com.docker.compose.config-hash"}}',
        $ContainerId
    ) -Capture
    $parts = $inspection.Split('|')
    if ($parts.Count -ne 6 -or $parts[4] -cne $ProjectName) {
        throw (New-DeploymentFailure -Message "El contenedor '$ContainerId' no pertenece exactamente a '$ProjectName'." -ExitCode 10)
    }
    return [pscustomobject]@{
        id = $parts[0]
        imageId = $parts[1]
        status = $parts[2]
        health = $parts[3]
        configHash = $parts[5]
    }
}

function Wait-DeploymentServiceHealthy {
    param(
        [Parameter(Mandatory)][string] $ContainerId,
        [Parameter(Mandatory)][string] $ProjectName,
        [Parameter(Mandatory)][string] $Service,
        [Parameter(Mandatory)][int] $TimeoutSeconds
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $state = Get-DeploymentContainerState -ContainerId $ContainerId -ProjectName $ProjectName
        if ($state.status -eq 'running' -and $state.health -eq 'healthy') { return $state }
        if ($state.status -in @('dead', 'exited', 'removing')) {
            throw (New-DeploymentFailure -Message "El servicio '$Service' termino en estado '$($state.status)'." -ExitCode 6)
        }
        Start-Sleep -Seconds 2
    } while ([DateTime]::UtcNow -lt $deadline)

    throw (New-DeploymentFailure -Message "Timeout esperando el healthcheck de '$Service'." -ExitCode 6)
}

function Invoke-DeploymentHttpGet {
    param([Parameter(Mandatory)][string] $Url, [int] $TimeoutSeconds = 20)

    Add-Type -AssemblyName System.Net.Http
    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.AllowAutoRedirect = $false
    $client = [Net.Http.HttpClient]::new($handler)
    try {
        $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
        $response = $client.GetAsync($Url).GetAwaiter().GetResult()
        $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        $contentType = if ($null -eq $response.Content.Headers.ContentType) {
            ''
        }
        else {
            [string]$response.Content.Headers.ContentType.MediaType
        }
        return [pscustomobject]@{
            statusCode = [int]$response.StatusCode
            contentType = $contentType
            body = $body
        }
    }
    finally {
        $client.Dispose()
        $handler.Dispose()
    }
}

function Get-DeploymentImageRevision {
    param([Parameter(Mandatory)][string] $ImageId)

    return Invoke-DeploymentNative -FilePath 'docker' -Arguments @(
        'image', 'inspect', '--format', '{{index .Config.Labels "org.opencontainers.image.revision"}}', $ImageId
    ) -Capture
}

function Invoke-GestudioDeploymentVerification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $RepositoryRoot,
        [Parameter(Mandatory)][string] $ComposeFile,
        [Parameter(Mandatory)][string] $EnvFile,
        [Parameter(Mandatory)][string] $ProjectName,
        [Parameter(Mandatory)][hashtable] $Configuration,
        [Parameter(Mandatory)][string] $ExpectedCommit,
        [Parameter(Mandatory)][string] $ExpectedFingerprint,
        [object] $PreviousState,
        [int] $TimeoutSeconds = 300,
        [scriptblock] $StatusWriter
    )

    if ($null -eq $StatusWriter) {
        $StatusWriter = { param($level, $message) Write-Host "[$level] $message" }
    }

    $expectedVersions = @(Get-ExpectedMigrationVersions -RepositoryRoot $RepositoryRoot)
    $expectedLatest = $expectedVersions[-1]
    $expectedVersionList = ($expectedVersions | ForEach-Object { [string]$_ }) -join ','

    $containerIds = @{}
    $containers = @{}
    foreach ($service in @('db', 'backend', 'frontend')) {
        $containerIds[$service] = Get-DeploymentServiceContainer -ComposeFile $ComposeFile `
            -EnvFile $EnvFile -ProjectName $ProjectName -Service $service
        $containers[$service] = Wait-DeploymentServiceHealthy -ContainerId $containerIds[$service] `
            -ProjectName $ProjectName -Service $service -TimeoutSeconds $TimeoutSeconds
        & $StatusWriter 'PASS' "$service healthy"
    }

    foreach ($service in @('backend', 'frontend')) {
        $revision = Get-DeploymentImageRevision -ImageId $containers[$service].imageId
        if ($revision -cne $ExpectedCommit) {
            throw (New-DeploymentFailure -Message "La imagen de '$service' pertenece a '$revision', no a '$ExpectedCommit'." -ExitCode 10)
        }
    }

    if ($null -ne $PreviousState -and
        [string]$PreviousState.fingerprint -ceq $ExpectedFingerprint -and
        $null -ne $PreviousState.containers) {
        foreach ($service in @('db', 'backend', 'frontend')) {
            $recorded = $PreviousState.containers.$service
            if ($null -eq $recorded -or
                [string]$recorded.imageId -cne [string]$containers[$service].imageId -or
                [string]$recorded.configHash -cne [string]$containers[$service].configHash) {
                throw (New-DeploymentFailure -Message "Drift de imagen o configuracion en '$service'." -ExitCode 10)
            }
        }
    }

    $flywaySql = @'
SELECT count(*) FILTER (WHERE success)::text || '|' ||
       coalesce(max(version::int) FILTER (WHERE success), 0)::text || '|' ||
       count(*) FILTER (WHERE NOT success)::text || '|' ||
       coalesce(string_agg(version, ',' ORDER BY installed_rank) FILTER (WHERE success), '') || '|' ||
       (SELECT count(*) FROM (
          SELECT version FROM flyway_schema_history WHERE success GROUP BY version HAVING count(*) <> 1
        ) duplicates)::text
FROM flyway_schema_history;
'@
    $flywayRaw = Invoke-DeploymentSql -ContainerId $containerIds.db -Role migration -Sql $flywaySql
    $flyway = $flywayRaw.Trim().Split('|')
    if ($flyway.Count -ne 5 -or
        [int]$flyway[0] -ne $expectedVersions.Count -or
        [int]$flyway[1] -ne $expectedLatest -or
        [int]$flyway[2] -ne 0 -or
        $flyway[3] -cne $expectedVersionList -or
        [int]$flyway[4] -ne 0) {
        throw (New-DeploymentFailure -Message "Flyway no converge al historial esperado V1-V${expectedLatest}: $flywayRaw" -ExitCode 7)
    }
    & $StatusWriter 'PASS' "Flyway V1-V$expectedLatest sin pendientes ni duplicados"

    $runtimeRaw = Invoke-DeploymentSql -ContainerId $containerIds.db -Role runtime -Sql @'
SELECT current_user || '|' || rolsuper::text || '|' || rolbypassrls::text || '|' ||
       rolcreaterole::text || '|' || rolcreatedb::text
FROM pg_roles WHERE rolname = current_user;
'@
    $runtime = $runtimeRaw.Trim().Split('|')
    if ($runtime.Count -ne 5 -or $runtime[0] -cne $Configuration['POSTGRES_APP_USER'] -or
        @($runtime[1..4] | Where-Object { $_ -cne 'false' }).Count -ne 0) {
        throw (New-DeploymentFailure -Message 'El usuario runtime tiene identidad o privilegios PostgreSQL indebidos.' -ExitCode 7)
    }
    & $StatusWriter 'PASS' 'Usuario runtime sin SUPERUSER, BYPASSRLS, CREATEROLE ni CREATEDB'

    if ($expectedLatest -ge 10) {
        $rlsHealth = Invoke-DeploymentSql -ContainerId $containerIds.db -Role runtime `
            -Sql 'SELECT status FROM public.v_multitenancy_migration_health;'
        if ($rlsHealth.Trim() -cne 'GREEN') {
            throw (New-DeploymentFailure -Message "El health estructural RLS es '$rlsHealth'." -ExitCode 7)
        }
        & $StatusWriter 'PASS' 'RLS estructural GREEN'
    }

    $bootstrap = [ordered]@{
        tenants = 0
        memberships = 0
        bootstrapUsers = [int](Invoke-DeploymentSql -ContainerId $containerIds.db -Role migration -Sql @'
SELECT count(*) FROM bootstrap_ejecuciones b
JOIN usuarios u ON u.id = b.usuario_id
WHERE b.tipo = 'SUPERADMIN_INICIAL';
'@)
        roles = [int](Invoke-DeploymentSql -ContainerId $containerIds.db -Role migration -Sql 'SELECT count(*) FROM roles;')
        permissions = 0
        membershipRoles = 0
    }
    if ($expectedLatest -ge 5) {
        $bootstrap.permissions = [int](Invoke-DeploymentSql -ContainerId $containerIds.db -Role migration -Sql 'SELECT count(*) FROM permisos;')
    }
    if ($expectedLatest -ge 8) {
        $bootstrap.tenants = [int](Invoke-DeploymentSql -ContainerId $containerIds.db -Role migration -Sql 'SELECT count(*) FROM tenants;')
        $bootstrap.memberships = [int](Invoke-DeploymentSql -ContainerId $containerIds.db -Role migration -Sql 'SELECT count(*) FROM tenant_memberships;')
        $bootstrap.membershipRoles = [int](Invoke-DeploymentSql -ContainerId $containerIds.db -Role migration -Sql 'SELECT count(*) FROM tenant_membership_roles;')
    }
    if ($bootstrap.bootstrapUsers -ne 1 -or ($expectedLatest -ge 8 -and ($bootstrap.tenants -lt 1 -or $bootstrap.memberships -lt 1))) {
        throw (New-DeploymentFailure -Message 'El bootstrap inicial no esta completo o no es unico.' -ExitCode 7)
    }
    & $StatusWriter 'PASS' 'Bootstrap unico verificado'

    $backendBase = "http://127.0.0.1:$($Configuration['BACKEND_PORT'])"
    $frontendBase = "http://127.0.0.1:$($Configuration['FRONTEND_PORT'])"

    $readiness = Invoke-DeploymentHttpGet -Url "$backendBase/actuator/health/readiness"
    $readinessStatus = ''
    try { $readinessStatus = [string](ConvertFrom-Json $readiness.body).status } catch { $readinessStatus = '' }
    if ($readiness.statusCode -ne 200 -or $readinessStatus -cne 'UP') {
        throw (New-DeploymentFailure -Message "Readiness invalido: HTTP $($readiness.statusCode), status '$readinessStatus'." -ExitCode 6)
    }
    & $StatusWriter 'PASS' 'Readiness HTTP 200 UP'

    $anonymous = Invoke-DeploymentHttpGet -Url "$backendBase/api/usuarios/perfil"
    $anonymousJson = $true
    try { $null = ConvertFrom-Json $anonymous.body } catch { $anonymousJson = $false }
    if ($anonymous.statusCode -ne 401 -or $anonymous.contentType -notmatch '^application/json$' -or
        -not $anonymousJson -or [string]::IsNullOrWhiteSpace($anonymous.body) -or
        $anonymous.body -match '(?i)(stacktrace|<html)') {
        throw (New-DeploymentFailure -Message "Contrato anonimo invalido: HTTP $($anonymous.statusCode), tipo '$($anonymous.contentType)'." -ExitCode 7)
    }
    & $StatusWriter 'PASS' 'Perfil anonimo HTTP 401 JSON'

    $frontend = Invoke-DeploymentHttpGet -Url "$frontendBase/"
    if ($frontend.statusCode -lt 200 -or $frontend.statusCode -ge 400 -or
        $frontend.contentType -notmatch '^text/html$' -or $frontend.body -notmatch '(?i)<!doctype html|<html') {
        throw (New-DeploymentFailure -Message "Frontend invalido: HTTP $($frontend.statusCode), tipo '$($frontend.contentType)'." -ExitCode 7)
    }
    & $StatusWriter 'PASS' 'Frontend HTML disponible'

    $recentLogs = Invoke-DeploymentCompose -ComposeFile $ComposeFile -EnvFile $EnvFile `
        -ProjectName $ProjectName -Arguments @('logs', '--since', '10m', '--tail', '400', '--no-color', 'db', 'backend') -Capture
    $fatalPattern = '(?im)(APPLICATION FAILED TO START|Flyway[^\r\n]*(exception|failed|error)|BeanCreationException|password authentication failed|permission denied|SQLSTATE\s*42501|connection refused|multitenancy[^\r\n]*RED|RLS[^\r\n]*(failed|error)|FATAL:\s)'
    if ($recentLogs -match $fatalPattern) {
        $matched = ($Matches[0] -replace '[\r\n\t]+', ' ').Trim()
        throw (New-DeploymentFailure -Message "Los logs recientes contienen un error fatal clasificado: $matched" -ExitCode 7)
    }
    & $StatusWriter 'PASS' 'Logs recientes sin errores fatales clasificados'

    return [pscustomobject]@{
        flyway = [pscustomobject]@{
            version = $expectedLatest
            successfulCount = $expectedVersions.Count
            pending = 0
            valid = $true
        }
        bootstrap = [pscustomobject]$bootstrap
        containers = [pscustomobject]@{
            db = $containers.db
            backend = $containers.backend
            frontend = $containers.frontend
        }
        endpoints = [pscustomobject]@{
            backend = $backendBase
            frontend = $frontendBase
            readiness = "$backendBase/actuator/health/readiness"
        }
        healthChecks = [pscustomobject]@{
            postgres = 'PASS'
            backend = 'PASS'
            anonymousSecurity = 'PASS'
            frontend = 'PASS'
            logs = 'PASS'
            rls = if ($expectedLatest -ge 10) { 'PASS' } else { 'NOT_APPLICABLE' }
        }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        if ([string]::IsNullOrWhiteSpace($VerifyComposeFile) -or
            [string]::IsNullOrWhiteSpace($VerifyEnvFile) -or
            [string]::IsNullOrWhiteSpace($VerifyProjectName) -or
            $VerifyBackendPort -le 0 -or $VerifyFrontendPort -le 0) {
            throw 'Faltan parametros para verificar el despliegue.'
        }
        $root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $config = Read-DeploymentEnvFile -Path $VerifyEnvFile
        $config['BACKEND_PORT'] = [string]$VerifyBackendPort
        $config['FRONTEND_PORT'] = [string]$VerifyFrontendPort
        $null = Invoke-GestudioDeploymentVerification -RepositoryRoot $root `
            -ComposeFile $VerifyComposeFile -EnvFile $VerifyEnvFile -ProjectName $VerifyProjectName `
            -Configuration $config -ExpectedCommit $VerifyExpectedCommit -ExpectedFingerprint 'standalone' `
            -TimeoutSeconds $VerifyTimeoutSeconds
        exit 0
    }
    catch {
        Write-Error $_.Exception.Message
        $code = 7
        if ($_.Exception.Data.Contains('ExitCode')) { $code = [int]$_.Exception.Data['ExitCode'] }
        exit $code
    }
}
