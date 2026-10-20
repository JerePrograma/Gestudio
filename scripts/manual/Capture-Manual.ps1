[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://localhost:18081',
    [Parameter(Mandatory)]
    [string]$OutputDirectory,
    [switch]$Headed,
    [string]$ResumeFrom,
    [string]$CredentialManifestPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Manual.Common.ps1')

if (-not [string]::IsNullOrWhiteSpace($CredentialManifestPath)) {
    if (-not (Test-ManualLocalUri -Uri ([uri]$BaseUrl))) {
        throw 'Las credenciales privadas del fixture sólo pueden utilizarse en una URL local.'
    }
    $CredentialManifestPath = [IO.Path]::GetFullPath($CredentialManifestPath)
    if (-not (Test-Path -LiteralPath $CredentialManifestPath -PathType Leaf)) {
        throw 'No existe el manifiesto privado del fixture multiorganización.'
    }
}

$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$screenshotDirectory = Join-Path $OutputDirectory 'screenshots'
$flowPath = Join-Path $PSScriptRoot 'flows\capture-manual.cjs'
$accountsPath = Join-Path (Get-ManualRepositoryRoot) 'docs\manual-usuarios\data\demo-accounts.json'

foreach ($requiredPath in @($flowPath, $accountsPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "No existe el archivo requerido: $requiredPath"
    }
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

    Write-Host "Reanudando capturas desde $ResumeFrom según el orden real del recorrido; se conservan las capturas anteriores."
}

$previousEnvironment = @{
    MANUAL_BASE_URL = [Environment]::GetEnvironmentVariable('MANUAL_BASE_URL', 'Process')
    MANUAL_SCREENSHOT_DIRECTORY = [Environment]::GetEnvironmentVariable('MANUAL_SCREENSHOT_DIRECTORY', 'Process')
    MANUAL_HEADED = [Environment]::GetEnvironmentVariable('MANUAL_HEADED', 'Process')
    MANUAL_RESUME_FROM = [Environment]::GetEnvironmentVariable('MANUAL_RESUME_FROM', 'Process')
    MANUAL_ACCOUNTS_PATH = [Environment]::GetEnvironmentVariable('MANUAL_ACCOUNTS_PATH', 'Process')
    MANUAL_CREDENTIAL_MANIFEST_PATH = [Environment]::GetEnvironmentVariable('MANUAL_CREDENTIAL_MANIFEST_PATH', 'Process')
    NODE_PATH = [Environment]::GetEnvironmentVariable('NODE_PATH', 'Process')
}

try {
    [Environment]::SetEnvironmentVariable('MANUAL_BASE_URL', $BaseUrl, 'Process')
    [Environment]::SetEnvironmentVariable('MANUAL_SCREENSHOT_DIRECTORY', $screenshotDirectory, 'Process')
    [Environment]::SetEnvironmentVariable('MANUAL_HEADED', $(if ($Headed) { '1' } else { '0' }), 'Process')
    [Environment]::SetEnvironmentVariable('MANUAL_RESUME_FROM', $ResumeFrom, 'Process')
    [Environment]::SetEnvironmentVariable('MANUAL_ACCOUNTS_PATH', $accountsPath, 'Process')
    [Environment]::SetEnvironmentVariable('MANUAL_CREDENTIAL_MANIFEST_PATH', $CredentialManifestPath, 'Process')
    $playwrightRuntime = Resolve-ManualPlaywrightRuntime
    Set-ManualNodePathForRuntime `
        -NodeModules $playwrightRuntime.NodeModules `
        -PreviousNodePath $previousEnvironment.NODE_PATH

    Write-Host "Comprobando Chromium administrado por Playwright $($playwrightRuntime.Version)..."
    Invoke-ManualNativeCommand `
        -FilePath 'node' `
        -Arguments @($playwrightRuntime.CliPath, 'install', 'chromium') | Out-Null

    Write-Host 'Ejecutando recorridos reales sin traces ni vídeos...'
    $captureResult = Invoke-ManualNativeCommand `
        -FilePath 'node' `
        -Arguments @($flowPath) -CaptureOutput
    $summaryLines = @($captureResult.Output -split '\r?\n' |
        Where-Object { $_.StartsWith('MANUAL_CAPTURE_SUMMARY=') })
    if ($summaryLines.Count -ne 1) {
        throw 'El recorrido no produjo un resumen verificable de los perfiles capturados.'
    }
    $captureSummary = $summaryLines[0].Substring('MANUAL_CAPTURE_SUMMARY='.Length) | ConvertFrom-Json
}
finally {
    foreach ($entry in $previousEnvironment.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process')
    }
}

$screenshots = @(Get-ChildItem -LiteralPath $screenshotDirectory -Filter '*.png' -File)
if ($screenshots.Count -ne 36) {
    throw "La captura produjo $($screenshots.Count) archivos; se esperaban exactamente 36."
}

Write-Host "Capturas generadas: $($screenshots.Count)."
return $captureSummary
