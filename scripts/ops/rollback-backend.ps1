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

if ([string]::IsNullOrWhiteSpace($TargetBackendImage)) {
    throw 'TargetBackendImage no puede estar vacío.'
}
if ([string]::IsNullOrWhiteSpace($ProjectName)) {
    throw 'ProjectName no puede estar vacío.'
}
if ($ProjectName -ieq 'gestudio-remote-demo') {
    throw 'gestudio-remote-demo está protegido y no admite rollback desde este comando.'
}

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

function Get-LocalMigrationManifest {
    $migrationRoot = Join-Path $repoRoot 'backend/src/main/resources/db/migration'
    if (-not (Test-Path -LiteralPath $migrationRoot -PathType Container)) {
        throw "No existe el directorio local de migraciones: $migrationRoot"
    }

    $entries = @(Get-ChildItem -LiteralPath $migrationRoot -Filter 'V*__*.sql' -File | ForEach-Object {
        if ($_.Name -notmatch '^V(?<version>[0-9]+)__.+\.sql$') {
            throw "Nombre de migración Flyway inválido: $($_.Name)"
        }
        [pscustomobject]@{ Version = [int]$matches.version; Script = $_.Name }
    } | Sort-Object Version)
    if ($entries.Count -eq 0) {
        throw 'No existen migraciones Flyway versionadas locales.'
    }
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
    if ($resourceNames.Count -eq 0) {
        throw 'No existen recursos Flyway locales.'
    }
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
        LatestVersion = $entries[-1].Version
        Entries = $entries
        Baseline = $baselines[0]
        Resources = $resourceEntries
        ResourceManifest = $canonicalLines -join "`n"
    }
}

function Get-ImageMetadataValue {
    param(
        [Parameter(Mandatory)][string] $Image,
        [Parameter(Mandatory)][string] $Path
    )

    try {
        $value = Invoke-Native -FilePath 'docker' -Arguments @(
            'run', '--rm', '--entrypoint', 'cat', $Image, $Path
        ) -Capture
    }
    catch {
        throw "La imagen '$Image' no expone metadata Flyway obligatoria en ${Path}: $($_.Exception.Message)"
    }
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "La imagen '$Image' expone metadata Flyway vacía en $Path."
    }
    return $value.Trim()
}

function Resolve-ImageIdentity {
    param([Parameter(Mandatory)][string] $Reference)

    $imageId = Invoke-Native -FilePath 'docker' -Arguments @(
        'image', 'inspect', '--format', '{{.Id}}', $Reference
    ) -Capture
    if ($imageId -notmatch '^sha256:[a-f0-9]{64}$') {
        throw "Docker no resolvió una identidad inmutable válida para '$Reference': '$imageId'."
    }
    return $imageId
}

function Get-ImageFlywayManifest {
    param(
        [Parameter(Mandatory)][string] $ImageId,
        [Parameter(Mandatory)] $LocalManifest
    )

    $latestPath = '/app/build-metadata/flyway-latest'
    $versionedPath = '/app/build-metadata/flyway-versioned-latest'
    $baselinePath = '/app/build-metadata/flyway-baseline-script'
    $resourcesPath = '/app/build-metadata/flyway-resources.sha256'
    $latestRaw = Get-ImageMetadataValue -Image $ImageId -Path $latestPath
    $versionedRaw = Get-ImageMetadataValue -Image $ImageId -Path $versionedPath
    $baselineScript = Get-ImageMetadataValue -Image $ImageId -Path $baselinePath
    $resourceManifest = Get-ImageMetadataValue -Image $ImageId -Path $resourcesPath

    if ($latestRaw -notmatch '^[0-9]+$') {
        throw "La imagen '$ImageId' no declara una versión Flyway válida en $latestPath."
    }
    if ($versionedRaw -notmatch '^[0-9]+$') {
        throw "La imagen '$ImageId' no declara una versión Flyway válida en $versionedPath."
    }
    if ($baselineScript -notmatch '^B(?<version>[0-9]+)__.+\.sql$') {
        throw "La imagen '$ImageId' no declara una baseline Flyway válida en $baselinePath."
    }

    $latest = [int]$latestRaw
    $versionedLatest = [int]$versionedRaw
    $baselineVersion = [int]$matches.version
    if ($latest -ne $versionedLatest -or $latest -ne $baselineVersion) {
        throw "Metadata Flyway inconsistente en '$ImageId': latest=$latest, versioned=$versionedLatest, baseline=B$baselineVersion."
    }
    if ($latest -ne $LocalManifest.LatestVersion -or
        $baselineScript -cne $LocalManifest.Baseline.Script) {
        throw "La imagen '$ImageId' no coincide con el manifiesto local V1..V$($LocalManifest.LatestVersion)/$($LocalManifest.Baseline.Script)."
    }

    $manifestLines = @($resourceManifest -split "`n")
    if ($manifestLines.Count -lt 2 -or $manifestLines[0] -cne 'gestudio-flyway-manifest-v1') {
        throw "La imagen '$ImageId' no declara un manifiesto canónico válido en $resourcesPath."
    }
    $manifestNames = [string[]]@()
    for ($index = 1; $index -lt $manifestLines.Count; $index++) {
        $line = $manifestLines[$index].TrimEnd("`r")
        if ($line -cnotmatch '^(?<sha>[a-f0-9]{64})\t(?<script>[^\t\r\n/\\]+)$') {
            throw "La imagen '$ImageId' contiene una entrada Flyway no canónica: '$line'."
        }
        $manifestNames += $matches.script
    }
    if (@($manifestNames | Select-Object -Unique).Count -ne $manifestNames.Count) {
        throw "La imagen '$ImageId' contiene recursos Flyway duplicados."
    }
    $sortedNames = [string[]]$manifestNames.Clone()
    [Array]::Sort($sortedNames, [StringComparer]::Ordinal)
    for ($index = 0; $index -lt $manifestNames.Count; $index++) {
        if ($manifestNames[$index] -cne $sortedNames[$index]) {
            throw "La imagen '$ImageId' no ordena canónicamente sus recursos Flyway."
        }
    }
    if ($resourceManifest -cne $LocalManifest.ResourceManifest) {
        throw "La imagen '$ImageId' no coincide exactamente con nombres y SHA-256 de todos los recursos Flyway locales."
    }

    return [pscustomobject]@{
        LatestVersion = $latest
        VersionedLatest = $versionedLatest
        BaselineScript = $baselineScript
        ResourceManifest = $resourceManifest
    }
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

function Invoke-DatabaseSql {
    param(
        [Parameter(Mandatory)][string] $DbContainer,
        [Parameter(Mandatory)][string] $Sql
    )

    $sql = $Sql
    $sqlBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($sql))
    return Invoke-Native -FilePath 'docker' -Arguments @(
        'exec', $DbContainer, 'sh', '-ec',
        'printf "%s" "$1" | base64 -d | PGPASSWORD="$POSTGRES_PASSWORD" psql --no-psqlrc --tuples-only --no-align --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" --file=-',
        'sh', $sqlBase64
    ) -Capture
}

function Assert-FlywayHistory {
    param(
        [Parameter(Mandatory)][string] $DbContainer,
        [Parameter(Mandatory)] $Manifest
    )

    $failedRaw = Invoke-DatabaseSql -DbContainer $DbContainer `
        -Sql 'SELECT count(*) FROM flyway_schema_history WHERE NOT success;'
    if ($failedRaw -notmatch '^[0-9]+$') {
        throw "No se pudo determinar el total de migraciones Flyway fallidas: $failedRaw"
    }
    $failed = [int]$failedRaw
    $raw = Invoke-DatabaseSql -DbContainer $DbContainer `
        -Sql "SELECT coalesce(version,'') || '|' || type || '|' || script FROM flyway_schema_history WHERE success ORDER BY installed_rank;"
    $installed = @(($raw -split "`r?`n") |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object {
            $parts = $_.Split('|', 3)
            if ($parts.Count -ne 3 -or $parts[0] -notmatch '^[0-9]+$') {
                throw "Fila Flyway inválida: $_"
            }
            [pscustomobject]@{
                Version = [int]$parts[0]
                Type = $parts[1]
                Script = $parts[2]
            }
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
    $baseline = $installed.Count -eq 1 -and
        $installed[0].Version -eq $Manifest.LatestVersion -and
        $installed[0].Type -ceq 'SQL_BASELINE' -and
        $installed[0].Script -ceq $Manifest.Baseline.Script
    if ($failed -ne 0 -or (-not $versioned -and -not $baseline)) {
        throw "Historial Flyway inválido: failed=$failed; successful=$raw"
    }
    if ($baseline) { return 'BASELINE' }
    return 'VERSIONED'
}

function ConvertTo-SqlLiteral {
    param([Parameter(Mandatory)][string] $Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

function Assert-ControlPlaneDatabaseContract {
    param(
        [Parameter(Mandatory)][string] $DbContainer,
        [Parameter(Mandatory)][string] $ApplicationRole,
        [Parameter(Mandatory)][string] $ControlRole
    )

    $applicationRoleSql = ConvertTo-SqlLiteral -Value $ApplicationRole
    $controlRoleSql = ConvertTo-SqlLiteral -Value $ControlRole
    $contract = (Invoke-DatabaseSql -DbContainer $DbContainer -Sql @"
SELECT
  EXISTS (
    SELECT 1
    FROM pg_catalog.pg_auth_members membership
    JOIN pg_catalog.pg_roles member_role ON member_role.oid = membership.member
    JOIN pg_catalog.pg_roles parent_role ON parent_role.oid = membership.roleid
    WHERE member_role.rolname = $controlRoleSql
      AND parent_role.rolname = 'gestudio_platform'
  )::text || '|' ||
  (to_regclass('public.platform_admins') IS NOT NULL AND
   to_regclass('public.platform_refresh_sessions') IS NOT NULL AND
   to_regclass('public.platform_mfa_credentials') IS NOT NULL AND
   to_regclass('public.platform_audit_events') IS NOT NULL AND
   to_regprocedure('public.gestudio_multitenancy_health()') IS NOT NULL)::text || '|' ||
  (has_table_privilege($controlRoleSql, 'public.tenants', 'SELECT') AND
   has_table_privilege($controlRoleSql, 'public.tenants', 'INSERT') AND
   has_table_privilege($controlRoleSql, 'public.tenants', 'UPDATE'))::text || '|' ||
  has_table_privilege($controlRoleSql, 'public.alumnos', 'SELECT')::text || '|' ||
  (has_table_privilege($applicationRoleSql, 'public.tenants', 'INSERT') OR
   has_table_privilege($applicationRoleSql, 'public.tenants', 'UPDATE') OR
   has_table_privilege($applicationRoleSql, 'public.tenants', 'DELETE'))::text;
"@).Trim()
    if ($contract -cne 'true|true|true|false|false') {
        throw "Contrato de estructuras/grants del control-plane inválido: $contract"
    }
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
        [Parameter(Mandatory)][string] $ImageId,
        [Parameter(Mandatory)][string] $HealthContract
    )

    $hadImageOverride = Test-Path Env:BACKEND_IMAGE
    $previousImageOverride = if ($hadImageOverride) { $env:BACKEND_IMAGE } else { $null }
    $hadHealthOverride = Test-Path Env:BACKEND_HEALTHCHECK_MODE
    $previousHealthOverride = if ($hadHealthOverride) { $env:BACKEND_HEALTHCHECK_MODE } else { $null }
    try {
        $env:BACKEND_IMAGE = $ImageId
        $env:BACKEND_HEALTHCHECK_MODE = $HealthContract
        Invoke-Compose -Arguments @('up', '-d', '--no-deps', '--force-recreate', $BackendService) | Out-Null
        $containerId = Wait-BackendHealthy
        $actualImageId = Invoke-Native -FilePath 'docker' -Arguments @(
            'inspect', '--format', '{{.Image}}', $containerId
        ) -Capture
        if ($actualImageId -cne $ImageId) {
            throw "Compose inició la identidad '$actualImageId' en lugar de la identidad validada '$ImageId'."
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

function Assert-ActiveBackendImageId {
    param([Parameter(Mandatory)][string] $ExpectedImageId)

    $containerId = Invoke-Compose -Arguments @('ps', '-q', $BackendService) -Capture
    if ([string]::IsNullOrWhiteSpace($containerId)) {
        throw 'No se encontró el backend al verificar su identidad inmutable.'
    }
    $actualImageId = Invoke-Native -FilePath 'docker' -Arguments @(
        'inspect', '--format', '{{.Image}}', $containerId
    ) -Capture
    if ($actualImageId -cne $ExpectedImageId) {
        throw "La identidad activa cambió. Esperada='$ExpectedImageId', actual='$actualImageId'."
    }
    return $containerId
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
    [string]::IsNullOrWhiteSpace($dbEnvironment['POSTGRES_USER']) -or
    [string]::IsNullOrWhiteSpace($dbEnvironment['POSTGRES_APP_USER']) -or
    [string]::IsNullOrWhiteSpace($dbEnvironment['POSTGRES_CONTROL_USER'])) {
    throw 'El contenedor de base no expone POSTGRES_DB, POSTGRES_USER, POSTGRES_APP_USER y POSTGRES_CONTROL_USER.'
}
if ($dbEnvironment['POSTGRES_APP_USER'] -ceq $dbEnvironment['POSTGRES_CONTROL_USER']) {
    throw 'Los usuarios runtime tenant y control-plane deben ser distintos.'
}

$previousImageReference = Invoke-Native -FilePath 'docker' -Arguments @(
    'inspect', '--format', '{{.Config.Image}}', $backendContainer
) -Capture
$previousContainerImageId = Invoke-Native -FilePath 'docker' -Arguments @(
    'inspect', '--format', '{{.Image}}', $backendContainer
) -Capture
if ($previousContainerImageId -notmatch '^sha256:[a-f0-9]{64}$') {
    throw "El contenedor backend no expone una identidad de imagen inmutable válida: '$previousContainerImageId'."
}
$previousImageId = Resolve-ImageIdentity -Reference $previousContainerImageId
if ($previousImageId -cne $previousContainerImageId) {
    throw "La identidad de imagen activa no es estable: contenedor='$previousContainerImageId', inspect='$previousImageId'."
}
if (-not [string]::IsNullOrWhiteSpace($ExpectedCurrentImage)) {
    $expectedCurrentImageId = Resolve-ImageIdentity -Reference $ExpectedCurrentImage
    if ($previousImageId -cne $expectedCurrentImageId) {
        throw "La imagen actual cambió. Referencia esperada='$ExpectedCurrentImage' ($expectedCurrentImageId), activa='$previousImageReference' ($previousImageId)."
    }
}
$targetImageId = Resolve-ImageIdentity -Reference $TargetBackendImage
if ($previousImageId -ceq $targetImageId) {
    throw "La imagen objetivo ya está activa: $TargetBackendImage ($targetImageId)"
}

$migrationManifest = Get-LocalMigrationManifest
Get-ImageFlywayManifest -ImageId $previousImageId -LocalManifest $migrationManifest | Out-Null
Get-ImageFlywayManifest -ImageId $targetImageId -LocalManifest $migrationManifest | Out-Null
$databaseFlywayMode = Assert-FlywayHistory -DbContainer $dbContainer -Manifest $migrationManifest
Assert-ControlPlaneDatabaseContract -DbContainer $dbContainer `
    -ApplicationRole $dbEnvironment['POSTGRES_APP_USER'] `
    -ControlRole $dbEnvironment['POSTGRES_CONTROL_USER']

$previousHealthContract = Get-ImageHealthContract -Image $previousImageId
$targetHealthContract = Get-ImageHealthContract -Image $targetImageId
Assert-ActiveBackendImageId -ExpectedImageId $previousImageId | Out-Null

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
    Assert-ActiveBackendImageId -ExpectedImageId $previousImageId | Out-Null
}

Write-Host "Imagen actual: $previousImageReference -> $previousImageId"
Write-Host "Imagen objetivo: $TargetBackendImage -> $targetImageId"
Write-Host "Flyway base/artefactos: $databaseFlywayMode V$($migrationManifest.LatestVersion) / $($migrationManifest.Baseline.Script)"
Write-Host "Health actual/objetivo: $previousHealthContract -> $targetHealthContract"
if ($backupDirectory) { Write-Host "Backup previo: $backupDirectory" }

try {
    Switch-BackendImage -ImageId $targetImageId -HealthContract $targetHealthContract | Out-Null
    $targetDatabaseFlywayMode = Assert-FlywayHistory -DbContainer $dbContainer -Manifest $migrationManifest
    if ($targetDatabaseFlywayMode -cne $databaseFlywayMode) {
        throw "El rollback cambió el modo Flyway de $databaseFlywayMode a $targetDatabaseFlywayMode."
    }
    Assert-ControlPlaneDatabaseContract -DbContainer $dbContainer `
        -ApplicationRole $dbEnvironment['POSTGRES_APP_USER'] `
        -ControlRole $dbEnvironment['POSTGRES_CONTROL_USER']
}
catch {
    $rollbackFailure = $_
    Write-Warning "La imagen objetivo no quedó operativa. Se intentará recuperar '$previousImageId'."
    try {
        Switch-BackendImage -ImageId $previousImageId -HealthContract $previousHealthContract | Out-Null
        $recoveredFlywayMode = Assert-FlywayHistory -DbContainer $dbContainer -Manifest $migrationManifest
        if ($recoveredFlywayMode -cne $databaseFlywayMode) {
            throw "La recuperación cambió el modo Flyway de $databaseFlywayMode a $recoveredFlywayMode."
        }
        Assert-ControlPlaneDatabaseContract -DbContainer $dbContainer `
            -ApplicationRole $dbEnvironment['POSTGRES_APP_USER'] `
            -ControlRole $dbEnvironment['POSTGRES_CONTROL_USER']
    }
    catch {
        throw "Falló el rollback y también la recuperación automática. Rollback: $($rollbackFailure.Exception.Message). Recuperación: $($_.Exception.Message)"
    }
    throw "La imagen objetivo falló y se recuperó la imagen anterior. Error original: $($rollbackFailure.Exception.Message)"
}

Write-Host "Rollback de aplicación completado: $previousImageId -> $targetImageId" -ForegroundColor Green
Write-Output ([ordered]@{
    previousImage = $previousImageReference
    previousImageId = $previousImageId
    previousHealthContract = $previousHealthContract
    targetImage = $TargetBackendImage
    targetImageId = $targetImageId
    targetHealthContract = $targetHealthContract
    flywayVersion = $migrationManifest.LatestVersion
    flywayMode = $databaseFlywayMode
    flywayBaselineScript = $migrationManifest.Baseline.Script
    flywayResourceCount = $migrationManifest.Resources.Count
    backupDirectory = $backupDirectory
} | ConvertTo-Json -Compress)
