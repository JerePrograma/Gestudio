$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
if ([string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
    throw "JAVA_HOME no está definido."
}
$javac = Join-Path $env:JAVA_HOME "bin\javac.exe"
$javacVersion = if (Test-Path -LiteralPath $javac) { & $javac -version | Out-String } else { "" }
if (-not (Test-Path -LiteralPath $javac) -or $javacVersion -notmatch '^javac 21(?:\.|$)') {
    throw "Le Dance requiere un JDK 21 válido en JAVA_HOME."
}

$env:SPRING_PROFILES_ACTIVE = if ([string]::IsNullOrWhiteSpace($env:SPRING_PROFILES_ACTIVE)) {
    "dev"
} else {
    $env:SPRING_PROFILES_ACTIVE
}
if ([string]::IsNullOrWhiteSpace($env:SERVER_PORT) -and -not [string]::IsNullOrWhiteSpace($env:BACKEND_PORT)) {
    $env:SERVER_PORT = $env:BACKEND_PORT
}
$env:GESTUDIO_HOME = $repoRoot
Push-Location (Join-Path $repoRoot "backend")
try {
    & ".\mvnw.cmd" spring-boot:run
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
