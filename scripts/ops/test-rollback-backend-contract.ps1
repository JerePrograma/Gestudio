[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$rollbackScript = Join-Path $PSScriptRoot 'rollback-backend.ps1'
$drillScript = Join-Path $PSScriptRoot 'verify-application-rollback.ps1'
$composeFile = Join-Path $repoRoot 'docker-compose.yml'
$migrationRoot = Join-Path $repoRoot 'backend/src/main/resources/db/migration'
$dockerfile = Join-Path $repoRoot 'backend/Dockerfile'
$workflow = Join-Path $repoRoot '.github/workflows/application-rollback-verification.yml'
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ("gestudio-rollback-contract-" + [Guid]::NewGuid().ToString('N'))
$passes = 0
$failures = 0
$currentImageId = 'sha256:' + [string]::new('a', 64)
$targetImageId = 'sha256:' + [string]::new('b', 64)
$global:GestudioRollbackContractCurrentImageId = $currentImageId
$global:GestudioRollbackContractTargetImageId = $targetImageId
$preexistingDockerFunction = Get-Item -LiteralPath Function:\docker -ErrorAction SilentlyContinue
$preexistingDockerAlias = Get-Alias -Name docker -ErrorAction SilentlyContinue
if ($null -ne $preexistingDockerFunction -or $null -ne $preexistingDockerAlias) {
    throw 'El contrato fake-docker requiere no tener una función ni alias docker preexistente.'
}

function Assert-True {
    param([bool] $Condition, [Parameter(Mandatory)][string] $Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param($Actual, $Expected, [Parameter(Mandatory)][string] $Message)
    if ([string]$Actual -cne [string]$Expected) {
        throw "$Message. Esperado='$Expected', actual='$Actual'."
    }
}

function Pass {
    param([Parameter(Mandatory)][string] $Message)
    $script:passes++
    Write-Host "[PASS] $Message" -ForegroundColor Green
}

function Get-MigrationFixture {
    $entries = @(Get-ChildItem -LiteralPath $migrationRoot -Filter 'V*__*.sql' -File | ForEach-Object {
        if ($_.Name -notmatch '^V(?<version>[0-9]+)__.+\.sql$') {
            throw "Nombre versionado inválido en fixture: $($_.Name)"
        }
        [pscustomobject]@{ Version = [int]$matches.version; Script = $_.Name }
    } | Sort-Object Version)
    Assert-True -Condition ($entries.Count -ge 2) -Message 'La fixture requiere al menos V1 y V2.'
    for ($index = 0; $index -lt $entries.Count; $index++) {
        Assert-Equal -Actual $entries[$index].Version -Expected ($index + 1) `
            -Message 'La cadena local usada por la fixture no es contigua'
    }
    $baselines = @(Get-ChildItem -LiteralPath $migrationRoot -Filter 'B*__*.sql' -File | ForEach-Object {
        if ($_.Name -notmatch '^B(?<version>[0-9]+)__.+\.sql$') {
            throw "Nombre baseline inválido en fixture: $($_.Name)"
        }
        [pscustomobject]@{ Version = [int]$matches.version; Script = $_.Name }
    })
    Assert-True -Condition ($baselines.Count -eq 1) -Message 'La fixture requiere una única baseline.'
    Assert-Equal -Actual $baselines[0].Version -Expected $entries[-1].Version `
        -Message 'La baseline de fixture no coincide con la última versión'
    $resourceNames = [string[]]@(Get-ChildItem -LiteralPath $migrationRoot -File |
        ForEach-Object { $_.Name })
    [Array]::Sort($resourceNames, [StringComparer]::Ordinal)
    $resources = @($resourceNames | ForEach-Object {
        [pscustomobject]@{
            Script = $_
            Sha256 = (Get-FileHash -LiteralPath (Join-Path $migrationRoot $_) -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    })
    $resourceManifest = New-ResourceManifest -Resources $resources
    return [pscustomobject]@{
        Entries = $entries
        LatestVersion = $entries[-1].Version
        BaselineScript = $baselines[0].Script
        Resources = $resources
        ResourceManifest = $resourceManifest
    }
}

function New-ResourceManifest {
    param([Parameter(Mandatory)][object[]] $Resources)

    $names = [string[]]@($Resources | ForEach-Object { $_.Script })
    [Array]::Sort($names, [StringComparer]::Ordinal)
    return (@('gestudio-flyway-manifest-v1') + @($names | ForEach-Object {
        $name = $_
        $resource = @($Resources | Where-Object { $_.Script -ceq $name })
        Assert-Equal -Actual $resource.Count -Expected 1 -Message "Recurso fixture duplicado: $name"
        "$($resource[0].Sha256)`t$name"
    })) -join "`n"
}

function global:docker {
    param([Parameter(ValueFromRemainingArguments = $true)][object[]] $DockerArguments)

    $tokens = @($DockerArguments | ForEach-Object { [string]$_ })
    $global:GestudioRollbackContractDockerCalls += ,$tokens
    $global:LASTEXITCODE = 0

    if ($tokens.Count -eq 1 -and $tokens[0] -ceq 'version') {
        return
    }
    if ($tokens.Count -ge 2 -and $tokens[0] -ceq 'compose' -and $tokens[1] -ceq 'version') {
        return
    }
    if ($tokens.Count -gt 0 -and $tokens[0] -ceq 'compose') {
        $psIndex = -1
        for ($index = 1; $index -lt $tokens.Count; $index++) {
            if ($tokens[$index] -ceq 'ps') { $psIndex = $index; break }
        }
        if ($psIndex -ge 0 -and $psIndex + 2 -lt $tokens.Count -and $tokens[$psIndex + 1] -ceq '-q') {
            if ($tokens[$psIndex + 2] -ceq 'db') { return 'fake-db-container' }
            if ($tokens[$psIndex + 2] -ceq 'backend') { return 'fake-backend-container' }
        }
        if ($tokens -ccontains 'up') {
            $global:GestudioRollbackContractActiveImageId = [string]$env:BACKEND_IMAGE
            return
        }
    }
    if ($tokens.Count -ge 4 -and $tokens[0] -ceq 'inspect' -and $tokens[1] -ceq '--format') {
        if ($tokens[2] -like '*Config.Env*' -and $tokens[3] -ceq 'fake-db-container') {
            return @(
                'POSTGRES_DB=gestudio_contract',
                'POSTGRES_USER=gestudio_contract_owner',
                'POSTGRES_APP_USER=gestudio_contract_runtime',
                'POSTGRES_CONTROL_USER=gestudio_contract_control'
            )
        }
        if ($tokens[2] -ceq '{{.Config.Image}}' -and $tokens[3] -ceq 'fake-backend-container') {
            return 'gestudio-contract-current'
        }
        if ($tokens[2] -ceq '{{.Image}}' -and $tokens[3] -ceq 'fake-backend-container') {
            return $global:GestudioRollbackContractActiveImageId
        }
        if ($tokens[2] -like '*State.Health*' -and $tokens[3] -ceq 'fake-backend-container') {
            return 'healthy'
        }
        if ($tokens[2] -like '*Config.Env*' -and $tokens[3] -ceq 'fake-backend-container') {
            return "BACKEND_HEALTHCHECK_MODE=$env:BACKEND_HEALTHCHECK_MODE"
        }
    }
    if ($tokens.Count -ge 3 -and $tokens[0] -ceq 'image' -and $tokens[1] -ceq 'inspect') {
        $reference = $tokens[-1]
        if ($reference -ceq 'gestudio-contract-current' -or
            $reference -ceq $global:GestudioRollbackContractCurrentImageId) {
            return $global:GestudioRollbackContractCurrentImageId
        }
        if ($reference -ceq 'gestudio-contract-target' -or
            $reference -ceq $global:GestudioRollbackContractTargetImageId) {
            return $global:GestudioRollbackContractTargetImageId
        }
        $global:LASTEXITCODE = 44
        return "fixture: imagen desconocida $reference"
    }
    if ($tokens.Count -ge 6 -and $tokens[0] -ceq 'run' -and $tokens[3] -ceq 'cat') {
        $image = $tokens[4]
        $metadataPath = $tokens[5]
        if ($metadataPath -ceq '/app/build-metadata/flyway-latest' -or
            $metadataPath -ceq '/app/build-metadata/flyway-versioned-latest') {
            return [string]$global:GestudioRollbackContractFixture.LatestVersion
        }
        if ($metadataPath -ceq '/app/build-metadata/flyway-baseline-script') {
            if ($global:GestudioRollbackContractFixture.MissingTargetBaseline -and
                $image -ceq $global:GestudioRollbackContractTargetImageId) {
                $global:LASTEXITCODE = 42
                return 'fixture: falta /app/build-metadata/flyway-baseline-script'
            }
            return [string]$global:GestudioRollbackContractFixture.BaselineScript
        }
        if ($metadataPath -ceq '/app/build-metadata/flyway-resources.sha256') {
            if ($image -ceq $global:GestudioRollbackContractTargetImageId) {
                return [string]$global:GestudioRollbackContractFixture.TargetResourceManifest
            }
            return [string]$global:GestudioRollbackContractFixture.CurrentResourceManifest
        }
    }
    if ($tokens.Count -ge 6 -and $tokens[0] -ceq 'run' -and $tokens[3] -ceq 'sh') {
        return 'actuator-readiness-v1'
    }
    if ($tokens.Count -ge 2 -and $tokens[0] -ceq 'exec' -and $tokens[1] -ceq 'fake-db-container') {
        try {
            $sql = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($tokens[-1]))
        }
        catch {
            $global:LASTEXITCODE = 43
            return 'fixture: SQL no codificado como base64'
        }
        if ($sql -like '*WHERE NOT success*') {
            return [string]$global:GestudioRollbackContractFixture.FailedCount
        }
        if ($sql -like '*FROM flyway_schema_history WHERE success ORDER BY installed_rank*') {
            return ($global:GestudioRollbackContractFixture.HistoryRows -join "`n")
        }
        if ($sql -like '*pg_catalog.pg_auth_members*' -and $sql -like '*platform_admins*') {
            return 'true|true|true|false|false'
        }
    }

    $global:LASTEXITCODE = 99
    return ('fixture: llamada docker inesperada: ' + ($tokens -join ' '))
}

function Assert-NoMutation {
    param(
        [Parameter(Mandatory)][string] $FixtureName,
        [Parameter(Mandatory)][string] $BackupDirectory
    )

    $mutatingComposeOperations = @('up', 'down', 'stop', 'restart', 'rm', 'create', 'run', 'kill')
    foreach ($call in @($global:GestudioRollbackContractDockerCalls)) {
        $tokens = @($call)
        if ($tokens.Count -gt 0 -and $tokens[0] -ceq 'compose') {
            foreach ($operation in $mutatingComposeOperations) {
                Assert-True -Condition ($tokens -cnotcontains $operation) `
                    -Message "La fixture '$FixtureName' alcanzó docker compose $operation antes de rechazar."
            }
        }
    }
    Assert-True -Condition (-not (Test-Path -LiteralPath $BackupDirectory)) `
        -Message "La fixture '$FixtureName' creó el directorio de backup antes de rechazar."
}

function Assert-MetadataUsesImmutableIds {
    param([Parameter(Mandatory)][string] $FixtureName)

    $metadataRuns = @($global:GestudioRollbackContractDockerCalls | Where-Object {
        $_.Count -ge 6 -and $_[0] -ceq 'run' -and $_[3] -ceq 'cat'
    })
    Assert-True -Condition ($metadataRuns.Count -gt 0) `
        -Message "La fixture '$FixtureName' no consultó metadata de imagen."
    foreach ($call in $metadataRuns) {
        Assert-True -Condition ($call[4] -in @(
            $global:GestudioRollbackContractCurrentImageId,
            $global:GestudioRollbackContractTargetImageId)) `
            -Message "La fixture '$FixtureName' consultó metadata mediante un tag mutable: $($call[4])"
    }
}

function Invoke-NegativeFixture {
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][bool] $MissingTargetBaseline,
        [Parameter(Mandatory)][string[]] $HistoryRows,
        [Parameter(Mandatory)][int] $FailedCount,
        [Parameter(Mandatory)][string] $TargetResourceManifest,
        [Parameter(Mandatory)][string] $ExpectedMessage,
        [Parameter(Mandatory)] $MigrationFixture
    )

    $global:GestudioRollbackContractDockerCalls = @()
    $global:GestudioRollbackContractFixture = [pscustomobject]@{
        LatestVersion = $MigrationFixture.LatestVersion
        BaselineScript = $MigrationFixture.BaselineScript
        MissingTargetBaseline = $MissingTargetBaseline
        CurrentResourceManifest = $MigrationFixture.ResourceManifest
        TargetResourceManifest = $TargetResourceManifest
        HistoryRows = $HistoryRows
        FailedCount = $FailedCount
    }
    $global:GestudioRollbackContractActiveImageId = $global:GestudioRollbackContractCurrentImageId
    $backupDirectory = Join-Path $temporaryRoot ("backup-" + $Name)
    $caught = $null
    try {
        & $rollbackScript `
            -TargetBackendImage 'gestudio-contract-target' `
            -ExpectedCurrentImage 'gestudio-contract-current' `
            -ComposeFile $composeFile `
            -ProjectName 'gestudio-rollback-contract' `
            -BackupOutputDirectory $backupDirectory `
            -ConfirmRollback
    }
    catch { $caught = $_ }

    Assert-True -Condition ($null -ne $caught) -Message "La fixture '$Name' no fue rechazada."
    Assert-True -Condition ($caught.Exception.Message -like "*$ExpectedMessage*") `
        -Message "La fixture '$Name' falló por una causa inesperada: $($caught.Exception.Message)"
    Assert-NoMutation -FixtureName $Name -BackupDirectory $backupDirectory
    Assert-MetadataUsesImmutableIds -FixtureName $Name
    Pass "$Name aborta antes de backup y compose up"
}

function Assert-ProtectedProjectRejected {
    $global:GestudioRollbackContractDockerCalls = @()
    $caught = $null
    try {
        & $rollbackScript -TargetBackendImage 'gestudio-contract-target' `
            -ComposeFile $composeFile -ProjectName 'gestudio-remote-demo' -ConfirmRollback
    }
    catch { $caught = $_ }
    Assert-True -Condition ($null -ne $caught -and
        $caught.Exception.Message -like '*gestudio-remote-demo*protegido*') `
        -Message 'El proyecto protegido no fue rechazado explícitamente.'
    Assert-Equal -Actual $global:GestudioRollbackContractDockerCalls.Count -Expected 0 `
        -Message 'El rechazo del proyecto protegido alcanzó Docker'
    Pass 'gestudio-remote-demo se rechaza antes de Docker'
}

function Assert-ImmutableSwitch {
    param(
        [Parameter(Mandatory)][string[]] $HistoryRows,
        [Parameter(Mandatory)] $MigrationFixture
    )

    $global:GestudioRollbackContractDockerCalls = @()
    $global:GestudioRollbackContractActiveImageId = $global:GestudioRollbackContractCurrentImageId
    $global:GestudioRollbackContractFixture = [pscustomobject]@{
        LatestVersion = $MigrationFixture.LatestVersion
        BaselineScript = $MigrationFixture.BaselineScript
        MissingTargetBaseline = $false
        CurrentResourceManifest = $MigrationFixture.ResourceManifest
        TargetResourceManifest = $MigrationFixture.ResourceManifest
        HistoryRows = $HistoryRows
        FailedCount = 0
    }
    $result = @(& $rollbackScript `
        -TargetBackendImage 'gestudio-contract-target' `
        -ExpectedCurrentImage 'gestudio-contract-current' `
        -ComposeFile $composeFile `
        -ProjectName 'gestudio-rollback-contract' `
        -SkipBackup `
        -ConfirmRollback)
    $json = $result[-1] | ConvertFrom-Json
    Assert-Equal -Actual $json.previousImageId -Expected $global:GestudioRollbackContractCurrentImageId `
        -Message 'El resultado no registró la identidad actual fijada'
    Assert-Equal -Actual $json.targetImageId -Expected $global:GestudioRollbackContractTargetImageId `
        -Message 'El resultado no registró la identidad objetivo fijada'
    Assert-Equal -Actual $global:GestudioRollbackContractActiveImageId `
        -Expected $global:GestudioRollbackContractTargetImageId `
        -Message 'Compose no recibió la identidad objetivo fijada'
    $targetResolutions = @($global:GestudioRollbackContractDockerCalls | Where-Object {
        $_.Count -ge 5 -and $_[0] -ceq 'image' -and $_[1] -ceq 'inspect' -and
        $_[-1] -ceq 'gestudio-contract-target'
    })
    Assert-Equal -Actual $targetResolutions.Count -Expected 1 `
        -Message 'La referencia objetivo mutable se resolvió más de una vez'
    Assert-MetadataUsesImmutableIds -FixtureName 'switch-inmutable'
    Pass 'la referencia mutable se resuelve una vez y el switch usa exclusivamente su ID'
}

function Assert-StaticContract {
    $tokens = $null
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile(
        $rollbackScript, [ref]$tokens, [ref]$parseErrors)
    Assert-Equal -Actual $parseErrors.Count -Expected 0 -Message 'rollback-backend.ps1 no parsea'

    $source = Get-Content -LiteralPath $rollbackScript -Raw
    foreach ($metadataPath in @(
        '/app/build-metadata/flyway-latest',
        '/app/build-metadata/flyway-versioned-latest',
        '/app/build-metadata/flyway-baseline-script',
        '/app/build-metadata/flyway-resources.sha256')) {
        Assert-True -Condition $source.Contains($metadataPath) `
            -Message "Falta metadata obligatoria en runtime: $metadataPath"
    }

    $commands = @($ast.FindAll({
        param($node)
        $node -is [Management.Automation.Language.CommandAst]
    }, $true))
    $flywayOffsets = @($commands | Where-Object { $_.GetCommandName() -ceq 'Assert-FlywayHistory' } |
        ForEach-Object { $_.Extent.StartOffset })
    $controlOffsets = @($commands | Where-Object { $_.GetCommandName() -ceq 'Assert-ControlPlaneDatabaseContract' } |
        ForEach-Object { $_.Extent.StartOffset })
    $switchOffsets = @($commands | Where-Object { $_.GetCommandName() -ceq 'Switch-BackendImage' } |
        ForEach-Object { $_.Extent.StartOffset })
    $imageManifestCalls = @($commands | Where-Object { $_.GetCommandName() -ceq 'Get-ImageFlywayManifest' })

    Assert-Equal -Actual $imageManifestCalls.Count -Expected 2 `
        -Message 'Deben calificarse la imagen activa y la objetivo'
    Assert-Equal -Actual $switchOffsets.Count -Expected 2 `
        -Message 'El contrato espera switch objetivo y recuperación'
    Assert-Equal -Actual $flywayOffsets.Count -Expected 3 `
        -Message 'Flyway debe verificarse pre-switch, post-switch y post-recuperación'
    Assert-Equal -Actual $controlOffsets.Count -Expected 3 `
        -Message 'Control-plane debe verificarse pre-switch, post-switch y post-recuperación'
    Assert-True -Condition ($flywayOffsets[0] -lt $switchOffsets[0] -and
        $flywayOffsets[1] -gt $switchOffsets[0] -and $flywayOffsets[1] -lt $switchOffsets[1] -and
        $flywayOffsets[2] -gt $switchOffsets[1]) -Message 'Orden de verificaciones Flyway inválido.'
    Assert-True -Condition ($controlOffsets[0] -lt $switchOffsets[0] -and
        $controlOffsets[1] -gt $switchOffsets[0] -and $controlOffsets[1] -lt $switchOffsets[1] -and
        $controlOffsets[2] -gt $switchOffsets[1]) -Message 'Orden de verificaciones control-plane inválido.'
    Assert-True -Condition ($source.Contains('Switch-BackendImage -ImageId $targetImageId') -and
        $source.Contains('Switch-BackendImage -ImageId $previousImageId')) `
        -Message 'Objetivo o recuperación no usan la identidad inmutable resuelta.'
    Assert-True -Condition ($source.Contains("`$ProjectName -ieq 'gestudio-remote-demo'") -and
        $source.IndexOf("`$ProjectName -ieq 'gestudio-remote-demo'", [StringComparison]::Ordinal) -lt
        $source.IndexOf("Invoke-Native -FilePath 'docker'", [StringComparison]::Ordinal)) `
        -Message 'El runtime no rechaza el demo protegido antes de Docker.'

    $dockerfileSource = Get-Content -LiteralPath $dockerfile -Raw
    Assert-True -Condition ($dockerfileSource.Contains('/workspace/build-metadata/flyway-resources.sha256') -and
        $dockerfileSource.Contains('find "$migration_root" -maxdepth 1 -type f') -and
        $dockerfileSource.Contains('sha256sum "$migration_root/$resource_name"')) `
        -Message 'Dockerfile no publica nombres y SHA-256 de todos los recursos Flyway.'

    $drillTokens = $null
    $drillParseErrors = $null
    [Management.Automation.Language.Parser]::ParseFile(
        $drillScript, [ref]$drillTokens, [ref]$drillParseErrors) | Out-Null
    Assert-Equal -Actual $drillParseErrors.Count -Expected 0 -Message 'verify-application-rollback.ps1 no parsea'
    $drillSource = Get-Content -LiteralPath $drillScript -Raw
    foreach ($guard in @(
        "GetEnvironmentVariable('DOCKER_HOST', 'Process')",
        "(?i)(prod|production|stage|staging|remote|demo)",
        "unix:///var/run/docker.sock",
        "`$osType.Trim() -cne 'linux'",
        "Get-DockerProjectSnapshot -ProjectName 'gestudio-remote-demo'",
        'Test-DockerProjectSnapshotInvariant')) {
        Assert-True -Condition $drillSource.Contains($guard) `
            -Message "El drill no contiene la guarda obligatoria: $guard"
    }
    Assert-True -Condition ($drillSource.IndexOf('$dockerContext = Assert-LocalDockerTarget', [StringComparison]::Ordinal) -lt
        $drillSource.IndexOf('New-Item -ItemType Directory -Path $workRoot', [StringComparison]::Ordinal)) `
        -Message 'El drill muta el filesystem antes de validar Docker local Linux.'

    $workflowSource = Get-Content -LiteralPath $workflow -Raw
    Assert-True -Condition ($workflowSource.Contains('scripts/ops/test-rollback-backend-contract.ps1') -and
        $workflowSource.Contains('Execute rollback static contract')) `
        -Message 'CI no ejecuta el contrato fail-closed de rollback.'
    Pass 'Contrato AST, metadata exacta, identidades inmutables y preflight Docker'
}

try {
    $resolvedDocker = Get-Command -Name docker -ErrorAction Stop
    Assert-Equal -Actual $resolvedDocker.CommandType -Expected 'Function' `
        -Message 'La fixture no logró aislar el comando docker real'
    Assert-True -Condition (Test-Path -LiteralPath $rollbackScript -PathType Leaf) `
        -Message "No existe $rollbackScript"
    Assert-True -Condition (Test-Path -LiteralPath $composeFile -PathType Leaf) `
        -Message "No existe $composeFile"
    New-Item -ItemType Directory -Path $temporaryRoot | Out-Null

    $migrationFixture = Get-MigrationFixture
    $completeHistory = @($migrationFixture.Entries | ForEach-Object {
        "$($_.Version)|SQL|$($_.Script)"
    })
    Assert-True -Condition ($completeHistory[-1] -like "$($migrationFixture.LatestVersion)|*") `
        -Message 'La fixture failed debe conservar el mismo máximo Flyway.'
    $gapVersion = $migrationFixture.LatestVersion - 1
    $gapHistory = @($migrationFixture.Entries | Where-Object { $_.Version -ne $gapVersion } |
        ForEach-Object { "$($_.Version)|SQL|$($_.Script)" })
    Assert-True -Condition ($gapHistory[-1] -like "$($migrationFixture.LatestVersion)|*") `
        -Message 'La fixture de hueco debe conservar el mismo máximo Flyway.'

    $driftResources = @($migrationFixture.Resources | ForEach-Object {
        [pscustomobject]@{ Script = $_.Script; Sha256 = $_.Sha256 }
    })
    $driftResources[0].Sha256 = if ($driftResources[0].Sha256 -ceq ([string]::new('0', 64))) {
        [string]::new('f', 64)
    } else { [string]::new('0', 64) }
    $resourceHole = @($migrationFixture.Resources | Where-Object {
        $_.Script -cne $migrationFixture.Entries[1].Script
    })
    $repeatableExtra = @($migrationFixture.Resources) + @([pscustomobject]@{
        Script = 'R__unexpected_repeatable.sql'
        Sha256 = [string]::new('c', 64)
    })
    $callbackExtra = @($migrationFixture.Resources) + @([pscustomobject]@{
        Script = 'beforeMigrate.sql'
        Sha256 = [string]::new('d', 64)
    })

    Assert-StaticContract
    Assert-ProtectedProjectRejected
    Invoke-NegativeFixture -Name 'baseline-ausente' -MissingTargetBaseline $true `
        -HistoryRows $completeHistory -FailedCount 0 `
        -TargetResourceManifest $migrationFixture.ResourceManifest `
        -ExpectedMessage 'flyway-baseline-script' -MigrationFixture $migrationFixture
    Invoke-NegativeFixture -Name 'contenido-flyway-con-drift' -MissingTargetBaseline $false `
        -HistoryRows $completeHistory -FailedCount 0 `
        -TargetResourceManifest (New-ResourceManifest -Resources $driftResources) `
        -ExpectedMessage 'no coincide exactamente' -MigrationFixture $migrationFixture
    Invoke-NegativeFixture -Name 'manifiesto-flyway-con-hueco' -MissingTargetBaseline $false `
        -HistoryRows $completeHistory -FailedCount 0 `
        -TargetResourceManifest (New-ResourceManifest -Resources $resourceHole) `
        -ExpectedMessage 'no coincide exactamente' -MigrationFixture $migrationFixture
    Invoke-NegativeFixture -Name 'repeatable-flyway-extra' -MissingTargetBaseline $false `
        -HistoryRows $completeHistory -FailedCount 0 `
        -TargetResourceManifest (New-ResourceManifest -Resources $repeatableExtra) `
        -ExpectedMessage 'no coincide exactamente' -MigrationFixture $migrationFixture
    Invoke-NegativeFixture -Name 'callback-flyway-extra' -MissingTargetBaseline $false `
        -HistoryRows $completeHistory -FailedCount 0 `
        -TargetResourceManifest (New-ResourceManifest -Resources $callbackExtra) `
        -ExpectedMessage 'no coincide exactamente' -MigrationFixture $migrationFixture
    Invoke-NegativeFixture -Name 'historial-con-hueco-y-mismo-maximo' -MissingTargetBaseline $false `
        -HistoryRows $gapHistory -FailedCount 0 `
        -TargetResourceManifest $migrationFixture.ResourceManifest `
        -ExpectedMessage 'Historial Flyway inválido' -MigrationFixture $migrationFixture
    Invoke-NegativeFixture -Name 'failed-con-mismo-maximo' -MissingTargetBaseline $false `
        -HistoryRows $completeHistory -FailedCount 1 `
        -TargetResourceManifest $migrationFixture.ResourceManifest `
        -ExpectedMessage 'Historial Flyway inválido' -MigrationFixture $migrationFixture
    Assert-ImmutableSwitch -HistoryRows $completeHistory -MigrationFixture $migrationFixture
}
catch {
    $failures++
    Write-Host "[FAIL] $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    Remove-Item -LiteralPath Function:\docker -ErrorAction SilentlyContinue
    Remove-Variable -Name GestudioRollbackContractDockerCalls -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name GestudioRollbackContractFixture -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name GestudioRollbackContractActiveImageId -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name GestudioRollbackContractCurrentImageId -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name GestudioRollbackContractTargetImageId -Scope Global -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $temporaryRoot) {
        $resolvedTemporaryRoot = [IO.Path]::GetFullPath($temporaryRoot)
        $resolvedSystemTemporary = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if ($resolvedTemporaryRoot.StartsWith($resolvedSystemTemporary, [StringComparison]::OrdinalIgnoreCase) -and
            (Split-Path $resolvedTemporaryRoot -Leaf) -like 'gestudio-rollback-contract-*') {
            Remove-Item -LiteralPath $resolvedTemporaryRoot -Recurse -Force
        }
        else {
            $failures++
            Write-Host "[FAIL] Se rechazó cleanup fuera del temporal esperado: $resolvedTemporaryRoot" -ForegroundColor Red
        }
    }
}

Write-Host "Pasos aprobados: $passes"
Write-Host "Fallos: $failures"
Write-Host "Resultado global: $(if ($failures -eq 0) { 'PASS' } else { 'FAIL' })"
if ($failures -ne 0) { exit 1 }
