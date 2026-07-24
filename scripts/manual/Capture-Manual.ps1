[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://localhost:18081',
    [Parameter(Mandatory)]
    [string]$OutputDirectory,
    [switch]$Headed,
    [string]$ResumeFrom
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Manual.Common.ps1')

Assert-ManualDemoCredentials

$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$screenshotDirectory = Join-Path $OutputDirectory 'screenshots'
$flowPath = Join-Path $PSScriptRoot 'flows\capture-manual.cjs'

if (-not (Test-Path -LiteralPath $flowPath -PathType Leaf)) {
    throw 'No existe flows/capture-manual.cjs.'
}

New-Item -ItemType Directory -Force -Path $screenshotDirectory | Out-Null

if ([string]::IsNullOrWhiteSpace($ResumeFrom)) {
    Get-ChildItem -LiteralPath $screenshotDirectory -Filter '*.png' -File -ErrorAction SilentlyContinue |
        Remove-Item -Force
}
else {
    if ([IO.Path]::GetFileName($ResumeFrom) -ne $ResumeFrom -or
        $ResumeFrom -notmatch '^(?<order>[0-9]{2})-[a-z0-9-]+\.png$') {
        throw "Nombre de reanudación inválido: $ResumeFrom"
    }

    $resumeOrder = [int]$Matches.order

    Get-ChildItem -LiteralPath $screenshotDirectory -Filter '*.png' -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -match '^(?<order>[0-9]{2})-' -and [int]$Matches.order -ge $resumeOrder
        } |
        Remove-Item -Force

    Write-Host "Reanudando capturas desde $ResumeFrom; se conservan las capturas anteriores."
}

$previousEnvironment = @{
    MANUAL_BASE_URL = [Environment]::GetEnvironmentVariable('MANUAL_BASE_URL', 'Process')
    MANUAL_SCREENSHOT_DIRECTORY = [Environment]::GetEnvironmentVariable('MANUAL_SCREENSHOT_DIRECTORY', 'Process')
    MANUAL_HEADED = [Environment]::GetEnvironmentVariable('MANUAL_HEADED', 'Process')
    MANUAL_RESUME_FROM = [Environment]::GetEnvironmentVariable('MANUAL_RESUME_FROM', 'Process')
}

try {
    [Environment]::SetEnvironmentVariable('MANUAL_BASE_URL', $BaseUrl, 'Process')
    [Environment]::SetEnvironmentVariable('MANUAL_SCREENSHOT_DIRECTORY', $screenshotDirectory, 'Process')
    [Environment]::SetEnvironmentVariable('MANUAL_HEADED', $(if ($Headed) { '1' } else { '0' }), 'Process')
    [Environment]::SetEnvironmentVariable('MANUAL_RESUME_FROM', $ResumeFrom, 'Process')

    Write-Host 'Comprobando Chromium administrado por Playwright 1.54.1...'
    Invoke-ManualNativeCommand `
        -FilePath 'npx' `
        -Arguments @('--yes', 'playwright@1.54.1', 'install', 'chromium') | Out-Null

    Write-Host 'Ejecutando recorridos reales sin traces ni vídeos...'
    Invoke-ManualNativeCommand `
        -FilePath 'npx' `
        -Arguments @('--yes', '-p', 'playwright@1.54.1', 'node', $flowPath) | Out-Null
}
finally {
    foreach ($entry in $previousEnvironment.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process')
    }
}

$screenshots = @(Get-ChildItem -LiteralPath $screenshotDirectory -Filter '*.png' -File)
if ($screenshots.Count -lt 20) {
    throw "La captura produjo sólo $($screenshots.Count) archivos; se esperaban al menos 20."
}

Write-Host "Capturas generadas: $($screenshots.Count)."
