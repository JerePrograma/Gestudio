[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://localhost:18081',
    [string]$BackendUrl = 'http://localhost:18080',
    [string]$OutputDirectory,
    [switch]$SkipApplicationStart,
    [switch]$KeepApplicationRunning,
    [switch]$Headed,
    [switch]$PublicDemo
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Manual.Common.ps1')

$repoRoot = Get-ManualRepositoryRoot

if ($PublicDemo) {
    $BaseUrl = 'https://gestudio-demo-jere-287b8c90.pages.dev/'
    $BackendUrl = 'https://gestudio-demo-jere-287b8c90.pages.dev/api'
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $repoRoot 'artifacts\manual'
}
else {
    $OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
}

$requiredSources = @(
    'Manual.Common.ps1'
    'Preflight-Manual.ps1'
    'Start-Gestudio.ps1'
    'Seed-ManualDemo.ps1'
    'Capture-Manual.ps1'
    'Render-Manual.ps1'
    'Validate-Manual.ps1'
    'flows\capture-manual.cjs'
    'flows\manual-accounts.cjs'
    'flows\render-manual.cjs'
)

$missingSources = @(
    $requiredSources | Where-Object {
        -not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $_) -PathType Leaf)
    }
)

if ($missingSources.Count -gt 0) {
    throw "Faltan archivos auxiliares del generador: $($missingSources -join ', ')."
}

$requiredDocumentation = @(
    'docs\manual-usuarios\manifest.json'
    'docs\manual-usuarios\templates\manual.html'
    'docs\manual-usuarios\templates\manual.css'
    'docs\manual-usuarios\data\demo-accounts.json'
)

$missingDocumentation = @(
    $requiredDocumentation | Where-Object {
        -not (Test-Path -LiteralPath (Join-Path $repoRoot $_) -PathType Leaf)
    }
)

if ($missingDocumentation.Count -gt 0) {
    throw "Faltan fuentes del manual: $($missingDocumentation -join ', ')."
}

$credentialEnvironmentBefore = [ordered]@{}
foreach ($variableName in $script:ManualDemoCredentialVariables.Values) {
    $credentialEnvironmentBefore[$variableName] = [Environment]::GetEnvironmentVariable($variableName, 'Process')
}

$script:applicationStartedByGenerator = $false
$script:nodePathBefore = [Environment]::GetEnvironmentVariable('NODE_PATH', 'Process')
$script:playwrightRuntimePrepared = $false
$playwrightRuntimeDirectory = Join-Path $OutputDirectory '.playwright-runtime'
$playwrightNodeModules = Join-Path $playwrightRuntimeDirectory 'node_modules'
$incompleteMarkerPath = Join-Path $OutputDirectory '.last-build-incomplete'
$completed = $false
$locationPushed = $false
$demoStageName = if ($PublicDemo) { '3/7 Demo pública' } else { '3/7 Demo local' }
$datasetStageName = if ($PublicDemo) { '4/7 Fixture multiorganización' } else { '4/7 Dataset demo' }

function Invoke-ManualStage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [scriptblock]$Action
    )

    Write-Host ''
    Write-Host "=== $Name ===" -ForegroundColor Cyan

    try {
        & $Action
        Write-Host "[OK] $Name" -ForegroundColor Green
    }
    catch {
        throw "$Name falló: $($_.Exception.Message)"
    }
}

function Clear-ManualPlaywrightRuntime {
    [CmdletBinding()]
    param()

    try {
        if (Test-Path -LiteralPath $playwrightRuntimeDirectory) {
            Remove-Item -LiteralPath $playwrightRuntimeDirectory -Recurse -Force
        }
    }
    finally {
        [Environment]::SetEnvironmentVariable('NODE_PATH', $script:nodePathBefore, 'Process')
        $script:playwrightRuntimePrepared = $false
    }
}

function Write-IncompleteManualMarker {
    [CmdletBinding()]
    param()

    New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
    $state = [ordered]@{
        status = 'INCOMPLETE'
        recordedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
        sourceCommit = (Invoke-ManualNativeCommand `
            -FilePath 'git' `
            -Arguments @('-C', $repoRoot, 'rev-parse', 'HEAD') `
            -CaptureOutput).Output.Trim()
    }
    $state | ConvertTo-Json -Depth 3 |
        Set-Content -LiteralPath $incompleteMarkerPath -Encoding UTF8
}

try {
    Push-Location -LiteralPath $repoRoot
    $locationPushed = $true

    New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
    Write-IncompleteManualMarker

    Invoke-ManualStage -Name '1/7 Preflight' -Action {
        & (Join-Path $PSScriptRoot 'Preflight-Manual.ps1') `
            -BaseUrl $BaseUrl `
            -BackendUrl $BackendUrl `
            -AllowNonLocalUrl:$PublicDemo `
            -SkipCredentialCheck:$PublicDemo `
            -BrowserOnly:$PublicDemo
    }

    Invoke-ManualStage -Name '2/7 Runtime Playwright' -Action {
        if (Test-Path -LiteralPath $playwrightRuntimeDirectory) {
            Remove-Item -LiteralPath $playwrightRuntimeDirectory -Recurse -Force
        }

        New-Item -ItemType Directory -Force -Path $playwrightRuntimeDirectory | Out-Null

        Invoke-ManualNativeCommand `
            -FilePath 'npm' `
            -Arguments @(
                'install'
                '--no-audit'
                '--no-fund'
                '--no-save'
                '--package-lock=false'
                '--prefix'
                $playwrightRuntimeDirectory
                'playwright@1.54.1'
            ) | Out-Null

        $playwrightPackagePath = Join-Path $playwrightNodeModules 'playwright\package.json'
        if (-not (Test-Path -LiteralPath $playwrightPackagePath -PathType Leaf)) {
            throw 'npm no instaló el runtime aislado de Playwright 1.54.1.'
        }

        $nodePath = $playwrightNodeModules
        if (-not [string]::IsNullOrWhiteSpace($script:nodePathBefore)) {
            $nodePath += [IO.Path]::PathSeparator + $script:nodePathBefore
        }

        [Environment]::SetEnvironmentVariable('NODE_PATH', $nodePath, 'Process')
        $script:playwrightRuntimePrepared = $true
    }

    Invoke-ManualStage -Name $demoStageName -Action {
        if ($PublicDemo) {
            $frontend = Invoke-WebRequest -Uri $BaseUrl -UseBasicParsing -TimeoutSec 20
            $platform = Invoke-WebRequest -Uri ([uri]::new([uri]$BaseUrl, '/platform/login')) -UseBasicParsing -TimeoutSec 20
            if ($frontend.StatusCode -ne 200 -or $platform.StatusCode -ne 200) {
                throw 'La demo pública no respondió correctamente.'
            }
            Write-Host 'Demo pública disponible; no se inició ningún servicio local.'
        }
        elseif ($SkipApplicationStart) {
            & (Join-Path $PSScriptRoot 'Start-Gestudio.ps1') `
                -BaseUrl $BaseUrl `
                -BackendUrl $BackendUrl `
                -StatusOnly | Out-Null
        }
        else {
            $startResult = & (Join-Path $PSScriptRoot 'Start-Gestudio.ps1') `
                -BaseUrl $BaseUrl `
                -BackendUrl $BackendUrl

            $script:applicationStartedByGenerator = [bool]$startResult.StartedByGenerator
        }
    }

    Invoke-ManualStage -Name $datasetStageName -Action {
        if ($PublicDemo) {
            Write-Host 'Se usará el fixture multiorganización público existente sin crear ni modificar registros.'
        }
        else {
            & (Join-Path $PSScriptRoot 'Seed-ManualDemo.ps1') `
                -BackendUrl $BackendUrl
        }
    }

    Invoke-ManualStage -Name '5/7 Capturas reales' -Action {
        $captureParameters = @{}
        if (-not $PublicDemo) {
            $captureParameters.CredentialManifestPath = Get-ManualLocalCredentialManifestPath
        }
        $script:captureSummary = & (Join-Path $PSScriptRoot 'Capture-Manual.ps1') `
            -BaseUrl $BaseUrl `
            -OutputDirectory $OutputDirectory `
            -Headed:$Headed @captureParameters
    }

    Invoke-ManualStage -Name '6/7 HTML y PDF' -Action {
        & (Join-Path $PSScriptRoot 'Render-Manual.ps1') `
            -BaseUrl $BaseUrl `
            -BackendUrl $BackendUrl `
            -OutputDirectory $OutputDirectory `
            -CaptureSource $script:captureSummary.CaptureSource `
            -GeneralCaptureProfile $script:captureSummary.GeneralCaptureProfile `
            -CapturedAccountCount $script:captureSummary.CapturedAccountCount `
            -ApplicationStartedByGenerator:$script:applicationStartedByGenerator
    }

    Clear-ManualPlaywrightRuntime

    if (Test-Path -LiteralPath $incompleteMarkerPath) {
        Remove-Item -LiteralPath $incompleteMarkerPath -Force
    }

    Invoke-ManualStage -Name '7/7 Validación estructural' -Action {
        & (Join-Path $PSScriptRoot 'Validate-Manual.ps1') `
            -OutputDirectory $OutputDirectory
    }

    $completed = $true

    Write-Host ''
    Write-Host 'Generación completada.' -ForegroundColor Green
    Write-Host "HTML: $(Join-Path $OutputDirectory 'manual.html')"
    Write-Host "PDF:  $(Join-Path $OutputDirectory 'Manual_Gestudio_Usuarios_Nuevos.pdf')"
    Write-Host "Meta: $(Join-Path $OutputDirectory 'metadata.json')"
}
finally {
    if (-not $PublicDemo -and $script:applicationStartedByGenerator -and -not $KeepApplicationRunning) {
        Write-Host ''
        Write-Host 'Deteniendo únicamente la demo iniciada por este generador...'

        $stopResult = @(
            Invoke-ManualDemoScript `
                -Path (Join-Path $repoRoot 'scripts\demo-local-multitenant.ps1') `
                -Action Stop `
                -AllowFailure
        ) | Select-Object -Last 1

        if ($null -eq $stopResult -or
            -not ($stopResult.PSObject.Properties.Name -contains 'ExitCode') -or
            $stopResult.ExitCode -ne 0) {
            Write-Warning 'No se pudo detener la demo iniciada por el generador. Revise scripts/demo-local-multitenant.ps1 -Action Status.'
        }
    }

    if ($script:playwrightRuntimePrepared -or (Test-Path -LiteralPath $playwrightRuntimeDirectory)) {
        try {
            Clear-ManualPlaywrightRuntime
        }
        catch {
            Write-Warning "No se pudo limpiar el runtime temporal de Playwright: $($_.Exception.Message)"
        }
    }

    foreach ($entry in $credentialEnvironmentBefore.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process')
    }

    if ($locationPushed) {
        Pop-Location
    }

    if (-not $completed) {
        try {
            Write-IncompleteManualMarker
        }
        catch {
            Write-Warning "No se pudo registrar el estado incompleto del manual: $($_.Exception.Message)"
        }
        Write-Host 'La generación no se completó. No se afirma que el PDF sea válido.' -ForegroundColor Yellow
    }
}
