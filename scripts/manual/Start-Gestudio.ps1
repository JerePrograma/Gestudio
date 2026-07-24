[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://localhost:18081',
    [string]$BackendUrl = 'http://localhost:18080',
    [switch]$StatusOnly,
    [ValidateRange(1, 30)]
    [int]$TimeoutMinutes = 8
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Manual.Common.ps1')

$repoRoot = Get-ManualRepositoryRoot
$demoScript = Join-Path $repoRoot 'scripts\demo-local.ps1'

if (-not (Test-Path -LiteralPath $demoScript -PathType Leaf)) {
    throw 'No existe scripts/demo-local.ps1.'
}

Assert-ManualDemoCredentials

$status = Invoke-ManualDemoScript `
    -Path $demoScript `
    -Action Status `
    -AllowFailure

if ($status.ExitCode -eq 0) {
    $startedByGenerator = $false
}
elseif ($StatusOnly) {
    throw 'La demo local no está disponible o no corresponde al checkout actual.'
}
else {
    Write-Host 'La demo no está disponible; se ejecutará el arranque seguro sin Reset.'

    $startResult = Invoke-ManualDemoScript `
        -Path $demoScript `
        -Action Start `
        -AllowFailure

    if ($startResult.ExitCode -ne 0) {
        throw 'No se pudo iniciar la demo local mediante scripts/demo-local.ps1 -Action Start.'
    }

    $startedByGenerator = $true
}

$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
$lastProblem = ''

while ((Get-Date) -lt $deadline) {
    try {
        $readiness = Invoke-RestMethod `
            -Uri "$BackendUrl/actuator/health/readiness" `
            -TimeoutSec 8

        $frontend = Invoke-WebRequest `
            -Uri $BaseUrl `
            -UseBasicParsing `
            -TimeoutSec 8

        if ($readiness.status -eq 'UP' -and $frontend.StatusCode -eq 200) {
            return [pscustomobject]@{
                StartedByGenerator = $startedByGenerator
                FrontendUrl = $BaseUrl
                BackendUrl = $BackendUrl
            }
        }

        $lastProblem = "readiness=$($readiness.status), frontend=$($frontend.StatusCode)"
    }
    catch {
        $lastProblem = $_.Exception.Message
    }

    Start-Sleep -Seconds 2
}

if ($startedByGenerator) {
    Write-Warning 'La demo fue iniciada por este proceso pero no quedó disponible; se intentará detenerla sin borrar volúmenes.'

    Invoke-ManualPowerShellFile `
        -Path $demoScript `
        -Arguments @('-Action', 'Stop') `
        -AllowFailure | Out-Null
}

throw "La demo no quedó disponible dentro del tiempo esperado. Último diagnóstico: $lastProblem"
