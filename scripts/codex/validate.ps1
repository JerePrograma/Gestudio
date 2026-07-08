param(
    [ValidateSet("All", "Backend", "Frontend")]
    [string] $Scope = "All"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$results = [ordered]@{}
$firstExitCode = 0

function Invoke-Step {
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][scriptblock] $Action
    )

    $code = 0
    try {
        $global:LASTEXITCODE = 0
        & $Action
        if ($LASTEXITCODE -ne 0) {
            $code = $LASTEXITCODE
        }
    }
    catch {
        $code = if ($LASTEXITCODE -gt 0) { $LASTEXITCODE } else { 1 }
        Write-Host "[$Name] $($_.Exception.Message)" -ForegroundColor Red
    }

    if ($code -eq 0) {
        $results[$Name] = "PASS"
    }
    else {
        $results[$Name] = "FAIL ($code)"
        if ($script:firstExitCode -eq 0) {
            $script:firstExitCode = $code
        }
    }
}

if ($Scope -in "All", "Backend") {
    if ([string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
        throw "JAVA_HOME no está definido."
    }
    $javac = Join-Path $env:JAVA_HOME "bin\javac.exe"
    if (-not (Test-Path -LiteralPath $javac)) {
        throw "JAVA_HOME no contiene bin\javac.exe: $env:JAVA_HOME"
    }
    $javacVersion = (& $javac -version | Out-String)
    if ($javacVersion -notmatch '^javac 21(?:\.|$)') {
        throw "La validación requiere JDK 21."
    }

    $env:GESTUDIO_HOME = $repoRoot
    Invoke-Step "backend clean verify" {
        Push-Location (Join-Path $repoRoot "backend")
        try { & ".\mvnw.cmd" clean verify }
        finally { Pop-Location }
    }
}

if ($Scope -in "All", "Frontend") {
    Invoke-Step "frontend lint" {
        Push-Location (Join-Path $repoRoot "frontend")
        try { & npm run lint }
        finally { Pop-Location }
    }

    $package = Get-Content -Raw (Join-Path $repoRoot "frontend\package.json") | ConvertFrom-Json
    if ($package.scripts.PSObject.Properties.Name -contains "test") {
        Invoke-Step "frontend test" {
            Push-Location (Join-Path $repoRoot "frontend")
            try { & npm test }
            finally { Pop-Location }
        }
    }
    else {
        $results["frontend test"] = "SKIP (script inexistente)"
    }

    Invoke-Step "frontend build" {
        Push-Location (Join-Path $repoRoot "frontend")
        try { & npm run build }
        finally { Pop-Location }
    }
}

if ($Scope -eq "All") {
    Invoke-Step "docker compose config" {
        Push-Location $repoRoot
        try { & docker compose config --quiet }
        finally { Pop-Location }
    }
}

Write-Host ""
Write-Host "Resumen de validación ($Scope):"
foreach ($result in $results.GetEnumerator()) {
    Write-Host ("- {0}: {1}" -f $result.Key, $result.Value)
}

exit $firstExitCode
