<#
.SYNOPSIS
Recrea el schema public de una base Gestudio efímera y verifica su convergencia.

.DESCRIPTION
Herramienta destructiva separada del deploy. Sólo acepta proyectos dev, test o
ephemeral con nombres canónicos correlacionados. Antes de ejecutar DROP SCHEMA
valida la configuración Compose efectiva, las credenciales sintéticas, el ID y
los labels exactos del contenedor db, el volumen aislado y la identidad de la
base. Después recrea public, arranca el backend para Flyway/Hibernate y verifica
historial, runtime sin privilegios elevados, ausencia de seed funcional y health.

No descubre recursos por nombre parcial, no elimina volúmenes y nunca acepta
production, staging, demo remota ni el proyecto protegido gestudio-remote-demo.

.PARAMETER TargetEnvironment
Entorno exacto permitido: dev, test o ephemeral.

.PARAMETER ProjectName
Proyecto Compose exacto: gestudio-<entorno>-<12 hex>.

.PARAMETER DatabaseName
Base exacta derivada del proyecto reemplazando guiones por guiones bajos.

.PARAMETER DockerContext
Contexto Docker local explícito; se rechazan endpoints TCP, SSH o remotos.

.PARAMETER EnvFile
Archivo de entorno sintético y privado usado por el proyecto efímero.

.PARAMETER ComposeFile
Compose canónico del repositorio. No se aceptan Compose alternativos.

.PARAMETER Confirmation
Frase exacta RESET-EPHEMERAL-DATABASE:<contexto>:<proyecto>:<base>.

.PARAMETER TimeoutSeconds
Espera máxima del backend healthy, entre 60 y 900 segundos.

.PARAMETER Help
Muestra uso y termina sin consultar Docker.

.EXAMPLE
pwsh -NoProfile -File .\scripts\ops\reset-ephemeral-database.ps1 -TargetEnvironment ephemeral -DockerContext desktop-linux -ProjectName gestudio-ephemeral-a1b2c3d4e5f6 -DatabaseName gestudio_ephemeral_a1b2c3d4e5f6 -EnvFile C:\secure\gestudio-ephemeral.env -Confirmation RESET-EPHEMERAL-DATABASE:desktop-linux:gestudio-ephemeral-a1b2c3d4e5f6:gestudio_ephemeral_a1b2c3d4e5f6
#>
[CmdletBinding()]
param(
    [string] $TargetEnvironment,
    [string] $DockerContext,
    [string] $ProjectName,
    [string] $DatabaseName,
    [string] $EnvFile,
    [string] $ComposeFile,
    [string] $Confirmation,
    [int] $TimeoutSeconds = 300,
    [switch] $Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$canonicalComposeFile = [IO.Path]::GetFullPath((Join-Path $repoRoot 'docker-compose.yml'))
$script:expectedDatabaseSecrets = $null
$script:expectedBackendImage = $null
$script:resolvedDockerContext = $null

function Show-Usage {
    Write-Output @'
Reset destructivo permitido sólo sobre una base Gestudio efímera ya iniciada.

Uso:
  pwsh -NoProfile -File .\scripts\ops\reset-ephemeral-database.ps1 `
    -TargetEnvironment ephemeral `
    -DockerContext desktop-linux `
    -ProjectName gestudio-ephemeral-<12-hex> `
    -DatabaseName gestudio_ephemeral_<12_hex> `
    -EnvFile <archivo-privado> `
    -Confirmation RESET-EPHEMERAL-DATABASE:<contexto>:<proyecto>:<base>

El contenedor db debe existir, estar healthy y usar el volumen y los labels
exactos de ese proyecto. Use -Help o Get-Help <script> -Full para más detalles.
'@
}

function Assert-StaticSafetyContract {
    $missing = @()
    foreach ($entry in ([ordered]@{
        TargetEnvironment = $TargetEnvironment
        DockerContext = $DockerContext
        ProjectName = $ProjectName
        DatabaseName = $DatabaseName
        EnvFile = $EnvFile
        Confirmation = $Confirmation
    }).GetEnumerator()) {
        if ([string]::IsNullOrWhiteSpace([string] $entry.Value)) {
            $missing += $entry.Key
        }
    }
    if ($missing.Count -gt 0) {
        throw "Faltan parámetros explícitos: $($missing -join ', '). Use -Help."
    }

    if ($TargetEnvironment -cnotin @('dev', 'test', 'ephemeral')) {
        throw "TargetEnvironment '$TargetEnvironment' rechazado: sólo dev, test o ephemeral."
    }
    if ($DockerContext -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$' -or
        $DockerContext -match '(?i)(^|[-_.])(prod(?:uction)?|stag(?:e|ing)?|remote|demo)([-_.]|$)') {
        throw 'DockerContext inválido o asociado por nombre a production, staging, remote o demo.'
    }
    if ($ProjectName -ceq 'gestudio-remote-demo') {
        throw 'gestudio-remote-demo está protegido y nunca puede resetearse con esta herramienta.'
    }
    if ($ProjectName -match '(?i)(^|[-_])(prod(?:uction)?|stag(?:e|ing)?|remote|demo)([-_]|$)') {
        throw 'ProjectName parece production, staging, remote o demo y fue rechazado.'
    }
    $projectPattern = '^gestudio-' + [Regex]::Escape($TargetEnvironment) + '-[a-f0-9]{12}$'
    if ($ProjectName -cnotmatch $projectPattern) {
        throw "ProjectName debe ser gestudio-$TargetEnvironment-<12 hex> en minúsculas."
    }
    $expectedDatabase = $ProjectName.Replace('-', '_')
    if ($DatabaseName -cne $expectedDatabase) {
        throw "DatabaseName debe ser exactamente '$expectedDatabase'."
    }
    $expectedConfirmation = "RESET-EPHEMERAL-DATABASE:${DockerContext}:${ProjectName}:${DatabaseName}"
    if ($Confirmation -cne $expectedConfirmation) {
        throw "Confirmación inválida. Se exige exactamente: $expectedConfirmation"
    }
    if ($TimeoutSeconds -lt 60 -or $TimeoutSeconds -gt 900) {
        throw 'TimeoutSeconds debe estar entre 60 y 900.'
    }
}

function Invoke-Native {
    param(
        [Parameter(Mandatory)][string] $FilePath,
        [Parameter(Mandatory)][string[]] $Arguments,
        [Parameter(Mandatory)][string] $Operation,
        [switch] $Capture
    )

    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $effectiveArguments = $Arguments
        if ($FilePath -ceq 'docker' -and -not [string]::IsNullOrWhiteSpace($script:resolvedDockerContext)) {
            $effectiveArguments = @('--context', $script:resolvedDockerContext) + $Arguments
        }
        $output = @(& $FilePath @effectiveArguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousPreference }
    if ($exitCode -ne 0) {
        throw "$Operation falló con exit code $exitCode. No se muestran salidas que puedan contener secretos."
    }
    if ($Capture) {
        return (($output | ForEach-Object { $_.ToString() }) -join "`n").Trim()
    }
}

function Get-ComposePrefix {
    return @(
        'compose', '-f', $canonicalComposeFile,
        '--env-file', ([IO.Path]::GetFullPath($EnvFile)),
        '-p', $ProjectName
    )
}

function Invoke-Compose {
    param(
        [Parameter(Mandatory)][string[]] $Arguments,
        [Parameter(Mandatory)][string] $Operation,
        [switch] $Capture
    )
    return Invoke-Native -FilePath 'docker' -Arguments ((Get-ComposePrefix) + $Arguments) `
        -Operation $Operation -Capture:$Capture
}

function Get-RequiredProperty {
    param(
        [Parameter(Mandatory)][object] $Object,
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $Context
    )
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { throw "Falta $Context.$Name en Compose efectivo." }
    return $property.Value
}

function Assert-ExactValue {
    param(
        [AllowNull()][object] $Actual,
        [Parameter(Mandatory)][string] $Expected,
        [Parameter(Mandatory)][string] $Name
    )
    if ([string] $Actual -cne $Expected) {
        throw "$Name no cumple el contrato efímero esperado."
    }
}

function Get-EphemeralIdentity {
    $suffix = $ProjectName.Substring($ProjectName.Length - 12)
    return [ordered]@{
        Suffix = $suffix
        Owner = "ge_${suffix}_owner"
        App = "ge_${suffix}_app"
        Control = "ge_${suffix}_ctl"
        PasswordPrefix = "ephemeral-${suffix}-"
        Volume = "${ProjectName}_postgres_data"
    }
}

function Assert-SyntheticSecret {
    param(
        [AllowNull()][object] $Value,
        [Parameter(Mandatory)][string] $ExpectedPrefix,
        [Parameter(Mandatory)][string] $Name
    )
    $text = [string] $Value
    if (-not $text.StartsWith($ExpectedPrefix, [StringComparison]::Ordinal) -or
        $text.Length -lt ($ExpectedPrefix.Length + 24) -or
        $text -notmatch '^[A-Za-z0-9_-]+$') {
        throw "$Name debe ser un secreto sintético dedicado con el prefijo efímero requerido."
    }
}

function Assert-ComposeModel {
    param([Parameter(Mandatory)][object] $Config)

    $identity = Get-EphemeralIdentity
    Assert-ExactValue -Actual (Get-RequiredProperty $Config 'name' 'config') `
        -Expected $ProjectName -Name 'config.name'
    $services = Get-RequiredProperty $Config 'services' 'config'
    $db = Get-RequiredProperty $services 'db' 'services'
    $backend = Get-RequiredProperty $services 'backend' 'services'
    $dbEnvironment = Get-RequiredProperty $db 'environment' 'services.db'
    $backendEnvironment = Get-RequiredProperty $backend 'environment' 'services.backend'
    $expectedBackendImage = "gestudio-backend:ephemeral-$($identity.Suffix)"
    Assert-ExactValue (Get-RequiredProperty $backend 'image' 'services.backend') `
        $expectedBackendImage 'backend.image'
    $script:expectedBackendImage = $expectedBackendImage

    Assert-ExactValue (Get-RequiredProperty $dbEnvironment 'POSTGRES_DB' 'db.environment') `
        $DatabaseName 'POSTGRES_DB'
    Assert-ExactValue (Get-RequiredProperty $dbEnvironment 'POSTGRES_USER' 'db.environment') `
        $identity.Owner 'POSTGRES_USER'
    Assert-ExactValue (Get-RequiredProperty $dbEnvironment 'POSTGRES_APP_USER' 'db.environment') `
        $identity.App 'POSTGRES_APP_USER'
    Assert-ExactValue (Get-RequiredProperty $dbEnvironment 'POSTGRES_CONTROL_USER' 'db.environment') `
        $identity.Control 'POSTGRES_CONTROL_USER'

    $passwords = @(
        [string](Get-RequiredProperty $dbEnvironment 'POSTGRES_PASSWORD' 'db.environment'),
        [string](Get-RequiredProperty $dbEnvironment 'POSTGRES_APP_PASSWORD' 'db.environment'),
        [string](Get-RequiredProperty $dbEnvironment 'POSTGRES_CONTROL_PASSWORD' 'db.environment')
    )
    Assert-SyntheticSecret $passwords[0] $identity.PasswordPrefix 'POSTGRES_PASSWORD'
    Assert-SyntheticSecret $passwords[1] $identity.PasswordPrefix 'POSTGRES_APP_PASSWORD'
    Assert-SyntheticSecret $passwords[2] $identity.PasswordPrefix 'POSTGRES_CONTROL_PASSWORD'
    if (@($passwords | Sort-Object -Unique).Count -ne 3) {
        throw 'Las tres credenciales DB efímeras deben ser distintas.'
    }
    $script:expectedDatabaseSecrets = @{
        POSTGRES_PASSWORD = $passwords[0]
        POSTGRES_APP_PASSWORD = $passwords[1]
        POSTGRES_CONTROL_PASSWORD = $passwords[2]
    }

    $expectedProfile = if ($TargetEnvironment -ceq 'test') { 'test' } else { 'dev' }
    foreach ($contract in ([ordered]@{
        SPRING_PROFILES_ACTIVE = $expectedProfile
        SPRING_DATASOURCE_URL = "jdbc:postgresql://db:5432/$DatabaseName"
        SPRING_DATASOURCE_USERNAME = $identity.App
        APP_PLATFORM_DATASOURCE_URL = "jdbc:postgresql://db:5432/$DatabaseName"
        APP_PLATFORM_DATASOURCE_USERNAME = $identity.Control
        SPRING_FLYWAY_USER = $identity.Owner
        SPRING_FLYWAY_ENABLED = 'true'
        SPRING_FLYWAY_BASELINE_ON_MIGRATE = 'false'
        SPRING_JPA_HIBERNATE_DDL_AUTO = 'validate'
        APP_MULTITENANCY_REQUIRED = 'true'
        APP_SCHEDULING_ENABLED = 'false'
        APP_EMAIL_ENABLED = 'false'
        APP_EMAIL_REAL_NETWORK_ALLOWED = 'false'
        APP_EMAIL_KILL_SWITCH = 'true'
        APP_BOOTSTRAP_SUPERADMIN_ENABLED = 'false'
        APP_LOCAL_ADMIN_PASSWORD_RESET_ENABLED = 'false'
    }).GetEnumerator()) {
        Assert-ExactValue (Get-RequiredProperty $backendEnvironment $contract.Key 'backend.environment') `
            ([string] $contract.Value) $contract.Key
    }
    Assert-ExactValue (Get-RequiredProperty $backendEnvironment 'SPRING_DATASOURCE_PASSWORD' 'backend.environment') `
        $passwords[1] 'SPRING_DATASOURCE_PASSWORD'
    Assert-ExactValue (Get-RequiredProperty $backendEnvironment 'APP_PLATFORM_DATASOURCE_PASSWORD' 'backend.environment') `
        $passwords[2] 'APP_PLATFORM_DATASOURCE_PASSWORD'
    Assert-ExactValue (Get-RequiredProperty $backendEnvironment 'SPRING_FLYWAY_PASSWORD' 'backend.environment') `
        $passwords[0] 'SPRING_FLYWAY_PASSWORD'
    Assert-SyntheticSecret (Get-RequiredProperty $backendEnvironment 'JWT_SECRET' 'backend.environment') `
        $identity.PasswordPrefix 'JWT_SECRET'
    $mfaKey = [string](Get-RequiredProperty $backendEnvironment `
        'APP_PLATFORM_MFA_ENCRYPTION_KEY' 'backend.environment')
    try { $mfaKeyBytes = [Convert]::FromBase64String($mfaKey) }
    catch { throw 'APP_PLATFORM_MFA_ENCRYPTION_KEY debe ser Base64 sintético válido.' }
    if ($mfaKeyBytes.Length -ne 32 -or
        $mfaKey -ceq 'bG9jYWwtb25seS1tZmEta2V5LTMyLWJ5dGUtdmFsdWU=') {
        throw 'APP_PLATFORM_MFA_ENCRYPTION_KEY debe ser una clave efímera nueva de 32 bytes.'
    }
    foreach ($blankSetting in @(
        'APP_OBSERVABILITY_METRICS_TOKEN',
        'APP_LOCAL_ADMIN_PASSWORD_RESET_USERNAME',
        'APP_LOCAL_ADMIN_PASSWORD_RESET_PASSWORD',
        'APP_EMAIL_FROM_ADDRESS',
        'APP_EMAIL_GMAIL_USERNAME',
        'APP_EMAIL_GMAIL_APP_PASSWORD',
        'APP_EMAIL_SENT_COPY_USERNAME',
        'APP_EMAIL_SENT_COPY_APP_PASSWORD')) {
        if (-not [string]::IsNullOrEmpty([string](Get-RequiredProperty `
            $backendEnvironment $blankSetting 'backend.environment'))) {
            throw "$blankSetting debe estar vacío en un reset efímero."
        }
    }

    $dbVolumes = @(Get-RequiredProperty $db 'volumes' 'services.db')
    $dataMounts = @($dbVolumes | Where-Object {
        [string] $_.type -ceq 'volume' -and
        [string] $_.source -ceq 'postgres_data' -and
        [string] $_.target -ceq '/var/lib/postgresql/data'
    })
    if ($dataMounts.Count -ne 1) {
        throw 'db debe usar exactamente el volumen lógico postgres_data en su destino canónico.'
    }
    $volumes = Get-RequiredProperty $Config 'volumes' 'config'
    $postgresVolume = Get-RequiredProperty $volumes 'postgres_data' 'volumes'
    $external = $postgresVolume.PSObject.Properties['external']
    if ($null -ne $external -and [bool] $external.Value) {
        throw 'postgres_data no puede ser un volumen externo.'
    }
}

function Get-ExactServiceContainerId {
    param(
        [Parameter(Mandatory)][string] $Service,
        [switch] $Optional
    )
    $raw = Invoke-Compose -Arguments @('ps', '-a', '-q', $Service) `
        -Operation "consulta exacta del contenedor $Service" -Capture
    $ids = @(($raw -split "`r?`n") | Where-Object { $_ -match '^[a-f0-9]{12,64}$' })
    if ($ids.Count -eq 0 -and $Optional) { return $null }
    if ($ids.Count -ne 1) {
        throw "El proyecto debe tener exactamente un contenedor $Service; encontrados=$($ids.Count)."
    }
    $fullId = Invoke-Native -FilePath 'docker' -Arguments @(
        'inspect', '--format', '{{.Id}}', $ids[0]
    ) -Operation "resolución del ID completo de $Service" -Capture
    if ($fullId -notmatch '^[a-f0-9]{64}$') {
        throw "Docker no devolvió un ID completo para $Service."
    }
    return $fullId
}

function Get-ContainerInspection {
    param([Parameter(Mandatory)][string] $ContainerId)
    $raw = Invoke-Native -FilePath 'docker' -Arguments @('inspect', $ContainerId) `
        -Operation 'inspección exacta del contenedor' -Capture
    try { $items = @($raw | ConvertFrom-Json) }
    catch { throw 'Docker devolvió metadata de contenedor inválida.' }
    if ($items.Count -ne 1) { throw 'La inspección debe resolver exactamente un contenedor.' }
    return $items[0]
}

function Assert-OwnedContainer {
    param(
        [Parameter(Mandatory)][string] $ContainerId,
        [Parameter(Mandatory)][string] $Service,
        [switch] $RequireHealthy
    )
    $container = Get-ContainerInspection $ContainerId
    if ([string] $container.Id -cne $ContainerId -or
        [string] $container.Config.Labels.'com.docker.compose.project' -cne $ProjectName -or
        [string] $container.Config.Labels.'com.docker.compose.service' -cne $Service -or
        [string] $container.Config.Labels.'com.docker.compose.oneoff' -ine 'False' -or
        [string] $container.Config.Labels.'com.docker.compose.container-number' -cne '1') {
        throw "El contenedor $Service no tiene ID y labels Compose exactos del proyecto."
    }
    if ($RequireHealthy -and
        (-not [bool] $container.State.Running -or [string] $container.State.Health.Status -cne 'healthy')) {
        throw "El contenedor $Service debe estar running y healthy antes de continuar."
    }
    return $container
}

function Get-ContainerEnvironment {
    param([Parameter(Mandatory)][object] $Container)
    $values = @{}
    foreach ($entry in @($Container.Config.Env)) {
        $parts = ([string] $entry).Split(@('='), 2)
        if ($parts.Count -eq 2) { $values[$parts[0]] = $parts[1] }
    }
    return $values
}

function Assert-DatabaseOwnership {
    param(
        [Parameter(Mandatory)][string] $ContainerId,
        [Parameter(Mandatory)][object] $Container
    )
    $identity = Get-EphemeralIdentity
    $containerEnvironment = Get-ContainerEnvironment $Container
    foreach ($contract in ([ordered]@{
        POSTGRES_DB = $DatabaseName
        POSTGRES_USER = $identity.Owner
        POSTGRES_APP_USER = $identity.App
        POSTGRES_CONTROL_USER = $identity.Control
    }).GetEnumerator()) {
        if (-not $containerEnvironment.ContainsKey($contract.Key) -or
            [string] $containerEnvironment[$contract.Key] -cne [string] $contract.Value) {
            throw "El contenedor db no conserva $($contract.Key) exacto del target."
        }
    }
    if ($null -eq $script:expectedDatabaseSecrets) {
        throw 'No existe un contrato de secretos Compose previamente validado.'
    }
    foreach ($secretName in @(
        'POSTGRES_PASSWORD', 'POSTGRES_APP_PASSWORD', 'POSTGRES_CONTROL_PASSWORD')) {
        if (-not $containerEnvironment.ContainsKey($secretName) -or
            [string] $containerEnvironment[$secretName] -cne
                [string] $script:expectedDatabaseSecrets[$secretName]) {
            throw "El contenedor db no coincide con el secreto sintético $secretName del env efectivo."
        }
    }

    $dataMounts = @($Container.Mounts | Where-Object {
        [string] $_.Type -ceq 'volume' -and
        [string] $_.Destination -ceq '/var/lib/postgresql/data'
    })
    if ($dataMounts.Count -ne 1 -or [string] $dataMounts[0].Name -cne $identity.Volume) {
        throw 'El contenedor db no monta el volumen aislado exacto esperado.'
    }
    $volumeRaw = Invoke-Native -FilePath 'docker' -Arguments @('volume', 'inspect', $identity.Volume) `
        -Operation 'inspección exacta del volumen PostgreSQL' -Capture
    try { $volumes = @($volumeRaw | ConvertFrom-Json) }
    catch { throw 'Docker devolvió metadata de volumen inválida.' }
    if ($volumes.Count -ne 1 -or [string] $volumes[0].Name -cne $identity.Volume -or
        [string] $volumes[0].Labels.'com.docker.compose.project' -cne $ProjectName -or
        [string] $volumes[0].Labels.'com.docker.compose.volume' -cne 'postgres_data') {
        throw 'El volumen no tiene nombre y labels Compose exactos del proyecto efímero.'
    }
    $attachmentsRaw = Invoke-Native -FilePath 'docker' -Arguments @(
        'ps', '-a', '--no-trunc', '--filter', "volume=$($identity.Volume)", '-q'
    ) -Operation 'consulta exacta de consumidores del volumen' -Capture
    $attachments = @(($attachmentsRaw -split "`r?`n") | Where-Object { $_ -match '^[a-f0-9]{64}$' })
    if ($attachments.Count -ne 1 -or $attachments[0] -cne $ContainerId) {
        throw 'El volumen PostgreSQL está compartido o no pertenece sólo al contenedor db validado.'
    }

    $databaseIdentity = (Invoke-DatabaseSql -ContainerId $ContainerId -Sql @'
SELECT current_database() || '|' || current_user || '|' || pg_get_userbyid(datdba)
FROM pg_database
WHERE datname = current_database();
'@).Trim()
    if ($databaseIdentity -cne "$DatabaseName|$($identity.Owner)|$($identity.Owner)") {
        throw 'La sesión PostgreSQL no confirma la base, el migrador y el owner efímeros esperados.'
    }
    foreach ($runtime in @(
        @{ UserVariable = 'POSTGRES_APP_USER'; PasswordVariable = 'POSTGRES_APP_PASSWORD' },
        @{ UserVariable = 'POSTGRES_CONTROL_USER'; PasswordVariable = 'POSTGRES_CONTROL_PASSWORD' })) {
        $shellCommand = 'PGPASSWORD="$' + $runtime.PasswordVariable +
            '" psql --no-psqlrc --host=127.0.0.1 --tuples-only --no-align' +
            ' --set ON_ERROR_STOP=1 --username="$' + $runtime.UserVariable +
            '" --dbname="$POSTGRES_DB" --command="SELECT 1"'
        $authentication = Invoke-Native -FilePath 'docker' -Arguments @(
            'exec', $ContainerId, 'sh', '-ec', $shellCommand
        ) -Operation "autenticación sintética $($runtime.UserVariable)" -Capture
        if ($authentication.Trim() -cne '1') {
            throw "La credencial sintética $($runtime.UserVariable) no autentica contra la base efímera."
        }
    }
}

function Invoke-DatabaseSql {
    param(
        [Parameter(Mandatory)][string] $ContainerId,
        [Parameter(Mandatory)][string] $Sql
    )
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Sql))
    return Invoke-Native -FilePath 'docker' -Arguments @(
        'exec', $ContainerId, 'sh', '-ec',
        'printf "%s" "$1" | base64 -d | psql --no-psqlrc --tuples-only --no-align --set ON_ERROR_STOP=1 --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" --file=-',
        'sh', $encoded
    ) -Operation 'operación SQL acotada a la base efímera validada' -Capture
}

function Get-LocalMigrationManifest {
    $migrationRoot = Join-Path $repoRoot 'backend\src\main\resources\db\migration'
    $versioned = @(Get-ChildItem -LiteralPath $migrationRoot -File | ForEach-Object {
        if ($_.Name -match '^V(?<version>[0-9]+)__(?<description>.+)\.sql$') {
            [pscustomobject]@{ Version = [int] $Matches.version; Script = $_.Name }
        }
    } | Sort-Object Version)
    if ($versioned.Count -eq 0) { throw 'No se encontraron migraciones V locales.' }
    for ($index = 0; $index -lt $versioned.Count; $index++) {
        if ($versioned[$index].Version -ne ($index + 1)) {
            throw 'Las migraciones V locales no forman una cadena contigua desde V1.'
        }
    }
    $latest = $versioned[-1].Version
    $baselines = @(Get-ChildItem -LiteralPath $migrationRoot -File | Where-Object {
        $_.Name -match "^B${latest}__.+\.sql$"
    })
    if ($baselines.Count -ne 1) {
        throw "Debe existir exactamente una baseline B$latest local."
    }
    return [ordered]@{
        Latest = $latest
        Versioned = @($versioned.Script)
        Baseline = $baselines[0].Name
    }
}

function Assert-BackendImageMatchesMigrations {
    if ([string]::IsNullOrWhiteSpace($script:expectedBackendImage)) {
        throw 'No existe una imagen backend efímera previamente validada.'
    }
    $manifest = Get-LocalMigrationManifest
    $imageIdsRaw = Invoke-Native -FilePath 'docker' -Arguments @(
        'image', 'ls', '--no-trunc', '--quiet', $script:expectedBackendImage
    ) -Operation 'resolución exacta de la imagen backend efímera' -Capture
    $imageIds = @(($imageIdsRaw -split "`r?`n") | Where-Object { $_ -match '^sha256:[a-f0-9]{64}$' })
    if ($imageIds.Count -ne 1) {
        throw 'Debe existir exactamente una imagen backend con el tag efímero validado.'
    }
    $imageLatest = (Invoke-Native -FilePath 'docker' -Arguments @(
        'run', '--rm', '--network', 'none', '--pull', 'never',
        '--entrypoint', 'cat', $script:expectedBackendImage,
        '/app/build-metadata/flyway-latest'
    ) -Operation 'validación pre-destructiva de metadata Flyway' -Capture).Trim()
    if ($imageLatest -cne [string] $manifest.Latest) {
        throw 'La imagen backend efímera no corresponde a la última migración local.'
    }
}

function Assert-FlywayAndRuntime {
    param(
        [Parameter(Mandatory)][string] $DatabaseContainerId,
        [Parameter(Mandatory)][string] $BackendContainerId
    )
    $identity = Get-EphemeralIdentity
    $manifest = Get-LocalMigrationManifest
    $imageLatest = (Invoke-Native -FilePath 'docker' -Arguments @(
        'exec', $BackendContainerId, 'cat', '/app/build-metadata/flyway-latest'
    ) -Operation 'lectura de metadata Flyway de la imagen backend' -Capture).Trim()
    if ($imageLatest -cne [string] $manifest.Latest) {
        throw 'La imagen backend no corresponde a la última migración local.'
    }

    $historyRaw = Invoke-DatabaseSql -ContainerId $DatabaseContainerId -Sql @'
SELECT version || '|' || type || '|' || script
FROM flyway_schema_history
WHERE success
ORDER BY installed_rank;
'@
    $history = @(($historyRaw -split "`r?`n") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $failed = (Invoke-DatabaseSql -ContainerId $DatabaseContainerId `
        -Sql 'SELECT count(*) FROM flyway_schema_history WHERE NOT success;').Trim()
    $baselineHistory = $history.Count -eq 1 -and
        $history[0] -ceq "$($manifest.Latest)|SQL_BASELINE|$($manifest.Baseline)"
    $versionedHistory = $history.Count -eq $manifest.Versioned.Count
    if ($versionedHistory) {
        for ($index = 0; $index -lt $manifest.Versioned.Count; $index++) {
            if ($history[$index] -cne "$($index + 1)|SQL|$($manifest.Versioned[$index])") {
                $versionedHistory = $false
                break
            }
        }
    }
    if ($failed -cne '0' -or (-not $baselineHistory -and -not $versionedHistory)) {
        throw 'Flyway no validó una cadena V completa ni la baseline fresh local exacta.'
    }

    $runtimeRolesSql = @"
SELECT count(*)
FROM pg_roles
WHERE rolname IN ('$($identity.App)', '$($identity.Control)')
  AND rolcanlogin
  AND NOT rolsuper
  AND NOT rolcreaterole
  AND NOT rolcreatedb
  AND NOT rolreplication
  AND NOT rolbypassrls;
"@
    if ((Invoke-DatabaseSql -ContainerId $DatabaseContainerId -Sql $runtimeRolesSql).Trim() -cne '2') {
        throw 'Los runtimes efímeros no conservan el contrato NOSUPERUSER/NOBYPASSRLS.'
    }
    $functionalRows = (Invoke-DatabaseSql -ContainerId $DatabaseContainerId -Sql @'
SELECT
  (SELECT count(*) FROM tenants)::text || '|' ||
  (SELECT count(*) FROM usuarios)::text || '|' ||
  (SELECT count(*) FROM tenant_memberships)::text || '|' ||
  (SELECT count(*) FROM alumnos)::text || '|' ||
  (SELECT count(*) FROM profesores)::text || '|' ||
  (SELECT count(*) FROM pagos)::text;
'@).Trim()
    if ($functionalRows -cne '0|0|0|0|0|0') {
        throw 'La reconstrucción fresh contiene seed funcional inesperado.'
    }
}

if ($Help) {
    Show-Usage
    return
}

Assert-StaticSafetyContract
if (-not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable('DOCKER_HOST', 'Process'))) {
    throw 'DOCKER_HOST está definido; se rechazan overrides que podrían apuntar a un daemon remoto.'
}
if ([string]::IsNullOrWhiteSpace($ComposeFile)) { $ComposeFile = $canonicalComposeFile }
$resolvedComposeFile = [IO.Path]::GetFullPath($ComposeFile)
if ($resolvedComposeFile -cne $canonicalComposeFile) {
    throw "ComposeFile debe ser exactamente el canónico: $canonicalComposeFile"
}
if (-not (Test-Path -LiteralPath $canonicalComposeFile -PathType Leaf)) {
    throw "No existe el Compose canónico: $canonicalComposeFile"
}
if (-not (Test-Path -LiteralPath $EnvFile -PathType Leaf)) {
    throw 'EnvFile debe existir como archivo privado antes del reset.'
}
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'Docker CLI no está disponible; no se realizó ninguna mutación.'
}

$script:resolvedDockerContext = $DockerContext
$endpointRaw = Invoke-Native -FilePath 'docker' -Arguments @(
    'context', 'inspect', '--format', '{{json .Endpoints.docker.Host}}', $DockerContext
) -Operation 'validación del contexto Docker local' -Capture
try { $dockerEndpoint = [string] ($endpointRaw | ConvertFrom-Json) }
catch { throw 'El contexto Docker no devolvió un endpoint válido.' }
if ($dockerEndpoint -notmatch '^npipe://' -and $dockerEndpoint -cne 'unix:///var/run/docker.sock') {
    throw 'DockerContext no apunta a un endpoint local permitido; TCP, SSH y endpoints remotos se rechazan.'
}
[void](Invoke-Native -FilePath 'docker' -Arguments @('version', '--format', '{{.Server.Version}}') `
    -Operation 'preflight del Docker Engine' -Capture)
[void](Invoke-Native -FilePath 'docker' -Arguments @('compose', 'version', '--short') `
    -Operation 'preflight de Docker Compose' -Capture)
$configRaw = Invoke-Compose -Arguments @('config', '--format', 'json') `
    -Operation 'resolución segura de Compose' -Capture
try { $config = $configRaw | ConvertFrom-Json }
catch { throw 'Docker Compose devolvió configuración efectiva inválida.' }
Assert-ComposeModel -Config $config
$configRaw = $null
$config = $null

$databaseContainerId = Get-ExactServiceContainerId -Service 'db'
$databaseContainer = Assert-OwnedContainer -ContainerId $databaseContainerId -Service 'db' -RequireHealthy
Assert-DatabaseOwnership -ContainerId $databaseContainerId -Container $databaseContainer
$script:expectedDatabaseSecrets = $null
Assert-BackendImageMatchesMigrations
$backendContainerId = Get-ExactServiceContainerId -Service 'backend' -Optional
if ($null -ne $backendContainerId) {
    [void](Assert-OwnedContainer -ContainerId $backendContainerId -Service 'backend')
}

Write-Host "[PASS] Preflight fail-closed: proyecto '$ProjectName', base '$DatabaseName' y volumen aislado verificados."
if ($null -ne $backendContainerId) {
    [void](Invoke-Native -FilePath 'docker' -Arguments @(
        'container', 'stop', '--time', '30', $backendContainerId
    ) -Operation 'detención exacta del backend efímero' -Capture)
}
$otherConnections = (Invoke-DatabaseSql -ContainerId $databaseContainerId -Sql @'
SELECT count(*)
FROM pg_stat_activity
WHERE datname = current_database()
  AND pid <> pg_backend_pid();
'@).Trim()
if ($otherConnections -cne '0') {
    throw "La base efímera conserva $otherConnections conexión(es) ajena(s); se rechaza el DROP SCHEMA."
}

[void](Invoke-DatabaseSql -ContainerId $databaseContainerId -Sql @'
SELECT pg_advisory_lock(hashtext('gestudio_ephemeral_schema_reset_v1'));
BEGIN;
DROP SCHEMA public CASCADE;
CREATE SCHEMA public AUTHORIZATION pg_database_owner;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO PUBLIC;
COMMIT;
'@)
Write-Host '[PASS] Schema public recreado únicamente en la base efímera validada.'

[void](Invoke-Compose -Arguments @(
    'up', '-d', '--no-deps', '--force-recreate', '--wait',
    '--wait-timeout', [string] $TimeoutSeconds, 'backend'
) -Operation 'Flyway migrate, validate y arranque del backend efímero')
$backendContainerId = Get-ExactServiceContainerId -Service 'backend'
[void](Assert-OwnedContainer -ContainerId $backendContainerId -Service 'backend' -RequireHealthy)
Assert-FlywayAndRuntime -DatabaseContainerId $databaseContainerId `
    -BackendContainerId $backendContainerId

Write-Host '[PASS] Reset efímero: Flyway validado, runtime healthy, roles mínimos y cero seed funcional.' -ForegroundColor Green
