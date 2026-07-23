Add-Type -AssemblyName System.Net.Http

function Test-Readiness {
    $port = [int](Get-EnvironmentValue "BACKEND_PORT")
    $handler = [Net.Http.HttpClientHandler]::new()
    $client = [Net.Http.HttpClient]::new($handler, $true)
    $client.Timeout = [TimeSpan]::FromSeconds(20)
    try {
        $response = $client.GetAsync("http://127.0.0.1:$port/actuator/health/readiness").GetAwaiter().GetResult()
        try {
            $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            return [int]$response.StatusCode -eq 200 -and $body -match '"status"\s*:\s*"UP"'
        }
        finally { $response.Dispose() }
    }
    catch { return $false }
    finally { $client.Dispose() }
}

function Set-BuildMetadataEnvironment {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return }
    try {
        $revision = Invoke-Native -FilePath "git" -Arguments @("-C", $script:repoRoot, "rev-parse", "HEAD") -Capture
        $backendTree = Invoke-Native -FilePath "git" -Arguments @("-C", $script:repoRoot, "rev-parse", "HEAD:backend") -Capture
        $composeMaterial = [IO.File]::ReadAllText($script:composeFile) + "`n" + [IO.File]::ReadAllText($script:remoteComposeFile)
        $sha = [Security.Cryptography.SHA256]::Create()
        try {
            $composeSha = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($composeMaterial)))).Replace("-", "").ToLowerInvariant()
        }
        finally { $sha.Dispose() }
        Set-ScopedEnvironmentVariable "VCS_REF" $revision
        Set-ScopedEnvironmentVariable "BACKEND_SOURCE_SHA" $backendTree
        Set-ScopedEnvironmentVariable "COMPOSE_SHA" $composeSha
    }
    catch {
        Write-Host "[INFO] No se pudo completar metadata Git de build: $(Redact $_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Test-BackendImageCurrent {
    $expectedComposeSha = [Environment]::GetEnvironmentVariable("COMPOSE_SHA", "Process")
    $expectedSourceSha = [Environment]::GetEnvironmentVariable("BACKEND_SOURCE_SHA", "Process")
    if ([string]::IsNullOrWhiteSpace($expectedComposeSha) -or [string]::IsNullOrWhiteSpace($expectedSourceSha)) {
        return $false
    }

    $image = Get-EnvironmentValue "BACKEND_IMAGE"
    try {
        $actual = Invoke-Docker -Arguments @(
            "image", "inspect", "--format",
            "{{ index .Config.Labels `"org.gestudio.compose.sha256`" }}|{{ index .Config.Labels `"org.gestudio.source.sha256`" }}",
            $image
        ) -Capture -IgnoreDeadline
    }
    catch {
        return $false
    }

    return $actual.Trim() -eq "$expectedComposeSha|$expectedSourceSha"
}

function Ensure-RemoteDatabase {
    $state = Get-ServiceState "db"
    if ($state.State -eq "running" -and $state.Health -eq "healthy") {
        Sync-DatabasePassword
        Pass "PostgreSQL" "existente, healthy, credencial sincronizada y sin publicación de puerto"
        return
    }

    Invoke-Compose -Arguments @("up", "-d", "--force-recreate", "db") -Capture | Out-Null
    Wait-ServiceHealthy "db"
    Sync-DatabasePassword
    Pass "PostgreSQL" "healthy, credencial sincronizada y sin publicación de puerto"
}

function Ensure-BackendImage {
    if (Test-BackendImageCurrent) {
        Pass "Imagen backend" "actual; se reutiliza sin reconstruir"
        return
    }

    Write-Host "[INFO] Construyendo imagen backend remote-demo..."
    Invoke-Compose -Arguments @("build", "backend")
    Pass "Imagen backend" "construida para el árbol backend y Compose actuales"
}

function Show-Diagnostics {
    try {
        $ps = Invoke-Compose -Arguments @("ps", "-a") -Capture -IgnoreDeadline
        if ($ps) { Write-Host (Redact $ps) }
    }
    catch { }
    try {
        $logs = Invoke-Compose -Arguments @("logs", "--tail", "100", "db", "backend") -Capture -IgnoreDeadline
        if ($logs) { Write-Host (Redact $logs) }
    }
    catch { }
}

function Invoke-Status {
    Assert-EnvironmentContract
    Assert-Prerequisites
    $states = @("db", "backend") | ForEach-Object { Get-ServiceState $_ }
    $allHealthy = @($states | Where-Object { $_.State -ne "running" -or $_.Health -ne "healthy" }).Count -eq 0
    $networkReady = $false
    $flywayReady = $false
    $seedReady = $false
    $readinessReady = $false

    if ($allHealthy) {
        try { Assert-NetworkExposure; $networkReady = $true } catch { Write-Host "[FAIL] $(Redact $_.Exception.Message)" -ForegroundColor Red }
        try { Assert-FlywayHistory; $flywayReady = $true } catch { Write-Host "[FAIL] $(Redact $_.Exception.Message)" -ForegroundColor Red }
        try { $seedReady = Test-DemoSeedContract } catch { $seedReady = $false }
        $readinessReady = Test-Readiness
    }

    $states | Select-Object @{N="Contenedor";E={$_.Service}}, @{N="Estado";E={$_.State}}, @{N="Health";E={$_.Health}} | Format-Table -AutoSize | Out-Host
    Write-Host "Backend local: http://127.0.0.1:$((Get-EnvironmentValue 'BACKEND_PORT'))"
    Write-Host "Frontend CORS: $((Get-EnvironmentValue 'APP_CORS_ALLOWED_ORIGINS'))"
    Write-Host "PostgreSQL publicado: NO (requerido)"
    Write-Host "Flyway: $(if ($flywayReady) { 'OK' } else { 'NO' })"
    Write-Host "Seed demo: $(if ($seedReady) { 'OK' } else { 'NO' })"
    Write-Host "Readiness: $(if ($readinessReady) { 'UP' } else { 'DOWN' })"
    $available = $allHealthy -and $networkReady -and $flywayReady -and $seedReady -and $readinessReady
    Write-Host "Demo remota disponible: $(if ($available) { 'SÍ' } else { 'NO' })"
    return $available
}

function Invoke-Start {
    Assert-EnvironmentContract
    Assert-Prerequisites
    $backendPort = [int](Get-EnvironmentValue "BACKEND_PORT")
    Assert-PortAvailable $backendPort
    Set-BuildMetadataEnvironment
    $script:stackAttempted = $true

    Ensure-RemoteDatabase
    Ensure-BackendImage

    Invoke-Compose -Arguments @("up", "-d", "--no-deps", "--force-recreate", "backend") -Capture | Out-Null
    Wait-ServiceHealthy "backend"
    Pass "Backend" "healthy en loopback"

    Assert-NetworkExposure
    Assert-FlywayHistory
    Initialize-DemoSeedIfRequired
    Assert-True (Test-Readiness) "Readiness local no responde UP"

    Write-Host ""
    if (-not (Invoke-Status)) { throw "El stack arrancó pero no satisface el contrato remoto" }
    Write-Host ""
    Write-Host "DEMO REMOTA LOCAL LISTA" -ForegroundColor Green
    Write-Host "Configure Cloudflare Tunnel hacia http://127.0.0.1:$backendPort sólo en el segmento correspondiente."
}

function Invoke-Stop {
    if (-not (Test-Path -LiteralPath $script:composeFile -PathType Leaf)) { throw "Falta $($script:composeFile)" }
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw "Docker no está disponible en PATH" }
    Invoke-Docker -Arguments @("info", "--format", "{{.ServerVersion}}") -Capture -IgnoreDeadline | Out-Null
    Invoke-ProjectDown
    Write-Host "Demo remota detenida. Contenedores y red eliminados; volúmenes conservados."
}

function Invoke-Reset {
    Assert-EnvironmentContract
    Assert-Prerequisites
    Invoke-ProjectDown -Volumes
    Write-Host "Volúmenes de gestudio-remote-demo eliminados; recreando desde cero."
    Invoke-Start
}
