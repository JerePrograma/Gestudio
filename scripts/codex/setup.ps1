$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))

function Assert-Command {
    param([Parameter(Mandatory)][string] $Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Falta '$Name' en PATH. Instalalo y volvé a ejecutar este script."
    }
}

function Invoke-Native {
    param(
        [Parameter(Mandatory)][string] $FilePath,
        [Parameter(Mandatory)][string[]] $Arguments
    )

    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Falló '$FilePath $($Arguments -join ' ')' con código $LASTEXITCODE."
    }
}

foreach ($command in "git", "node", "npm", "docker") {
    Assert-Command $command
}

if ([string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
    throw "JAVA_HOME no está definido. Gestudio requiere un JDK 21."
}

$java = Join-Path $env:JAVA_HOME "bin\java.exe"
$javac = Join-Path $env:JAVA_HOME "bin\javac.exe"
if (-not (Test-Path -LiteralPath $java) -or -not (Test-Path -LiteralPath $javac)) {
    throw "JAVA_HOME no apunta a un JDK completo: $env:JAVA_HOME"
}

$javacVersion = (& $javac -version | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $javacVersion -notmatch '^javac 21(?:\.|$)') {
    throw "Gestudio requiere JDK 21. Detectado: $javacVersion"
}

$wrapper = Join-Path $repoRoot "backend\mvnw.cmd"
if (-not (Test-Path -LiteralPath $wrapper)) {
    throw "Falta backend\mvnw.cmd. El Maven Wrapper debe estar versionado."
}

Write-Host "Git: $(& git --version)"
Write-Host "JDK: $javacVersion"
Write-Host "Node: $(& node --version)"
Write-Host "npm: $(& npm --version)"
Invoke-Native docker @("compose", "version")

Push-Location (Join-Path $repoRoot "backend")
try {
    Invoke-Native ".\mvnw.cmd" @("-version")
    Invoke-Native ".\mvnw.cmd" @("-B", "-ntp", "dependency:go-offline")
}
finally {
    Pop-Location
}

Push-Location (Join-Path $repoRoot "frontend")
try {
    if (-not (Test-Path -LiteralPath ".\package-lock.json")) {
        throw "Falta frontend\package-lock.json. No se usa npm install como fallback."
    }
    Invoke-Native npm @("ci")
}
finally {
    Pop-Location
}

Write-Host "Entorno preparado. No se iniciaron servicios ni se ejecutó la validación completa."
