$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
Push-Location $repoRoot
try {
    & docker compose up -d db
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & docker compose ps db
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
