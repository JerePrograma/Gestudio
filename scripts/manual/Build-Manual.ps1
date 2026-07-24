[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://localhost:18081',
    [string]$BackendUrl = 'http://localhost:18080',
    [string]$OutputDirectory,
    [switch]$SkipApplicationStart,
    [switch]$KeepApplicationRunning,
    [switch]$Headed
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Manual.Common.ps1')

$repoRoot = Get-ManualRepositoryRoot

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
$completed = $false
$locationPushed = $false

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

try {
    Push-Location -LiteralPath $repoRoot
    $locationPushed = $true

    Set-MissingManualDemoCredentials
    Assert-ManualDemoCredentials
    New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

    Invoke-ManualStage -Name '1/7 Preflight' -Action {
        & (Join-Path $PSScriptRoot 'Preflight-Manual.ps1') `
            -BaseUrl $BaseUrl `
            -BackendUrl $BackendUrl
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

    Invoke-ManualStage -Name '3/7 Demo local' -Action {
        if ($SkipApplicationStart) {
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

    Invoke-ManualStage -Name '4/7 Dataset demo' -Action {
        & (Join-Path $PSScriptRoot 'Seed-ManualDemo.ps1') `
            -BackendUrl $BackendUrl
    }

    Invoke-ManualStage -Name '5/7 Capturas reales' -Action {
        & (Join-Path $PSScriptRoot 'Capture-Manual.ps1') `
            -BaseUrl $BaseUrl `
            -OutputDirectory $OutputDirectory `
            -Headed:$Headed
    }

    Invoke-ManualStage -Name '6/7 HTML y PDF' -Action {
        & (Join-Path $PSScriptRoot 'Render-Manual.ps1') `
            -BaseUrl $BaseUrl `
            -BackendUrl $BackendUrl `
            -OutputDirectory $OutputDirectory `
            -ApplicationStartedByGenerator:$script:applicationStartedByGenerator
    }

    Clear-ManualPlaywrightRuntime

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
    if ($script:applicationStartedByGenerator -and -not $KeepApplicationRunning) {
        Write-Host ''
        Write-Host 'Deteniendo únicamente la demo iniciada por este generador...'

        $stopResult = @(
            Invoke-ManualPowerShellFile `
                -Path (Join-Path $repoRoot 'scripts\demo-local.ps1') `
                -Arguments @('-Action', 'Stop') `
                -AllowFailure
        ) | Select-Object -Last 1

        if ($null -eq $stopResult -or
            -not ($stopResult.PSObject.Properties.Name -contains 'ExitCode') -or
            $stopResult.ExitCode -ne 0) {
            Write-Warning 'No se pudo detener la demo iniciada por el generador. Revise scripts/demo-local.ps1 -Action Status.'
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
        Write-Host 'La generación no se completó. No se afirma que el PDF sea válido.' -ForegroundColor Yellow
    }
}
