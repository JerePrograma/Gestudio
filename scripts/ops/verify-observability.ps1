[CmdletBinding()]
param(
    [string] $ComposeFile,
    [int] $TimeoutSeconds = 420,
    [switch] $KeepStack
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if ([string]::IsNullOrWhiteSpace($ComposeFile)) {
    $ComposeFile = Join-Path $repoRoot 'docker-compose.yml'
}

$suffix = [Guid]::NewGuid().ToString('N').Substring(0, 10)
$project = "gestudio-observability-$suffix"
$workRoot = Join-Path ([IO.Path]::GetTempPath()) $project
$envFile = Join-Path $workRoot 'verify.env'
$database = 'gestudio_observability_verify'
$postgresUser = 'gestudio_observability'
$rng = [Security.Cryptography.RandomNumberGenerator]::Create()
try {
    $postgresPasswordBytes = New-Object byte[] 24
    $jwtSecretBytes = New-Object byte[] 64
    $metricsTokenBytes = New-Object byte[] 48
    $rng.GetBytes($postgresPasswordBytes)
    $rng.GetBytes($jwtSecretBytes)
    $rng.GetBytes($metricsTokenBytes)
}
finally { $rng.Dispose() }
$postgresPassword = ([BitConverter]::ToString($postgresPasswordBytes) -replace '-', '').ToLowerInvariant()
$jwtSecret = ([BitConverter]::ToString($jwtSecretBytes) -replace '-', '').ToLowerInvariant()
$metricsToken = ([BitConverter]::ToString($metricsTokenBytes) -replace '-', '').ToLowerInvariant()
$backendImage = "gestudio-backend:observability-$suffix"
$customRequestId = "obs-$suffix"
$startedAt = Get-Date
$stackAttempted = $false
$hadPrimaryFailure = $false
$passes = 0
$failures = 0

function Invoke-Native {
    param(
        [Parameter(Mandatory)][string] $FilePath,
        [Parameter(Mandatory)][string[]] $Arguments,
        [switch] $Capture,
        [switch] $IgnoreFailure
    )

    $previous = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $FilePath @Arguments 2>&1)
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previous
    }

    $text = ($output | ForEach-Object { $_.ToString() }) -join "`n"
    if ($code -ne 0 -and -not $IgnoreFailure) {
        $tail = (($text -split "`r?`n") | Select-Object -Last 120) -join "`n"
        throw "El comando $FilePath falló con código ${code}: $tail"
    }
    if ($Capture) { return $text.Trim() }
    if (-not [string]::IsNullOrWhiteSpace($text)) { Write-Host $text }
    return $code
}

function Compose-Prefix {
    return @(
        'compose', '-f', (Resolve-Path -LiteralPath $ComposeFile).Path,
        '--env-file', (Resolve-Path -LiteralPath $envFile).Path,
        '-p', $project
    )
}

function Invoke-Compose {
    param([Parameter(Mandatory)][string[]] $Arguments, [switch] $Capture, [switch] $IgnoreFailure)
    return Invoke-Native -FilePath 'docker' -Arguments ((Compose-Prefix) + $Arguments) -Capture:$Capture -IgnoreFailure:$IgnoreFailure
}

function Get-FreePort {
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $listener.Start()
    try { return ([Net.IPEndPoint]$listener.LocalEndpoint).Port }
    finally { $listener.Stop() }
}

function Wait-ServiceHealthy {
    param([Parameter(Mandatory)][string] $Service)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $containerId = Invoke-Compose -Arguments @('ps', '-q', $Service) -Capture
        if (-not [string]::IsNullOrWhiteSpace($containerId)) {
            $status = Invoke-Native -FilePath 'docker' -Arguments @(
                'inspect', '--format', '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}',
                $containerId
            ) -Capture
            if ($status -eq 'healthy') { return $containerId }
            if ($status -in @('unhealthy', 'exited', 'dead')) {
                throw "El servicio '$Service' terminó en estado '$status'."
            }
        }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)

    throw "Timeout esperando que '$Service' quede healthy."
}

function Invoke-HttpGet {
    param(
        [Parameter(Mandatory)][string] $Uri,
        [hashtable] $Headers = @{}
    )

    $client = [Net.Http.HttpClient]::new()
    try {
        foreach ($entry in $Headers.GetEnumerator()) {
            if (-not $client.DefaultRequestHeaders.TryAddWithoutValidation([string]$entry.Key, [string]$entry.Value)) {
                throw "No se pudo agregar la cabecera '$($entry.Key)'."
            }
        }
        $response = $client.GetAsync($Uri).GetAwaiter().GetResult()
        $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        $requestIdValues = $null
        $requestId = $null
        if ($response.Headers.TryGetValues('X-Request-ID', [ref]$requestIdValues)) {
            $requestId = [string]($requestIdValues | Select-Object -First 1)
        }
        return [pscustomobject]@{
            StatusCode = [int]$response.StatusCode
            Body = $body
            RequestId = $requestId
        }
    }
    finally {
        $client.Dispose()
    }
}

function Assert-Equal {
    param($Actual, $Expected, [Parameter(Mandatory)][string] $Message)
    if ([string]$Actual -ne [string]$Expected) {
        throw "$Message. Esperado='$Expected', actual='$Actual'."
    }
}

function Assert-True {
    param([bool] $Condition, [Parameter(Mandatory)][string] $Message)
    if (-not $Condition) { throw $Message }
}

function Pass {
    param([Parameter(Mandatory)][string] $Name)
    $script:passes++
    Write-Host "[PASS] $Name" -ForegroundColor Green
}

function Show-Diagnostics {
    try {
        $state = Invoke-Compose -Arguments @('ps', '-a') -Capture -IgnoreFailure
        if ($state) { Write-Host $state }
    }
    catch { }
    try {
        $logs = Invoke-Compose -Arguments @('logs', '--no-color', '--tail', '220', 'db', 'backend') -Capture -IgnoreFailure
        if ($logs) { Write-Host $logs }
    }
    catch { }
}

function Assert-NoProjectResources {
    $containers = Invoke-Native -FilePath 'docker' -Arguments @(
        'ps', '-a', '--filter', "label=com.docker.compose.project=$project", '-q'
    ) -Capture
    $volumes = Invoke-Native -FilePath 'docker' -Arguments @(
        'volume', 'ls', '--filter', "label=com.docker.compose.project=$project", '-q'
    ) -Capture
    $networks = Invoke-Native -FilePath 'docker' -Arguments @(
        'network', 'ls', '--filter', "label=com.docker.compose.project=$project", '-q'
    ) -Capture
    Assert-True -Condition ([string]::IsNullOrWhiteSpace($containers)) -Message 'Quedaron contenedores residuales.'
    Assert-True -Condition ([string]::IsNullOrWhiteSpace($volumes)) -Message 'Quedaron volúmenes residuales.'
    Assert-True -Condition ([string]::IsNullOrWhiteSpace($networks)) -Message 'Quedaron redes residuales.'
}

if (-not (Test-Path -LiteralPath $ComposeFile -PathType Leaf)) {
    throw "No existe Compose: $ComposeFile"
}

$dbPort = Get-FreePort
$backendPort = Get-FreePort
$environment = [ordered]@{
    COMPOSE_PROJECT_NAME = $project
    POSTGRES_DB = $database
    POSTGRES_USER = $postgresUser
    POSTGRES_PASSWORD = $postgresPassword
    POSTGRES_PORT = $dbPort
    BACKEND_PORT = $backendPort
    FRONTEND_PORT = (Get-FreePort)
    BACKEND_IMAGE = $backendImage
    SPRING_PROFILES_ACTIVE = 'dev'
    SPRING_JPA_HIBERNATE_DDL_AUTO = 'validate'
    SPRING_FLYWAY_ENABLED = 'true'
    SPRING_FLYWAY_BASELINE_ON_MIGRATE = 'false'
    APP_SCHEDULING_ENABLED = 'false'
    APP_BOOTSTRAP_SUPERADMIN_ENABLED = 'false'
    APP_LOCAL_ADMIN_PASSWORD_RESET_ENABLED = 'false'
    APP_LOCAL_ADMIN_PASSWORD_RESET_USERNAME = ''
    APP_LOCAL_ADMIN_PASSWORD_RESET_PASSWORD = ''
    APP_OBSERVABILITY_METRICS_TOKEN = $metricsToken
    JWT_SECRET = $jwtSecret
    JWT_ISSUER = 'gestudio-observability-verify'
    APP_TIME_ZONE = 'America/Argentina/Buenos_Aires'
    APP_CORS_ALLOWED_ORIGINS = "http://127.0.0.1:$backendPort"
    APP_JERE_PLATFORM_STUDENT_EXPORT_ENABLED = 'false'
}
$previousProcessEnvironment = @{}

try {
    foreach ($entry in $environment.GetEnumerator()) {
        $previousProcessEnvironment[$entry.Key] = [Environment]::GetEnvironmentVariable($entry.Key, 'Process')
        [Environment]::SetEnvironmentVariable($entry.Key, [string]$entry.Value, 'Process')
    }
    New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
    $environment.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" } |
        Set-Content -LiteralPath $envFile -Encoding ASCII

    Invoke-Native -FilePath 'docker' -Arguments @('info', '--format', '{{.ServerVersion}}') | Out-Null
    Invoke-Native -FilePath 'docker' -Arguments @('compose', 'version') | Out-Null
    Pass 'Docker disponible'

    Push-Location $repoRoot
    try {
        $stackAttempted = $true
        Invoke-Compose -Arguments @('up', '-d', '--build', 'db', 'backend') | Out-Null
        Wait-ServiceHealthy -Service 'db' | Out-Null
        Wait-ServiceHealthy -Service 'backend' | Out-Null
        Pass 'Stack descartable healthy por readiness real'

        $baseUri = "http://127.0.0.1:$backendPort"
        $liveness = Invoke-HttpGet -Uri "$baseUri/actuator/health/liveness"
        $readiness = Invoke-HttpGet -Uri "$baseUri/actuator/health/readiness"
        Assert-Equal -Actual $liveness.StatusCode -Expected 200 -Message 'Liveness no respondió 200'
        Assert-Equal -Actual $readiness.StatusCode -Expected 200 -Message 'Readiness no respondió 200'
        Assert-Equal -Actual (($liveness.Body | ConvertFrom-Json).status) -Expected 'UP' -Message 'Liveness no está UP'
        Assert-Equal -Actual (($readiness.Body | ConvertFrom-Json).status) -Expected 'UP' -Message 'Readiness no está UP'
        Assert-True -Condition ($liveness.Body -notmatch 'components') -Message 'Liveness expuso detalles internos.'
        Assert-True -Condition ($readiness.Body -notmatch 'components') -Message 'Readiness expuso detalles internos.'
        Pass 'Liveness y readiness públicos mínimos'

        $metricsMissing = Invoke-HttpGet -Uri "$baseUri/actuator/prometheus"
        $metricsWrong = Invoke-HttpGet -Uri "$baseUri/actuator/prometheus" -Headers @{
            'X-Gestudio-Metrics-Token' = 'wrong-token'
        }
        Assert-Equal -Actual $metricsMissing.StatusCode -Expected 401 -Message 'Prometheus quedó accesible sin token'
        Assert-Equal -Actual $metricsWrong.StatusCode -Expected 401 -Message 'Prometheus aceptó un token incorrecto'
        Pass 'Prometheus fail-closed con credencial ausente o inválida'

        $metrics = Invoke-HttpGet -Uri "$baseUri/actuator/prometheus" -Headers @{
            'X-Gestudio-Metrics-Token' = $metricsToken
        }
        Assert-Equal -Actual $metrics.StatusCode -Expected 200 -Message 'Prometheus rechazó el token correcto'
        Assert-True -Condition ($metrics.Body -match 'jvm_memory_used_bytes') -Message 'Falta métrica JVM esperada.'
        Assert-True -Condition ($metrics.Body -match 'process_uptime_seconds') -Message 'Falta métrica de proceso esperada.'
        Pass 'Prometheus autenticado publica métricas mínimas'

        $custom = Invoke-HttpGet -Uri "$baseUri/api/alumnos" -Headers @{
            'X-Request-ID' = $customRequestId
        }
        Assert-Equal -Actual $custom.StatusCode -Expected 401 -Message 'La ruta protegida no devolvió 401'
        Assert-Equal -Actual $custom.RequestId -Expected $customRequestId -Message 'No se propagó X-Request-ID'

        $generated = Invoke-HttpGet -Uri "$baseUri/api/alumnos"
        Assert-True -Condition ($generated.RequestId -match '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$') `
            -Message 'No se generó un UUID para X-Request-ID ausente.'

        $replaced = Invoke-HttpGet -Uri "$baseUri/api/alumnos" -Headers @{
            'X-Request-ID' = 'unsafe request id'
        }
        Assert-True -Condition ($replaced.RequestId -match '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$') `
            -Message 'No se reemplazó un X-Request-ID inseguro.'
        Pass 'Correlación propagada generada y saneada'

        Start-Sleep -Seconds 1
        $logs = Invoke-Compose -Arguments @('logs', '--no-color', 'backend') -Capture
        Assert-True -Condition ($logs -match [regex]::Escape("requestId=$customRequestId")) -Message 'El log no contiene el request ID esperado.'
        Assert-True -Condition ($logs -match 'http_request method=GET path=/api/alumnos status=401') -Message 'Falta el evento HTTP sanitizado.'
        Assert-True -Condition ($logs -notmatch [regex]::Escape($metricsToken)) -Message 'El token de métricas apareció en logs.'
        Assert-True -Condition ($logs -notmatch [regex]::Escape($jwtSecret)) -Message 'El secreto JWT apareció en logs.'
        Assert-True -Condition ($logs -notmatch [regex]::Escape($postgresPassword)) -Message 'La clave PostgreSQL apareció en logs.'
        Pass 'Logs correlacionados sin secretos conocidos'
    }
    finally {
        Pop-Location
    }
}
catch {
    $hadPrimaryFailure = $true
    $failures++
    Write-Host "[FAIL] $($_.Exception.Message)" -ForegroundColor Red
    Show-Diagnostics
    throw
}
finally {
    if ($stackAttempted -and -not $KeepStack) {
        try { Invoke-Compose -Arguments @('down', '--volumes', '--remove-orphans') -IgnoreFailure | Out-Null }
        catch { }
        try { Invoke-Native -FilePath 'docker' -Arguments @('image', 'rm', '--force', $backendImage) -IgnoreFailure | Out-Null }
        catch { }
        try { Assert-NoProjectResources; Pass 'Cleanup sin recursos residuales' }
        catch {
            $failures++
            Write-Host "[FAIL] $($_.Exception.Message)" -ForegroundColor Red
            if (-not $hadPrimaryFailure) { throw }
        }
    }
    if (-not $KeepStack -and (Test-Path -LiteralPath $workRoot)) {
        Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    foreach ($entry in $previousProcessEnvironment.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process')
    }

    $duration = (Get-Date) - $startedAt
    Write-Host "Observability drill duration: $($duration.ToString())"
    Write-Host "Passes: $passes"
    Write-Host "Failures: $failures"
}
