[CmdletBinding()]
param(
    [string]$BackendUrl = 'http://localhost:18080'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Manual.Common.ps1')

$repoRoot = Get-ManualRepositoryRoot
$demoScript = Join-Path $repoRoot 'scripts\demo-local.ps1'

Assert-ManualDemoCredentials

$status = Invoke-ManualDemoScript `
    -Path $demoScript `
    -Action Status `
    -AllowFailure

if ($status.ExitCode -ne 0) {
    throw 'El dataset demo persistente no superó scripts/demo-local.ps1 -Action Status. No se ejecutó Reset ni se borraron datos.'
}

try {
    $readiness = Invoke-RestMethod `
        -Uri "$BackendUrl/actuator/health/readiness" `
        -TimeoutSec 8
}
catch {
    throw "El backend demo no respondió en readiness: $($_.Exception.Message)"
}

if ($readiness.status -ne 'UP') {
    throw "El backend demo no está listo. Estado: $($readiness.status)."
}

Write-Host 'Dataset demo validado mediante el contrato persistente existente.'
Write-Host 'No se crearon pagos, egresos, alumnos ni inscripciones adicionales.'
