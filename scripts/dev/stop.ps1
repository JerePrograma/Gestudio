$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
Push-Location $repoRoot
try {
    & docker compose stop
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
