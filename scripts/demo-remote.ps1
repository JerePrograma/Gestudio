param(
    [Parameter(Mandatory)]
    [ValidateSet("Start", "Status", "Stop", "Reset")]
    [string] $Action,
    [string] $EnvFile = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Net.Http

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$composeFile = Join-Path $repoRoot "docker-compose.yml"
$remoteComposeFile = Join-Path $repoRoot "docker-compose.remote-demo.yml"
$seedPath = Join-Path $PSScriptRoot "gestudio_demo_seed_full.sql"
$seedContractPath = Join-Path $PSScriptRoot "remote-demo/validate-demo-seed.sql"
$backendRoot = Join-Path $repoRoot "backend"
$migrationRoot = Join-Path $backendRoot "src/main/resources/db/migration"
$project = "gestudio-remote-demo"
$envPath = if ([string]::IsNullOrWhiteSpace($EnvFile)) {
    Join-Path $repoRoot ".env.remote-demo"
}
else {
    [IO.Path]::GetFullPath($EnvFile)
}

$isWindowsHost = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
$deadline = (Get-Date).AddMinutes(45)
$environmentValues = @{}
$secretValues = [Collections.Generic.List[string]]::new()
$securePasswords = @{}
$demoPasswords = @{}
$demoHashes = @{}
$originalEnvironment = @{}
$tempRoot = $null
$javaExe = $null
$javacExe = $null
$bcryptClasspath = $null
$stackAttempted = $false
$exitCode = 0
$caughtMessage = $null

foreach ($module in @(
    "remote-demo/common.ps1",
    "remote-demo/environment.ps1",
    "remote-demo/database.ps1",
    "remote-demo/credentials.ps1",
    "remote-demo/seed.ps1",
    "remote-demo/lifecycle.ps1"
)) {
    $modulePath = Join-Path $PSScriptRoot $module
    if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
        throw "Falta módulo remoto requerido: $modulePath"
    }
    . $modulePath
}

try {
    switch ($Action) {
        "Start" { Invoke-Start }
        "Status" { if (-not (Invoke-Status)) { $exitCode = 1 } }
        "Stop" { Invoke-Stop }
        "Reset" { Invoke-Reset }
    }
}
catch {
    $exitCode = 1
    $caughtMessage = Redact $_.Exception.Message
    Write-Host "[FAIL] $caughtMessage" -ForegroundColor Red
    if ($stackAttempted) { Show-Diagnostics }
}
finally {
    foreach ($secure in @($securePasswords.Values)) {
        try { $secure.Dispose() } catch { }
    }
    foreach ($key in @($demoPasswords.Keys)) { $demoPasswords[$key] = $null }
    foreach ($key in @($demoHashes.Keys)) { $demoHashes[$key] = $null }
    $securePasswords.Clear()
    $demoPasswords.Clear()
    $demoHashes.Clear()
    $secretValues.Clear()
    $javaExe = $null
    $javacExe = $null
    $bcryptClasspath = $null
    try { Restore-Environment } catch { if ($exitCode -eq 0) { $exitCode = 1 } }
    if (-not [string]::IsNullOrWhiteSpace($tempRoot) -and (Test-Path -LiteralPath $tempRoot)) {
        try { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
        catch { if ($exitCode -eq 0) { $exitCode = 1 } }
    }
}

if ($exitCode -ne 0) {
    if (-not [string]::IsNullOrWhiteSpace($caughtMessage)) { [Console]::Error.WriteLine($caughtMessage) }
    exit $exitCode
}
exit 0
