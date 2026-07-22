$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$failed = $false

function Get-ConfiguredPort {
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][int] $Default
    )

    $raw = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($raw)) { return $Default }

    $port = 0
    if (-not [int]::TryParse($raw, [ref] $port) -or $port -lt 1 -or $port -gt 65535) {
        Write-Host "${Name}: INVALID ($raw)"
        $script:failed = $true
        return $Default
    }
    return $port
}

function Test-PortAvailable {
    param([Parameter(Mandatory)][int] $Port)

    $probe = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Any, $Port)
    try {
        $probe.Start()
        return $true
    }
    catch [Net.Sockets.SocketException] {
        return $false
    }
    finally {
        $probe.Stop()
    }
}

function Show-CommandVersion {
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][scriptblock] $Action
    )

    try {
        $previousErrorAction = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        $output = (& $Action 2>&1 | Out-String).Trim()
        $ErrorActionPreference = $previousErrorAction
        Write-Host "${Name}: $output"
        if ($LASTEXITCODE -ne 0) { $script:failed = $true }
    }
    catch {
        Write-Host "${Name}: ERROR - $($_.Exception.Message)"
        $script:failed = $true
    }
}

Push-Location $repoRoot
try {
    Write-Host "Repositorio: $repoRoot"
    Write-Host "Rama: $(& git branch --show-current)"
    Write-Host "Commit: $(& git rev-parse HEAD)"
    & git status --short --branch

    Show-CommandVersion "Git" { & git --version }

    if ([string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
        Write-Host "JAVA_HOME: MISSING"
        $failed = $true
    }
    else {
        Write-Host "JAVA_HOME: $env:JAVA_HOME"
        $javac = Join-Path $env:JAVA_HOME "bin\javac.exe"
        if (Test-Path -LiteralPath $javac) {
            Show-CommandVersion "JDK" { & $javac -version }
            $javacVersion = & $javac -version | Out-String
            if ($javacVersion -notmatch '^javac 21(?:\.|$)') {
                Write-Host "Java requerido: 21; detectado otro major."
                $failed = $true
            }
        }
        else {
            Write-Host "JDK: MISSING dentro de JAVA_HOME"
            $failed = $true
        }
    }

    if (Test-Path -LiteralPath ".\backend\mvnw.cmd") {
        Show-CommandVersion "Maven Wrapper" { & ".\backend\mvnw.cmd" -version }
    }
    else {
        Write-Host "Maven Wrapper: MISSING"
        $failed = $true
    }

    Show-CommandVersion "Node" { & node --version }
    Show-CommandVersion "npm" { & npm --version }
    Show-CommandVersion "Docker CLI" { & docker --version }
    Show-CommandVersion "Docker Compose" { & docker compose version }

    Write-Host "Variables críticas (sólo presencia):"
    foreach ($name in @(
        "SPRING_PROFILES_ACTIVE", "SPRING_DATASOURCE_URL",
        "SPRING_DATASOURCE_USERNAME", "SPRING_DATASOURCE_PASSWORD",
        "JWT_SECRET", "APP_TIME_ZONE", "APP_RECEIPTS_PATH",
        "APP_CORS_ALLOWED_ORIGINS", "VITE_API_BASE_URL"
    )) {
        $present = -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))
        Write-Host ("- {0}: {1}" -f $name, $(if ($present) { "PRESENT" } else { "MISSING" }))
    }

    Write-Host "Puertos:"
    $ports = [ordered]@{
        POSTGRES_PORT = Get-ConfiguredPort "POSTGRES_PORT" 5432
        BACKEND_PORT = Get-ConfiguredPort "BACKEND_PORT" 8080
        FRONTEND_PORT = Get-ConfiguredPort "FRONTEND_PORT" 8081
    }
    foreach ($entry in $ports.GetEnumerator()) {
        $port = $entry.Value
        if (Test-PortAvailable -Port $port) {
            Write-Host "- $($entry.Key)=${port}: AVAILABLE"
        }
        else {
            Write-Host "- $($entry.Key)=${port}: LISTENING"
        }
    }

    & docker info --format "Docker Engine: {{.ServerVersion}} ({{.OSType}}/{{.Architecture}})" 2>$null
    if ($LASTEXITCODE -eq 0) {
        & docker compose ps
        if ($LASTEXITCODE -ne 0) { $failed = $true }
    }
    else {
        Write-Host "Docker Engine: UNAVAILABLE"
        $failed = $true
    }
}
finally {
    Pop-Location
}

if ($failed) { exit 1 }
