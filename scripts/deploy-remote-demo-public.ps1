param(
    [string] $RepoPath = "C:\laburo\Gestudio",
    [string] $PagesProject = "gestudio-demo-jere-287b8c90",
    [string] $PagesOrigin = "https://gestudio-demo-jere-287b8c90.pages.dev",
    [int] $BackendPort = 18080
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Net.Http

$repoRoot = [IO.Path]::GetFullPath($RepoPath)
$frontendRoot = Join-Path $repoRoot "frontend"
$envPath = Join-Path $repoRoot ".env.remote-demo"
$launcherPath = Join-Path $repoRoot "scripts/demo-remote.ps1"
$backendOrigin = "http://127.0.0.1:$BackendPort"
$pagesOriginNormalized = $PagesOrigin.TrimEnd("/")
$stateRoot = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "Gestudio-RemoteDemo"
$logRoot = Join-Path $stateRoot "logs"
$statePath = Join-Path $stateRoot "public-deployment.json"
$secretFile = $null
$newTunnelStarted = $false
$pagesDeploymentCompleted = $false
$proxyToken = $null

function Pass {
    param([Parameter(Mandatory)][string] $Name, [string] $Detail = "")

    $suffix = if ([string]::IsNullOrWhiteSpace($Detail)) { "" } else { " - $Detail" }
    Write-Host "[PASS] $Name$suffix" -ForegroundColor Green
}

function Info {
    param([Parameter(Mandatory)][string] $Message)

    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Invoke-Native {
    param(
        [Parameter(Mandatory)][string] $FilePath,
        [Parameter(Mandatory)][string[]] $Arguments,
        [switch] $Capture
    )

    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        if ($Capture) {
            $output = @(& $FilePath @Arguments 2>&1)
            $code = $LASTEXITCODE
            $text = ($output | ForEach-Object { $_.ToString() }) -join "`n"
        }
        else {
            & $FilePath @Arguments
            $code = $LASTEXITCODE
            $text = ""
        }
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
    }

    if ($code -ne 0) {
        $detail = if ([string]::IsNullOrWhiteSpace($text)) { "" } else { "`n$text" }
        throw "$([IO.Path]::GetFileName($FilePath)) falló con código ${code}.${detail}"
    }

    if ($Capture) { return $text.Trim() }
}

function Resolve-NativeCommand {
    param([Parameter(Mandatory)][string[]] $Names)

    foreach ($name in $Names) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($null -ne $command) { return $command.Source }
    }
    throw "No se encontró ningún comando requerido: $($Names -join ', ')"
}

function Read-DotEnvValue {
    param([Parameter(Mandatory)][string] $Name)

    $prefix = "$Name="
    $line = Get-Content -LiteralPath $envPath |
        Where-Object { $_.StartsWith($prefix, [StringComparison]::Ordinal) } |
        Select-Object -First 1

    if ($null -eq $line) { throw "Falta $Name en $envPath" }
    $value = $line.Substring($prefix.Length)
    if ([string]::IsNullOrWhiteSpace($value)) { throw "$Name está vacío en $envPath" }
    return $value
}

function Get-HttpResult {
    param(
        [Parameter(Mandatory)][string] $Uri,
        [ValidateSet("GET", "POST", "OPTIONS")][string] $Method = "GET",
        [hashtable] $Headers = @{},
        [AllowNull()][string] $Body = $null
    )

    $handler = [Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $false
    $client = [Net.Http.HttpClient]::new($handler, $true)
    $client.Timeout = [TimeSpan]::FromSeconds(15)
    $request = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::new($Method), $Uri)

    try {
        foreach ($entry in $Headers.GetEnumerator()) {
            [void]$request.Headers.TryAddWithoutValidation([string]$entry.Key, [string]$entry.Value)
        }
        if ($null -ne $Body) {
            $request.Content = [Net.Http.StringContent]::new($Body, [Text.Encoding]::UTF8, "application/json")
        }

        try {
            $response = $client.SendAsync($request).GetAwaiter().GetResult()
            try {
                $responseBody = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                $contentType = if ($null -eq $response.Content.Headers.ContentType) {
                    ""
                }
                else {
                    $response.Content.Headers.ContentType.MediaType
                }
                return [pscustomobject]@{
                    Status = [int]$response.StatusCode
                    Body = $responseBody
                    ContentType = $contentType
                    Error = ""
                }
            }
            finally { $response.Dispose() }
        }
        catch {
            return [pscustomobject]@{
                Status = 0
                Body = ""
                ContentType = ""
                Error = $_.Exception.Message
            }
        }
    }
    finally {
        $request.Dispose()
        $client.Dispose()
    }
}

function Wait-HttpStatus {
    param(
        [Parameter(Mandatory)][string] $Uri,
        [Parameter(Mandatory)][int[]] $ExpectedStatuses,
        [ValidateSet("GET", "POST", "OPTIONS")][string] $Method = "GET",
        [hashtable] $Headers = @{},
        [AllowNull()][string] $Body = $null,
        [int] $TimeoutSeconds = 240
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $nextProgress = Get-Date
    $last = $null

    while ((Get-Date) -lt $deadline) {
        $last = Get-HttpResult -Uri $Uri -Method $Method -Headers $Headers -Body $Body
        if ($last.Status -in $ExpectedStatuses) { return $last }

        if ((Get-Date) -ge $nextProgress) {
            $detail = if ($last.Status -eq 0) { $last.Error } else { "HTTP $($last.Status)" }
            Info "Esperando $Uri ($detail)"
            $nextProgress = (Get-Date).AddSeconds(10)
        }
        Start-Sleep -Seconds 2
    }

    $lastDetail = if ($null -eq $last) {
        "sin respuesta"
    }
    elseif ($last.Status -eq 0) {
        $last.Error
    }
    else {
        "HTTP $($last.Status), content-type=$($last.ContentType)"
    }
    throw "Timeout esperando $Uri. Estados esperados: $($ExpectedStatuses -join ', '). Último resultado: $lastDetail"
}

function Wait-DnsResolution {
    param([Parameter(Mandatory)][Uri] $Uri, [int] $TimeoutSeconds = 240)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $nextProgress = Get-Date
    while ((Get-Date) -lt $deadline) {
        try {
            $addresses = @([Net.Dns]::GetHostAddresses($Uri.DnsSafeHost))
            if ($addresses.Count -gt 0) {
                Pass "DNS Quick Tunnel" (($addresses | ForEach-Object { $_.IPAddressToString }) -join ", ")
                return
            }
        }
        catch { }

        if ((Get-Date) -ge $nextProgress) {
            Info "Esperando resolución DNS de $($Uri.DnsSafeHost)"
            $nextProgress = (Get-Date).AddSeconds(10)
        }
        Start-Sleep -Seconds 2
    }
    throw "El hostname Quick Tunnel no resolvió por DNS: $($Uri.DnsSafeHost)"
}

function Read-TunnelState {
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { return $null }
    try { return Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json }
    catch { return $null }
}

function Write-TunnelState {
    param(
        [Parameter(Mandatory)][string] $Origin,
        [Parameter(Mandatory)][int] $ProcessId,
        [Parameter(Mandatory)][DateTime] $StartedAt,
        [Parameter(Mandatory)][string] $StdoutPath,
        [Parameter(Mandatory)][string] $StderrPath,
        [AllowNull()][string] $Commit = $null,
        [AllowNull()][string] $PublishedAt = $null
    )

    $state = [ordered]@{
        Origin = $Origin
        ProcessId = $ProcessId
        ProcessStartedAt = $StartedAt.ToUniversalTime().ToString("o")
        BackendOrigin = $backendOrigin
        PagesProject = $PagesProject
        PagesOrigin = $pagesOriginNormalized
        Commit = $Commit
        PublishedAt = $PublishedAt
        StdoutPath = $StdoutPath
        StderrPath = $StderrPath
    }
    New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
    [IO.File]::WriteAllText(
        $statePath,
        ($state | ConvertTo-Json -Depth 4),
        [Text.UTF8Encoding]::new($false)
    )
}

function Stop-TrackedQuickTunnel {
    $state = Read-TunnelState
    if ($null -eq $state -or $null -eq $state.ProcessId) { return }

    $trackedProcessId = 0
    if (-not [int]::TryParse([string]$state.ProcessId, [ref]$trackedProcessId)) { return }

    $process = Get-Process -Id $trackedProcessId -ErrorAction SilentlyContinue
    if ($null -eq $process) {
        Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
        return
    }

    $commandLine = ""
    try {
        $processInfo = Get-CimInstance Win32_Process -Filter "ProcessId = $trackedProcessId"
        if ($null -ne $processInfo) { $commandLine = [string]$processInfo.CommandLine }
    }
    catch { }

    $isOwnedTunnel = $process.ProcessName -like "cloudflared*" -and
        $commandLine -match "(?i)\btunnel\b" -and
        $commandLine.Contains($backendOrigin, [StringComparison]::OrdinalIgnoreCase)

    if (-not $isOwnedTunnel) {
        Write-Host "[WARN] El PID registrado ya no corresponde al Quick Tunnel de Gestudio; no se detuvo." -ForegroundColor Yellow
        Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
        return
    }

    Info "Deteniendo Quick Tunnel anterior registrado por Gestudio (PID $trackedProcessId)"
    Stop-Process -Id $trackedProcessId -ErrorAction Stop
    try { $process.WaitForExit(15000) } catch { }
    Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
    Pass "Quick Tunnel anterior" "detenido sin afectar otros procesos"
}

function Get-TunnelLogs {
    param([Parameter(Mandatory)][string] $StdoutPath, [Parameter(Mandatory)][string] $StderrPath)

    return @(
        if (Test-Path -LiteralPath $StdoutPath -PathType Leaf) {
            Get-Content -LiteralPath $StdoutPath -Raw -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $StderrPath -PathType Leaf) {
            Get-Content -LiteralPath $StderrPath -Raw -ErrorAction SilentlyContinue
        }
    ) -join "`n"
}

function Show-TunnelLogTail {
    $state = Read-TunnelState
    if ($null -eq $state) { return }
    foreach ($path in @([string]$state.StdoutPath, [string]$state.StderrPath)) {
        if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path -PathType Leaf)) {
            Write-Host "--- $path ---"
            Get-Content -LiteralPath $path -Tail 80 -ErrorAction SilentlyContinue | Out-Host
        }
    }
}

function Start-QuickTunnel {
    $configFiles = @(
        (Join-Path $HOME ".cloudflared/config.yml"),
        (Join-Path $HOME ".cloudflared/config.yaml")
    )
    $blockingConfig = $configFiles |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1
    if ($null -ne $blockingConfig) {
        throw "Quick Tunnel no puede iniciarse mientras exista $blockingConfig. No se modificó el archivo."
    }

    $cloudflared = Resolve-NativeCommand -Names @("cloudflared.exe", "cloudflared")
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $stdoutPath = Join-Path $logRoot "cloudflared-$timestamp.stdout.log"
    $stderrPath = Join-Path $logRoot "cloudflared-$timestamp.stderr.log"

    $process = Start-Process \
        -FilePath $cloudflared \
        -ArgumentList @("tunnel", "--url", $backendOrigin, "--no-autoupdate") \
        -RedirectStandardOutput $stdoutPath \
        -RedirectStandardError $stderrPath \
        -WindowStyle Hidden \
        -PassThru

    $origin = $null
    $urlDeadline = (Get-Date).AddSeconds(90)
    while ((Get-Date) -lt $urlDeadline) {
        if ($process.HasExited) {
            $logs = Get-TunnelLogs -StdoutPath $stdoutPath -StderrPath $stderrPath
            throw "cloudflared terminó con código $($process.ExitCode) antes de publicar el túnel.`n$logs"
        }
        $logs = Get-TunnelLogs -StdoutPath $stdoutPath -StderrPath $stderrPath
        $match = [regex]::Match(
            $logs,
            "https://[a-z0-9-]+[.]trycloudflare[.]com",
            [Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
        if ($match.Success) {
            $origin = $match.Value.TrimEnd("/")
            break
        }
        Start-Sleep -Seconds 2
    }
    if ([string]::IsNullOrWhiteSpace($origin)) {
        throw "cloudflared no informó el hostname Quick Tunnel"
    }

    Write-TunnelState \
        -Origin $origin \
        -ProcessId $process.Id \
        -StartedAt $process.StartTime \
        -StdoutPath $stdoutPath \
        -StderrPath $stderrPath

    $connectionDeadline = (Get-Date).AddSeconds(150)
    $registered = $false
    while ((Get-Date) -lt $connectionDeadline) {
        if ($process.HasExited) {
            $logs = Get-TunnelLogs -StdoutPath $stdoutPath -StderrPath $stderrPath
            throw "cloudflared terminó con código $($process.ExitCode) antes de registrar una conexión.`n$logs"
        }
        $logs = Get-TunnelLogs -StdoutPath $stdoutPath -StderrPath $stderrPath
        if ($logs -match "(?i)Registered tunnel connection") {
            $registered = $true
            break
        }
        Start-Sleep -Seconds 2
    }
    if ($registered) {
        Pass "Conector cloudflared" "conexión registrada"
    }
    else {
        Write-Host "[WARN] No apareció el mensaje de registro; se continuará con validación DNS/HTTP." -ForegroundColor Yellow
    }

    $originUri = [Uri]$origin
    Wait-DnsResolution -Uri $originUri -TimeoutSeconds 300

    [void](Wait-HttpStatus \
        -Uri "$origin/api/usuarios/perfil" \
        -ExpectedStatuses @(404) \
        -TimeoutSeconds 300)
    Pass "Protección directa del túnel" "HTTP 404 sin proxy token"

    [void](Wait-HttpStatus \
        -Uri "$origin/api/usuarios/perfil" \
        -ExpectedStatuses @(401) \
        -Headers @{ "X-Gestudio-Proxy-Token" = $proxyToken } \
        -TimeoutSeconds 180)
    Pass "Quick Tunnel hacia backend" "HTTP 401 esperado con proxy token y sin sesión"

    return [pscustomobject]@{
        Origin = $origin
        ProcessId = $process.Id
        ProcessStartedAt = $process.StartTime
        StdoutPath = $stdoutPath
        StderrPath = $stderrPath
    }
}

function Assert-GitContract {
    $git = Resolve-NativeCommand -Names @("git.exe", "git")
    $topLevel = Invoke-Native -FilePath $git -Arguments @("-C", $repoRoot, "rev-parse", "--show-toplevel") -Capture
    if ([IO.Path]::GetFullPath($topLevel) -ne $repoRoot.TrimEnd([IO.Path]::DirectorySeparatorChar)) {
        throw "El repositorio resuelto no corresponde a $repoRoot"
    }

    $branch = Invoke-Native -FilePath $git -Arguments @("-C", $repoRoot, "branch", "--show-current") -Capture
    if ($branch -ne "main") { throw "La rama actual debe ser main; actual=$branch" }

    $status = Invoke-Native -FilePath $git -Arguments @("-C", $repoRoot, "status", "--porcelain=v1") -Capture
    if (-not [string]::IsNullOrWhiteSpace($status)) { throw "Existen cambios locales versionables:`n$status" }

    Invoke-Native -FilePath $git -Arguments @("-C", $repoRoot, "fetch", "origin", "--prune")
    $head = Invoke-Native -FilePath $git -Arguments @("-C", $repoRoot, "rev-parse", "HEAD") -Capture
    $originMain = Invoke-Native -FilePath $git -Arguments @("-C", $repoRoot, "rev-parse", "origin/main") -Capture
    if ($head -ne $originMain) {
        throw "main local no coincide con origin/main. HEAD=$head origin/main=$originMain"
    }
    Pass "Git" "main limpia y sincronizada en $head"
    return $head
}

function Start-RemoteDemoBackend {
    $pwsh = Resolve-NativeCommand -Names @("pwsh.exe", "pwsh")
    Invoke-Native -FilePath $pwsh -Arguments @(
        "-NoProfile",
        "-File", $launcherPath,
        "-Action", "Start",
        "-EnvFile", $envPath
    )
    [void](Wait-HttpStatus \
        -Uri "$backendOrigin/actuator/health/readiness" \
        -ExpectedStatuses @(200) \
        -TimeoutSeconds 120)
    Pass "Backend local" "readiness UP en $backendOrigin"
}

function Publish-Pages {
    param([Parameter(Mandatory)] $Tunnel, [Parameter(Mandatory)][string] $Commit)

    $npm = Resolve-NativeCommand -Names @("npm.cmd", "npm")
    $npx = Resolve-NativeCommand -Names @("npx.cmd", "npx")
    $script:secretFile = Join-Path ([IO.Path]::GetTempPath()) "gestudio-pages-secrets-$PID.json"
    $secrets = [ordered]@{
        GESTUDIO_BACKEND_ORIGIN = $Tunnel.Origin
        GESTUDIO_PROXY_TOKEN = $proxyToken
    }
    [IO.File]::WriteAllText(
        $script:secretFile,
        ($secrets | ConvertTo-Json -Compress),
        [Text.UTF8Encoding]::new($false)
    )

    Push-Location $frontendRoot
    $previousApiUrl = [Environment]::GetEnvironmentVariable("VITE_API_BASE_URL", "Process")
    $previousTimeZone = [Environment]::GetEnvironmentVariable("VITE_APP_TIME_ZONE", "Process")
    try {
        Invoke-Native -FilePath $npx -Arguments @("--yes", "wrangler", "whoami")
        Invoke-Native -FilePath $npx -Arguments @(
            "--yes", "wrangler", "pages", "secret", "bulk", $script:secretFile,
            "--project-name", $PagesProject
        )
        Pass "Bindings Pages" "origin y proxy token actualizados antes del deploy"

        [Environment]::SetEnvironmentVariable("VITE_API_BASE_URL", "$pagesOriginNormalized/api", "Process")
        [Environment]::SetEnvironmentVariable("VITE_APP_TIME_ZONE", "America/Argentina/Buenos_Aires", "Process")

        Invoke-Native -FilePath $npm -Arguments @("ci")
        Invoke-Native -FilePath $npm -Arguments @("run", "build")
        Pass "Frontend" "build de producción completado"

        Invoke-Native -FilePath $npx -Arguments @(
            "--yes", "wrangler", "pages", "deploy", "dist",
            "--project-name", $PagesProject,
            "--branch", "main",
            "--commit-hash", $Commit,
            "--commit-message", "remote-demo: publish backend origin"
        )
        $script:pagesDeploymentCompleted = $true
        Pass "Cloudflare Pages" "deployment de producción publicado"
    }
    finally {
        [Environment]::SetEnvironmentVariable("VITE_API_BASE_URL", $previousApiUrl, "Process")
        [Environment]::SetEnvironmentVariable("VITE_APP_TIME_ZONE", $previousTimeZone, "Process")
        Pop-Location
    }
}

function Assert-PublicDeployment {
    [void](Wait-HttpStatus -Uri $pagesOriginNormalized -ExpectedStatuses @(200) -TimeoutSeconds 300)
    Pass "Frontend público" "HTTP 200"

    $profile = Wait-HttpStatus \
        -Uri "$pagesOriginNormalized/api/usuarios/perfil" \
        -ExpectedStatuses @(401) \
        -TimeoutSeconds 300
    if ($profile.ContentType -notmatch "(?i)application/json") {
        throw "La API pública respondió 401 pero no JSON; content-type=$($profile.ContentType)"
    }
    Pass "API pública" "HTTP 401 JSON sin sesión"

    $refresh = Wait-HttpStatus \
        -Uri "$pagesOriginNormalized/api/login/refresh" \
        -Method "POST" \
        -Body "{}" \
        -ExpectedStatuses @(401) \
        -TimeoutSeconds 180
    if ($refresh.ContentType -notmatch "(?i)application/json") {
        throw "Refresh público respondió 401 pero no JSON; content-type=$($refresh.ContentType)"
    }
    Pass "Refresh público" "HTTP 401 JSON sin cookie; sin 530/1016"

    [void](Wait-HttpStatus \
        -Uri "$pagesOriginNormalized/api/login" \
        -Method "OPTIONS" \
        -Headers @{
            "Origin" = $pagesOriginNormalized
            "Access-Control-Request-Method" = "POST"
            "Access-Control-Request-Headers" = "content-type"
        } \
        -ExpectedStatuses @(200, 204) \
        -TimeoutSeconds 120)
    Pass "CORS público" "preflight de login aceptado"
}

try {
    if (-not [Environment]::Is64BitOperatingSystem -or [Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw "Este despliegue operativo está preparado para Windows PowerShell 7"
    }
    foreach ($requiredPath in @($repoRoot, $frontendRoot, $envPath, $launcherPath)) {
        if (-not (Test-Path -LiteralPath $requiredPath)) { throw "Falta ruta requerida: $requiredPath" }
    }

    $commit = Assert-GitContract
    $script:proxyToken = Read-DotEnvValue -Name "APP_REMOTE_DEMO_PROXY_TOKEN"
    if ([Text.Encoding]::UTF8.GetByteCount($script:proxyToken) -lt 32) {
        throw "APP_REMOTE_DEMO_PROXY_TOKEN debe tener al menos 32 bytes UTF-8"
    }

    Start-RemoteDemoBackend
    Stop-TrackedQuickTunnel
    $tunnel = Start-QuickTunnel
    $script:newTunnelStarted = $true
    Publish-Pages -Tunnel $tunnel -Commit $commit
    Assert-PublicDeployment

    Write-TunnelState \
        -Origin $tunnel.Origin \
        -ProcessId $tunnel.ProcessId \
        -StartedAt $tunnel.ProcessStartedAt \
        -StdoutPath $tunnel.StdoutPath \
        -StderrPath $tunnel.StderrPath \
        -Commit $commit \
        -PublishedAt ([DateTimeOffset]::UtcNow.ToString("o"))

    Write-Host ""
    Pass "DEMO REMOTA PÚBLICA" "disponible"
    Write-Host "Frontend: $pagesOriginNormalized"
    Write-Host "Backend local: $backendOrigin"
    Write-Host "Quick Tunnel: $($tunnel.Origin)"
    Write-Host "Estado: $statePath"
    Write-Host ""
    Write-Host "Mantenga el equipo, Docker Desktop y el proceso cloudflared encendidos." -ForegroundColor Yellow
}
catch {
    Write-Host "[FAIL] $($_.Exception.Message)" -ForegroundColor Red
    Show-TunnelLogTail
    if ($newTunnelStarted -and -not $pagesDeploymentCompleted) {
        try { Stop-TrackedQuickTunnel } catch { }
    }
    throw
}
finally {
    $script:proxyToken = $null
    if (-not [string]::IsNullOrWhiteSpace($secretFile) -and (Test-Path -LiteralPath $secretFile -PathType Leaf)) {
        Remove-Item -LiteralPath $secretFile -Force -ErrorAction SilentlyContinue
    }
}
