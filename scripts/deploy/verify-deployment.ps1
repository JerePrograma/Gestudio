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

function Get-ExpectedMigrationManifest {
    param([Parameter(Mandatory)][string] $RepositoryRoot)

    $migrationRoot = Join-Path $RepositoryRoot 'backend\src\main\resources\db\migration'
    $versioned = @(
        Get-ChildItem -LiteralPath $migrationRoot -File |
            Where-Object { $_.Name -match '^V([0-9]+)__.+\.sql$' } |
            ForEach-Object { [pscustomobject]@{ version = [int]$Matches[1]; script = $_.Name } } |
            Sort-Object version
    )
    if ($versioned.Count -eq 0) { throw 'No se encontraron migraciones Flyway versionadas.' }
    for ($index = 0; $index -lt $versioned.Count; $index++) {
        if ($versioned[$index].version -ne ($index + 1)) {
            throw "El historial Flyway no es contiguo en V$($index + 1)."
        }
    }
    $latest = $versioned[-1].version
    $baselines = @(Get-ChildItem -LiteralPath $migrationRoot -File | Where-Object {
        $_.Name -match '^B([0-9]+)__.+\.sql$'
    } | ForEach-Object { [pscustomobject]@{ version = [int]$Matches[1]; script = $_.Name } })
    if ($baselines.Count -gt 1 -or ($baselines.Count -eq 1 -and $baselines[0].version -ne $latest)) {
        throw 'La baseline Flyway debe ser única y corresponder a la última versión.'
    }
    return [pscustomobject]@{
        versioned = $versioned
        baseline = if ($baselines.Count -eq 1) { $baselines[0] } else { $null }
        latest = $latest
    }
}

function Invoke-DeploymentSql {
    param(
        [Parameter(Mandatory)][string] $ContainerId,
        [Parameter(Mandatory)][ValidateSet('migration', 'runtime', 'control')][string] $Role,
        [Parameter(Mandatory)][string] $Sql
    )

    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Sql))
    if ($Role -eq 'runtime') {
        $command = 'printf "%s" "$1" | base64 -d | PGPASSWORD="$POSTGRES_APP_PASSWORD" psql --no-psqlrc --tuples-only --no-align --set ON_ERROR_STOP=1 --username="$POSTGRES_APP_USER" --dbname="$POSTGRES_DB" --file=-'
    }
    elseif ($Role -eq 'control') {
        $command = 'printf "%s" "$1" | base64 -d | PGPASSWORD="$POSTGRES_CONTROL_PASSWORD" psql --no-psqlrc --tuples-only --no-align --set ON_ERROR_STOP=1 --username="$POSTGRES_CONTROL_USER" --dbname="$POSTGRES_DB" --file=-'
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

    $migrationManifest = Get-ExpectedMigrationManifest -RepositoryRoot $RepositoryRoot
    $expectedVersions = @($migrationManifest.versioned)
    $expectedLatest = [int]$migrationManifest.latest

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

    $flywaySql = "SELECT version || '|' || type || '|' || script FROM flyway_schema_history WHERE success ORDER BY installed_rank;"
    $flywayRaw = Invoke-DeploymentSql -ContainerId $containerIds.db -Role migration -Sql $flywaySql
    $failedMigrations = [int](Invoke-DeploymentSql -ContainerId $containerIds.db -Role migration `
        -Sql 'SELECT count(*) FROM flyway_schema_history WHERE NOT success;')
    $installed = @(($flywayRaw -split "`r?`n") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object {
        $parts = $_.Split('|', 3)
        if ($parts.Count -ne 3) { throw "Fila Flyway inválida: $_" }
        [pscustomobject]@{ version = [int]$parts[0]; type = $parts[1]; script = $parts[2] }
    })
    $versionedHistory = $installed.Count -eq $expectedVersions.Count
    if ($versionedHistory) {
        for ($index = 0; $index -lt $expectedVersions.Count; $index++) {
            $versionedHistory = $versionedHistory -and
                $installed[$index].version -eq $expectedVersions[$index].version -and
                $installed[$index].type -ceq 'SQL' -and
                $installed[$index].script -ceq $expectedVersions[$index].script
        }
    }
    $baselineHistory = $null -ne $migrationManifest.baseline -and $installed.Count -eq 1 -and
        $installed[0].version -eq $expectedLatest -and
        $installed[0].type -ceq 'SQL_BASELINE' -and
        $installed[0].script -ceq $migrationManifest.baseline.script
    if ($failedMigrations -ne 0 -or (-not $versionedHistory -and -not $baselineHistory)) {
        throw (New-DeploymentFailure -Message "Flyway no converge a V1-V${expectedLatest} ni a la baseline B${expectedLatest}: $flywayRaw" -ExitCode 7)
    }
    $flywayMode = if ($baselineHistory) { 'BASELINE' } else { 'VERSIONED' }
    & $StatusWriter 'PASS' "Flyway $flywayMode converge a versión $expectedLatest"

    $runtimeRaw = Invoke-DeploymentSql -ContainerId $containerIds.db -Role runtime -Sql @'
SELECT current_user || '|' || rolsuper::text || '|' || rolbypassrls::text || '|' ||
       rolcreaterole::text || '|' || rolcreatedb::text || '|' || rolreplication::text
FROM pg_roles WHERE rolname = current_user;
'@
    $runtime = $runtimeRaw.Trim().Split('|')
    if ($runtime.Count -ne 6 -or $runtime[0] -cne $Configuration['POSTGRES_APP_USER'] -or
        @($runtime[1..5] | Where-Object { $_ -cne 'false' }).Count -ne 0) {
        throw (New-DeploymentFailure -Message 'El usuario runtime tiene identidad o privilegios PostgreSQL indebidos.' -ExitCode 7)
    }
    & $StatusWriter 'PASS' 'Usuario runtime sin SUPERUSER, BYPASSRLS, CREATEROLE, CREATEDB ni REPLICATION'

    $controlRaw = Invoke-DeploymentSql -ContainerId $containerIds.db -Role control -Sql @'
SELECT current_user || '|' || rolsuper::text || '|' || rolbypassrls::text || '|' ||
       rolcreaterole::text || '|' || rolcreatedb::text || '|' || rolreplication::text
FROM pg_roles WHERE rolname = current_user;
'@
    $control = $controlRaw.Trim().Split('|')
    if ($control.Count -ne 6 -or $control[0] -cne $Configuration['POSTGRES_CONTROL_USER'] -or
        @($control[1..5] | Where-Object { $_ -cne 'false' }).Count -ne 0) {
        throw (New-DeploymentFailure -Message 'El runtime de control-plane tiene privilegios PostgreSQL indebidos.' -ExitCode 7)
    }
    & $StatusWriter 'PASS' 'Runtime de control-plane sin SUPERUSER, BYPASSRLS, CREATEROLE, CREATEDB ni REPLICATION'

    if ($expectedLatest -ge 12) {
        $leastPrivilege = (Invoke-DeploymentSql -ContainerId $containerIds.db -Role migration -Sql @"
SELECT
  (SELECT (count(*) = 1 AND bool_and(parent.rolname = 'gestudio_platform'))::text
   FROM pg_catalog.pg_auth_members memberships
   JOIN pg_catalog.pg_roles member ON member.oid = memberships.member
   JOIN pg_catalog.pg_roles parent ON parent.oid = memberships.roleid
   WHERE member.rolname = '$($Configuration['POSTGRES_CONTROL_USER'])') || '|' ||
  (SELECT (count(*) = 1 AND bool_and(parent.rolname = 'gestudio_app'))::text
   FROM pg_catalog.pg_auth_members memberships
   JOIN pg_catalog.pg_roles member ON member.oid = memberships.member
   JOIN pg_catalog.pg_roles parent ON parent.oid = memberships.roleid
   WHERE member.rolname = '$($Configuration['POSTGRES_APP_USER'])') || '|' ||
  (NOT EXISTS (
     SELECT 1 FROM pg_catalog.pg_roles technical
     WHERE technical.rolname IN ('gestudio_app', 'gestudio_platform')
       AND (technical.rolcanlogin OR technical.rolsuper OR technical.rolcreaterole OR
            technical.rolcreatedb OR technical.rolinherit OR technical.rolreplication OR technical.rolbypassrls)
   ) AND NOT EXISTS (
     SELECT 1
     FROM pg_catalog.pg_auth_members memberships
     JOIN pg_catalog.pg_roles member ON member.oid = memberships.member
     WHERE member.rolname IN ('gestudio_app', 'gestudio_platform')
   ))::text || '|' ||
  (has_table_privilege('$($Configuration['POSTGRES_CONTROL_USER'])', 'public.tenants', 'SELECT') AND
   has_table_privilege('$($Configuration['POSTGRES_CONTROL_USER'])', 'public.tenants', 'INSERT') AND
   has_table_privilege('$($Configuration['POSTGRES_CONTROL_USER'])', 'public.tenants', 'UPDATE'))::text || '|' ||
  (has_table_privilege('$($Configuration['POSTGRES_CONTROL_USER'])', 'public.alumnos', 'SELECT') OR
   has_table_privilege('$($Configuration['POSTGRES_CONTROL_USER'])', 'public.alumnos', 'INSERT') OR
   has_table_privilege('$($Configuration['POSTGRES_CONTROL_USER'])', 'public.alumnos', 'UPDATE') OR
   has_table_privilege('$($Configuration['POSTGRES_CONTROL_USER'])', 'public.alumnos', 'DELETE'))::text || '|' ||
  (has_table_privilege('$($Configuration['POSTGRES_CONTROL_USER'])', 'public.pagos', 'SELECT') OR
   has_table_privilege('$($Configuration['POSTGRES_CONTROL_USER'])', 'public.pagos', 'INSERT') OR
   has_table_privilege('$($Configuration['POSTGRES_CONTROL_USER'])', 'public.pagos', 'UPDATE') OR
   has_table_privilege('$($Configuration['POSTGRES_CONTROL_USER'])', 'public.pagos', 'DELETE'))::text || '|' ||
  (has_table_privilege('$($Configuration['POSTGRES_APP_USER'])', 'public.tenants', 'INSERT') OR
   has_table_privilege('$($Configuration['POSTGRES_APP_USER'])', 'public.tenants', 'UPDATE') OR
   has_table_privilege('$($Configuration['POSTGRES_APP_USER'])', 'public.tenants', 'DELETE'))::text || '|' ||
  (SELECT count(*)
   FROM pg_catalog.pg_class object
   JOIN pg_catalog.pg_namespace namespace ON namespace.oid = object.relnamespace
   JOIN pg_catalog.pg_roles owner ON owner.oid = object.relowner
   WHERE namespace.nspname = 'public'
     AND owner.rolname IN ('$($Configuration['POSTGRES_APP_USER'])', '$($Configuration['POSTGRES_CONTROL_USER'])'))::text;
"@).Trim().Split('|')
        if ($leastPrivilege.Count -ne 8 -or $leastPrivilege[0] -cne 'true' -or
            $leastPrivilege[1] -cne 'true' -or $leastPrivilege[2] -cne 'true' -or
            $leastPrivilege[3] -cne 'true' -or $leastPrivilege[4] -cne 'false' -or
            $leastPrivilege[5] -cne 'false' -or $leastPrivilege[6] -cne 'false' -or
            $leastPrivilege[7] -cne '0') {
            throw (New-DeploymentFailure -Message 'La frontera SQL entre tenant runtime y control-plane no cumple mínimo privilegio.' -ExitCode 7)
        }
        & $StatusWriter 'PASS' 'DML control-plane separado del runtime tenant'
    }

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
        platformAdmins = 0
        bootstrapUsers = [int](Invoke-DeploymentSql -ContainerId $containerIds.db -Role migration `
            -Sql "SELECT count(*) FROM bootstrap_ejecuciones WHERE tipo = 'SUPERADMIN_INICIAL';")
        bootstrapLinkedAdmins = 0
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
        $bootstrap.platformAdmins = [int](Invoke-DeploymentSql -ContainerId $containerIds.db -Role migration -Sql 'SELECT count(*) FROM platform_admins WHERE active;')
        $bootstrap.bootstrapLinkedAdmins = [int](Invoke-DeploymentSql -ContainerId $containerIds.db -Role migration -Sql @'
SELECT count(*)
FROM bootstrap_ejecuciones b
JOIN usuarios u ON u.id = b.usuario_id AND u.activo
JOIN platform_admins pa ON pa.usuario_id = u.id AND pa.active
WHERE b.tipo = 'SUPERADMIN_INICIAL';
'@)
    }
    if ($bootstrap.bootstrapUsers -gt 1 -or ($expectedLatest -ge 8 -and
        $bootstrap.bootstrapLinkedAdmins -ne $bootstrap.bootstrapUsers)) {
        throw (New-DeploymentFailure -Message 'El estado one-shot del bootstrap de plataforma es inválido.' -ExitCode 7)
    }
    & $StatusWriter 'PASS' "Bootstrap externo compatible (claims=$($bootstrap.bootstrapUsers))"

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
            successfulCount = $installed.Count
            mode = $flywayMode
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
