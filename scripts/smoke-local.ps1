param(
    [switch] $KeepStack,
    [switch] $SkipBuild,
    [switch] $VerboseHttp
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Net.Http

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$startedAt = Get-Date
$deadline = $startedAt.AddMinutes(20)
$suffix = ([Guid]::NewGuid().ToString("N")).Substring(0, 8)
$project = "gestudio-smoke-$PID-$suffix"
$envFile = Join-Path ([IO.Path]::GetTempPath()) "$project.env"
$passes = 0
$failures = 0
$stackAttempted = $false
$accessToken = $null
$refreshToken = $null
$postgresPassword = $null
$jwtSecret = $null
$adminPassword = $null
$secretariaPassword = $null
$cajaPassword = $null
$limitedPassword = $null
$http = $null
$cookieContainer = $null
$caught = $null
$originalEnvironment = @{}

function New-HexSecret {
    param([Parameter(Mandatory)][int] $Bytes)

    $buffer = New-Object byte[] $Bytes
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($buffer) }
    finally { $rng.Dispose() }
    return [BitConverter]::ToString($buffer).Replace("-", "").ToLowerInvariant()
}

function Get-FreePort {
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    try {
        $listener.Start()
        return ([Net.IPEndPoint]$listener.LocalEndpoint).Port
    }
    finally { $listener.Stop() }
}

function Get-BusinessNow {
    try {
        $zone = [TimeZoneInfo]::FindSystemTimeZoneById("America/Argentina/Buenos_Aires")
    }
    catch {
        $zone = [TimeZoneInfo]::FindSystemTimeZoneById("Argentina Standard Time")
    }

    return [TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $zone)
}

function Redact {
    param([AllowNull()][string] $Text)

    if ($null -eq $Text) { return "" }
    $safe = $Text
    foreach ($secret in @($script:postgresPassword, $script:jwtSecret, $script:adminPassword,
            $script:secretariaPassword, $script:cajaPassword, $script:limitedPassword,
            $script:accessToken, $script:refreshToken)) {
        if (-not [string]::IsNullOrEmpty($secret)) { $safe = $safe.Replace($secret, "<redacted>") }
    }
    return $safe
}

function Assert-Deadline {
    if ((Get-Date) -gt $script:deadline) { throw "Se agoto el timeout global de 20 minutos" }
}

function Assert-True {
    param([Parameter(Mandatory)][bool] $Condition, [Parameter(Mandatory)][string] $Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param($Actual, $Expected, [Parameter(Mandatory)][string] $Message)
    if ($Actual -ne $Expected) { throw "$Message (esperado=$Expected, actual=$Actual)" }
}

function Pass {
    param([Parameter(Mandatory)][string] $Name)
    $script:passes++
    Write-Host "[PASS] $Name" -ForegroundColor Green
}

function Invoke-Docker {
    param(
        [Parameter(Mandatory)][string[]] $Arguments,
        [switch] $Capture,
        [switch] $IgnoreDeadline
    )

    if (-not $IgnoreDeadline) { Assert-Deadline }
    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = @(& docker @Arguments 2>&1)
        $code = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousErrorAction }
    $text = ($output | ForEach-Object { $_.ToString() }) -join "`n"
    if ($code -ne 0) {
        $tail = (($text -split "`r?`n") | Select-Object -Last 30) -join "`n"
        throw "Docker fallo con codigo ${code}: $(Redact $tail)"
    }
    if ($Capture) { return $text.Trim() }
    if (-not [string]::IsNullOrWhiteSpace($text)) { Write-Host (Redact $text) }
}

function Invoke-Compose {
    param([Parameter(Mandatory)][string[]] $Arguments, [switch] $Capture, [switch] $IgnoreDeadline)
    $all = @("compose", "--env-file", $script:envFile, "-p", $script:project) + $Arguments
    return Invoke-Docker -Arguments $all -Capture:$Capture -IgnoreDeadline:$IgnoreDeadline
}

function Wait-ServiceHealthy {
    param([Parameter(Mandatory)][string] $Service)

    while ((Get-Date) -lt $script:deadline) {
        $id = Invoke-Compose -Arguments @("ps", "-q", $Service) -Capture
        if (-not [string]::IsNullOrWhiteSpace($id)) {
            $state = Invoke-Docker -Arguments @("inspect", "--format", "{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{end}}", $id) -Capture
            if ($state -eq "running|healthy") { return }
            if ($state.StartsWith("exited|") -or $state.StartsWith("dead|")) {
                throw "El servicio $Service termino antes de estar healthy"
            }
        }
        Start-Sleep -Seconds 2
    }
    throw "Timeout esperando healthcheck de $Service"
}

function Invoke-Sql {
    param([Parameter(Mandatory)][string] $Query)

    Assert-Deadline
    $args = @("compose", "--env-file", $script:envFile, "-p", $script:project,
        "exec", "-T", "db", "psql", "-v", "ON_ERROR_STOP=1", "-U", $script:postgresUser,
        "-d", $script:postgresDb, "-A", "-t", "-F", "|", "-c", $Query)
    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = @(& docker @args 2>&1)
        $code = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousErrorAction }
    $text = ($output | ForEach-Object { $_.ToString() }) -join "`n"
    if ($code -ne 0) { throw "La asercion SQL fallo: $(Redact $text)" }
    return $text.Trim()
}

function Assert-AuditZero {
    param([Parameter(Mandatory)][string] $RelativePath)

    $query = Get-Content -Raw (Join-Path $script:repoRoot $RelativePath)
    $result = Invoke-Sql -Query $query
    foreach ($line in ($result -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line.Split("|")
        Assert-Equal -Actual $parts.Count -Expected 2 -Message "Salida de auditoria inesperada"
        Assert-Equal -Actual ([int]$parts[1]) -Expected 0 -Message "Fallo la regla $($parts[0])"
    }
}

function Invoke-SmokeHttp {
    param(
        [Parameter(Mandatory)][string] $Method,
        [Parameter(Mandatory)][string] $Uri,
        $Body,
        [AllowNull()][string] $Token
    )

    Assert-Deadline
    $request = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::new($Method), $Uri)
    try {
        if (-not [string]::IsNullOrWhiteSpace($Token)) {
            $request.Headers.Authorization = [Net.Http.Headers.AuthenticationHeaderValue]::new("Bearer", $Token)
        }
        if ($Uri -match '/login/(refresh|logout)$') {
            [void]$request.Headers.TryAddWithoutValidation("Origin", $script:frontendOrigin)
        }
        if ($null -ne $Body) {
            $json = $Body | ConvertTo-Json -Depth 12 -Compress
            $request.Content = [Net.Http.StringContent]::new($json, [Text.Encoding]::UTF8, "application/json")
        }
        $response = $script:http.SendAsync($request).GetAwaiter().GetResult()
        try {
            $raw = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            if ($script:VerboseHttp) { Write-Host "[HTTP] $Method $Uri -> $([int]$response.StatusCode)" }
            return [pscustomobject]@{ Status = [int]$response.StatusCode; Body = $raw }
        }
        finally { $response.Dispose() }
    }
    finally { $request.Dispose() }
}

function Get-RefreshToken {
    $cookie = $script:cookieContainer.GetCookies([Uri]($script:apiBase + "/login"))["gestudio_refresh"]
    if ($null -eq $cookie -or [string]::IsNullOrWhiteSpace($cookie.Value)) {
        throw "Login/refresh sin cookie HttpOnly"
    }
    return $cookie.Value
}

function Set-RefreshToken {
    param([Parameter(Mandatory)][string] $Value)
    $uri = [Uri]($script:apiBase + "/login")
    $cookie = $script:cookieContainer.GetCookies($uri)["gestudio_refresh"]
    if ($null -ne $cookie) {
        $cookie.Value = $Value
        return
    }
    $newCookie = [Net.Cookie]::new("gestudio_refresh", $Value, "/api/login", "127.0.0.1")
    $newCookie.HttpOnly = $true
    $script:cookieContainer.Add($uri, $newCookie)
}

function Invoke-Api {
    param(
        [Parameter(Mandatory)][string] $Method,
        [Parameter(Mandatory)][string] $Path,
        $Body = $null,
        [AllowNull()][string] $Token = $script:accessToken,
        [Parameter(Mandatory)][int] $ExpectedStatus
    )

    $result = Invoke-SmokeHttp -Method $Method -Uri ($script:apiBase + $Path) -Body $Body -Token $Token
    if ($result.Status -ne $ExpectedStatus) {
        throw "$Method $Path devolvio un estado inesperado (esperado=$ExpectedStatus, actual=$($result.Status), body=$(Redact $result.Body))"
    }
    $json = $null
    if (-not [string]::IsNullOrWhiteSpace($result.Body)) { $json = $result.Body | ConvertFrom-Json }
    return [pscustomobject]@{ Status = $result.Status; Body = $result.Body; Json = $json }
}

function Login {
    $response = Invoke-Api -Method "POST" -Path "/login" -Body @{
        nombreUsuario = $script:adminUsername
        contrasena = $script:adminPassword
    } -Token $null -ExpectedStatus 200
    Assert-True -Condition (-not [string]::IsNullOrWhiteSpace($response.Json.accessToken)) -Message "Login sin access token"
    Assert-True -Condition ($response.Json.PSObject.Properties.Name -notcontains "refreshToken") -Message "El refresh token no debe exponerse en el body"
    Assert-Equal -Actual $response.Json.usuario.nombreUsuario -Expected $script:adminUsername -Message "Username de login incorrecto"
    Assert-True -Condition ($response.Json.usuario.roles -contains "SUPERADMIN") -Message "Rol de login incorrecto"
    Assert-Equal -Actual $response.Json.usuario.activo -Expected $true -Message "Usuario de login inactivo"
    $script:accessToken = [string]$response.Json.accessToken
    $script:refreshToken = Get-RefreshToken
    return $response.Json.usuario
}

function Login-Actor {
    param(
        [Parameter(Mandatory)][string] $Username,
        [Parameter(Mandatory)][string] $Password,
        [Parameter(Mandatory)][string] $ExpectedRole
    )

    $response = Invoke-Api -Method "POST" -Path "/login" -Body @{
        nombreUsuario = $Username
        contrasena = $Password
    } -Token $null -ExpectedStatus 200
    Assert-True -Condition ($response.Json.usuario.roles -contains $ExpectedRole) -Message "Rol de actor incorrecto"
    Assert-True -Condition (-not [string]::IsNullOrWhiteSpace($response.Json.accessToken)) -Message "Actor sin access token"
    return [string]$response.Json.accessToken
}

function Restart-Backend {
    Invoke-Compose -Arguments @("up", "-d", "--no-deps", "--force-recreate", "backend")
    Wait-ServiceHealthy -Service "backend"
}

function Show-Diagnostics {
    try {
        $ps = Invoke-Compose -Arguments @("ps", "-a") -Capture -IgnoreDeadline
        if ($ps) { Write-Host (Redact $ps) }
    }
    catch { Write-Host "No se pudo obtener docker compose ps." }
    try {
        $logs = Invoke-Compose -Arguments @("logs", "--tail", "120", "db", "backend", "frontend") -Capture -IgnoreDeadline
        if ($logs) { Write-Host (Redact $logs) }
    }
    catch { Write-Host "No se pudieron obtener logs sanitizados." }
}

$dbPort = Get-FreePort
$backendPort = Get-FreePort
$frontendPort = Get-FreePort
$postgresDb = "gestudio_smoke"
$postgresUser = "gestudio_smoke"
$postgresPassword = New-HexSecret 24
$jwtSecret = New-HexSecret 64
$adminPassword = New-HexSecret 24
$secretariaPassword = New-HexSecret 24
$cajaPassword = New-HexSecret 24
$limitedPassword = New-HexSecret 24
$adminUsername = "smoke-admin-$suffix"
$apiBase = "http://127.0.0.1:$backendPort/api"
$frontendOrigin = "http://127.0.0.1:$frontendPort"

try {
    Push-Location $repoRoot
    try {
        if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw "Docker no esta disponible en PATH" }
        Invoke-Docker -Arguments @("info", "--format", "{{.ServerVersion}}") | Out-Null
        Invoke-Docker -Arguments @("compose", "version") | Out-Null
        Pass "Docker disponible"

        $smokeEnvironment = [ordered]@{
            COMPOSE_PROJECT_NAME = $project
            POSTGRES_DB = $postgresDb
            POSTGRES_USER = $postgresUser
            POSTGRES_PASSWORD = $postgresPassword
            POSTGRES_PORT = $dbPort
            BACKEND_PORT = $backendPort
            FRONTEND_PORT = $frontendPort
            BACKEND_IMAGE = "gestudio-backend:smoke-check"
            FRONTEND_IMAGE = "gestudio-frontend:smoke-check"
            SPRING_PROFILES_ACTIVE = "dev"
            SPRING_JPA_HIBERNATE_DDL_AUTO = "validate"
            SPRING_FLYWAY_ENABLED = "true"
            SPRING_FLYWAY_BASELINE_ON_MIGRATE = "false"
            APP_SCHEDULING_ENABLED = "false"
            APP_BOOTSTRAP_SUPERADMIN_ENABLED = "true"
            APP_BOOTSTRAP_SUPERADMIN_USERNAME = $adminUsername
            APP_BOOTSTRAP_SUPERADMIN_PASSWORD = $adminPassword
            JWT_SECRET = $jwtSecret
            JWT_ISSUER = "gestudio-smoke"
            APP_TIME_ZONE = "America/Argentina/Buenos_Aires"
            APP_CORS_ALLOWED_ORIGINS = $frontendOrigin
            VITE_API_BASE_URL = $apiBase
            VITE_APP_TIME_ZONE = "America/Argentina/Buenos_Aires"
        }
        foreach ($entry in $smokeEnvironment.GetEnumerator()) {
            $originalEnvironment[$entry.Key] = [Environment]::GetEnvironmentVariable($entry.Key, "Process")
            [Environment]::SetEnvironmentVariable($entry.Key, [string]$entry.Value, "Process")
        }
        $envLines = $smokeEnvironment.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }
        Set-Content -LiteralPath $envFile -Value $envLines -Encoding ASCII
        Write-Host "[INFO] Proyecto: $project"
        Write-Host "[INFO] Puertos aislados: PostgreSQL=$dbPort backend=$backendPort frontend=$frontendPort"

        if (-not $SkipBuild) { Invoke-Compose -Arguments @("build") }
        $stackAttempted = $true
        Invoke-Compose -Arguments @("up", "-d", "db", "backend", "frontend")
        Wait-ServiceHealthy -Service "db"
        Wait-ServiceHealthy -Service "backend"
        Wait-ServiceHealthy -Service "frontend"
        $cookieContainer = [Net.CookieContainer]::new()
        $handler = [Net.Http.HttpClientHandler]::new()
        $handler.CookieContainer = $cookieContainer
        $http = [Net.Http.HttpClient]::new($handler, $true)
        $http.Timeout = [TimeSpan]::FromSeconds(30)
        $front = Invoke-SmokeHttp -Method "GET" -Uri "http://127.0.0.1:$frontendPort/" -Body $null -Token $null
        Assert-Equal -Actual $front.Status -Expected 200 -Message "Frontend no responde"
        Pass "Stack healthy"

        Assert-Equal -Actual (Invoke-Sql "SELECT count(*) FROM flyway_schema_history WHERE success") -Expected "7" -Message "Flyway no aplico V1-V7"
        Assert-Equal -Actual (Invoke-Sql "SELECT count(*) FROM flyway_schema_history WHERE version = '7' AND success") -Expected "1" -Message "Flyway V7 no esta aplicada"
        Assert-Equal -Actual (Invoke-Sql "SELECT count(*) FROM flyway_schema_history WHERE NOT success OR version::int NOT BETWEEN 1 AND 7") -Expected "0" -Message "Hay migraciones fallidas o inesperadas"
        $flywayChecksums = Invoke-Sql "SELECT 'V' || version, checksum::text FROM flyway_schema_history WHERE success AND version::int BETWEEN 1 AND 7 ORDER BY version::int"
        $v7Checksum = @($flywayChecksums -split "`r?`n" | Where-Object { $_ -match '^V7\|-?\d+$' })
        Assert-Equal -Actual $v7Checksum.Count -Expected 1 -Message "Flyway V7 no tiene un checksum registrado"
        Write-Host "[INFO] Flyway checksums V1-V7:`n$flywayChecksums"
        Assert-Equal -Actual (Invoke-Sql "SELECT count(*) FROM permisos") -Expected "32" -Message "Catalogo RBAC inesperado"
        Assert-Equal -Actual (Invoke-Sql "SELECT count(*) FROM permisos WHERE activo AND sistema") -Expected "32" -Message "Hay permisos productivos inactivos o no sistema"
        Assert-Equal -Actual (Invoke-Sql "SELECT count(*) FROM roles WHERE codigo = 'SUPERADMIN' AND activo") -Expected "1" -Message "Falta SUPERADMIN activo"
        Assert-Equal -Actual (Invoke-Sql "SELECT count(*) FROM roles WHERE codigo = 'SUPERADMIN' AND sistema AND NOT editable") -Expected "1" -Message "SUPERADMIN no esta protegido"
        Assert-Equal -Actual (Invoke-Sql "SELECT count(*) FROM roles WHERE codigo IN ('DIRECCION','ADMINISTRADOR','SECRETARIA','CAJA') AND activo AND sistema") -Expected "4" -Message "Roles base activos incompletos"
        Assert-Equal -Actual (Invoke-Sql "SELECT count(*) FROM roles WHERE codigo = 'PROFESOR' AND NOT activo AND sistema") -Expected "1" -Message "PROFESOR debe estar inactivo"
        $matrixDiff = Invoke-Sql "WITH expected(role_code, permission_code) AS (SELECT 'SUPERADMIN', codigo FROM permisos UNION ALL SELECT 'DIRECCION', codigo FROM permisos WHERE codigo <> 'PERM_ROLES_ADMIN' UNION ALL SELECT 'ADMINISTRADOR', codigo FROM permisos WHERE codigo <> 'PERM_ROLES_ADMIN' UNION ALL SELECT 'SECRETARIA', codigo FROM permisos WHERE codigo IN ('PERM_APP_ACCESO','PERM_PAGOS_REGISTRAR','PERM_CREDITOS_CONSUMIR','PERM_CONDICIONES_ECONOMICAS_ADMIN','PERM_ALUMNOS_LEER','PERM_ALUMNOS_ADMIN','PERM_INSCRIPCIONES_LEER','PERM_INSCRIPCIONES_ADMIN','PERM_DISCIPLINAS_LEER','PERM_PROFESORES_LEER','PERM_ASISTENCIAS_LEER','PERM_ASISTENCIAS_REGISTRAR','PERM_PAGOS_LEER','PERM_CAJA_LEER','PERM_STOCK_LEER','PERM_REPORTES_LEER','PERM_CONFIG_LEER') UNION ALL SELECT 'CAJA', codigo FROM permisos WHERE codigo IN ('PERM_APP_ACCESO','PERM_ALUMNOS_LEER','PERM_PAGOS_LEER','PERM_PAGOS_REGISTRAR','PERM_CAJA_LEER','PERM_STOCK_LEER','PERM_CONFIG_LEER','PERM_CREDITOS_CONSUMIR')), actual AS (SELECT r.codigo, p.codigo FROM roles r JOIN rol_permisos rp ON rp.rol_id=r.id JOIN permisos p ON p.id=rp.permiso_id WHERE r.codigo IN ('SUPERADMIN','DIRECCION','ADMINISTRADOR','SECRETARIA','CAJA','PROFESOR')), differences AS ((SELECT * FROM expected EXCEPT SELECT * FROM actual) UNION ALL (SELECT * FROM actual EXCEPT SELECT * FROM expected)) SELECT count(*) FROM differences"
        Assert-Equal -Actual $matrixDiff -Expected "0" -Message "La matriz de roles base no es exacta"
        Assert-Equal -Actual (Invoke-Sql "SELECT count(*) FROM usuarios WHERE nombre_usuario LIKE 'demo-%'") -Expected "0" -Message "El smoke no debe depender del seed demo"
        Pass "Flyway V1-V7 y matriz RBAC"

        $quotedUser = $adminUsername.Replace("'", "''")
        Assert-Equal -Actual (Invoke-Sql "SELECT count(*) FROM usuarios") -Expected "1" -Message "El bootstrap no creo exactamente un usuario"
        $bootstrap = Invoke-Sql "SELECT u.id, u.activo, r.descripcion, u.contrasena FROM usuarios u JOIN roles r ON r.id=u.rol_id WHERE u.nombre_usuario='$quotedUser'"
        $bootstrapParts = $bootstrap.Split("|")
        Assert-Equal -Actual $bootstrapParts.Count -Expected 4 -Message "Usuario bootstrap no encontrado"
        Assert-Equal -Actual $bootstrapParts[1] -Expected "t" -Message "Usuario bootstrap inactivo"
        Assert-Equal -Actual $bootstrapParts[2] -Expected "SUPERADMIN" -Message "Rol bootstrap incorrecto"
        Assert-Equal -Actual (Invoke-Sql "SELECT count(*) FROM usuario_roles ur JOIN roles r ON r.id=ur.rol_id WHERE ur.usuario_id=$($bootstrapParts[0]) AND r.codigo='SUPERADMIN'") -Expected "1" -Message "Bootstrap sin rol efectivo"
        Assert-True -Condition ($bootstrapParts[3] -ne $adminPassword) -Message "La password plana fue persistida"
        Assert-True -Condition ($bootstrapParts[3] -match '^\$2[aby]\$') -Message "La password persistida no es BCrypt"
        $adminId = [long]$bootstrapParts[0]
        Pass "Super admin creado"

        $anonymous = Invoke-Api -Method "GET" -Path "/usuarios/perfil" -Token $null -ExpectedStatus 401
        Assert-Equal -Actual $anonymous.Json.code -Expected "UNAUTHORIZED" -Message "Contrato anonimo incorrecto"
        $loginUser = Login
        Assert-Equal -Actual ([long]$loginUser.id) -Expected $adminId -Message "ID de login incorrecto"
        $profile = Invoke-Api -Method "GET" -Path "/usuarios/perfil" -ExpectedStatus 200
        Assert-Equal -Actual $profile.Json.nombreUsuario -Expected $adminUsername -Message "Perfil incorrecto"
        Assert-True -Condition ($profile.Json.roles -contains "SUPERADMIN") -Message "Rol de perfil incorrecto"
        Assert-Equal -Actual @($profile.Json.permisos).Count -Expected 32 -Message "Perfil SUPERADMIN sin catalogo completo"
        Invoke-Api -Method "GET" -Path "/alumnos?page=0&size=1" -ExpectedStatus 200 | Out-Null
        Pass "Login"

        Set-RefreshToken -Value $accessToken
        Invoke-Api -Method "POST" -Path "/login/refresh" -Token $null -ExpectedStatus 401 | Out-Null
        Set-RefreshToken -Value $refreshToken
        Invoke-Api -Method "GET" -Path "/usuarios/perfil" -Token $refreshToken -ExpectedStatus 401 | Out-Null
        $oldAccess = $accessToken
        $oldRefresh = $refreshToken
        $refreshed = Invoke-Api -Method "POST" -Path "/login/refresh" -Token $null -ExpectedStatus 200
        Assert-True -Condition ($refreshed.Json.accessToken -ne $oldAccess) -Message "Refresh no roto access token"
        $newRefresh = Get-RefreshToken
        Assert-True -Condition ($newRefresh -ne $oldRefresh) -Message "Refresh no roto refresh token"
        Assert-True -Condition ($refreshed.Json.usuario.roles -contains "SUPERADMIN") -Message "Rol de refresh incorrecto"
        $accessToken = [string]$refreshed.Json.accessToken
        $refreshToken = $newRefresh
        Pass "Refresh"

        (Get-Content -Raw $envFile).Replace("APP_BOOTSTRAP_SUPERADMIN_ENABLED=true", "APP_BOOTSTRAP_SUPERADMIN_ENABLED=false") |
            Set-Content -LiteralPath $envFile -Encoding ASCII
        [Environment]::SetEnvironmentVariable("APP_BOOTSTRAP_SUPERADMIN_ENABLED", "false", "Process")
        Restart-Backend
        Login | Out-Null
        Assert-Equal -Actual (Invoke-Sql "SELECT count(*) FROM usuarios") -Expected "1" -Message "El reinicio creo otro usuario"
        Pass "Bootstrap deshabilitado y reinicio"

        $salon = (Invoke-Api -Method "POST" -Path "/salones" -Body @{
            nombre = "Salon smoke $suffix"; descripcion = "Dato sintetico .test"
        } -ExpectedStatus 201).Json
        $profesor = (Invoke-Api -Method "POST" -Path "/profesores" -Body @{
            nombre = "Profesor-$suffix"; apellido = "Smoke"; fechaNacimiento = "1990-01-01"; telefono = "000000"
        } -ExpectedStatus 200).Json
        $disciplina = (Invoke-Api -Method "POST" -Path "/disciplinas" -Body @{
            nombre = "Disciplina-$suffix"; salonId = $salon.id; profesorId = $profesor.id
            valorCuota = "25.00"; matricula = "10.00"; claseSuelta = "5.00"; clasePrueba = "0.00"; horarios = @()
        } -ExpectedStatus 200).Json
        $tarifaBusinessNow = Get-BusinessNow
$tarifaVigenteDesde = [datetime]::new($tarifaBusinessNow.Year, 1, 1).ToString("yyyy-MM-dd")
$tarifa = (Invoke-Api -Method "POST" -Path "/disciplinas/$($disciplina.id)/tarifas" -Body @{
    vigenteDesde = $tarifaVigenteDesde; valorCuota = "25.00"; matricula = "10.00"
    claseSuelta = "5.00"; clasePrueba = "0.00"; motivo = "Tarifa efectiva smoke $suffix"
} -ExpectedStatus 201).Json
Assert-Equal -Actual $tarifa.vigenteDesde -Expected $tarifaVigenteDesde -Message "Tarifa inicial sin vigencia efectiva"
        $subconcepto = (Invoke-Api -Method "POST" -Path "/sub-conceptos" -Body @{
            id = $null; descripcion = "SMOKE-$suffix"
        } -ExpectedStatus 200).Json
        $concepto = (Invoke-Api -Method "POST" -Path "/conceptos" -Body @{
            descripcion = "Concepto smoke $suffix"; precio = "100.00"
            subConcepto = @{ id = $subconcepto.id; descripcion = $subconcepto.descripcion }; activo = $true
        } -ExpectedStatus 200).Json
        $metodo = (Invoke-Api -Method "POST" -Path "/metodos-pago" -Body @{
            id = $null; descripcion = "Metodo smoke $suffix"; activo = $true; recargo = "0.00"
        } -ExpectedStatus 201).Json
        $stockCreateKey = "stock-create-$suffix"
        $stock = (Invoke-Api -Method "POST" -Path "/stocks" -Body @{
            id = $null; nombre = "Producto smoke $suffix"; precio = "20.00"; stock = 5
            requiereControlDeStock = $true; activo = $true; codigoBarras = "SMOKE$suffix"; idempotencyKey = $stockCreateKey
        } -ExpectedStatus 200).Json

        $businessNow = Get-BusinessNow
        $today = $businessNow.ToString("yyyy-MM-dd")
        $alumnoName = "Alumno-$suffix"
        $alumno = (Invoke-Api -Method "POST" -Path "/alumnos" -Body @{
            id = $null; nombre = $alumnoName; apellido = "Smoke"; fechaNacimiento = "2000-01-01"
            fechaIncorporacion = $today; celular1 = "000000"; celular2 = $null
            email = "alumno-$suffix@example.test"; documento = "TEST-$suffix"; fechaDeBaja = $null
            nombrePadres = "Datos sinteticos"; autorizadoParaSalirSolo = $true; activo = $true
            otrasNotas = "Smoke local"; inscripciones = @()
        } -ExpectedStatus 200).Json
        Assert-True -Condition ([long]$alumno.id -gt 0) -Message "Alumno sin ID"
        Assert-Equal -Actual (Invoke-Api -Method "GET" -Path "/alumnos/$($alumno.id)" -ExpectedStatus 200).Json.email -Expected "alumno-$suffix@example.test" -Message "Alumno no persistido"
        $alumnos = (Invoke-Api -Method "GET" -Path "/alumnos?page=0&size=50" -ExpectedStatus 200).Json
        Assert-True -Condition (@($alumnos.content | Where-Object { $_.id -eq $alumno.id }).Count -eq 1) -Message "Alumno ausente del listado"
        $searchName = [Uri]::EscapeDataString($alumnoName)
        $search = (Invoke-Api -Method "GET" -Path "/alumnos/buscar?nombre=$searchName&page=0&size=50" -ExpectedStatus 200).Json
        Assert-True -Condition (@($search.content | Where-Object { $_.id -eq $alumno.id }).Count -eq 1) -Message "Alumno ausente de busqueda"
        Pass "Alumno"

        $inscripcionBody = @{
            id = $null; alumnoId = $alumno.id; disciplinaId = $disciplina.id
            fechaInscripcion = $today
        }
        $inscripcion = (Invoke-Api -Method "POST" -Path "/inscripciones" -Body $inscripcionBody -ExpectedStatus 201).Json
        Assert-Equal -Actual ([long]$inscripcion.alumnoId) -Expected ([long]$alumno.id) -Message "Alumno de inscripcion incorrecto"
        Assert-Equal -Actual ([long]$inscripcion.disciplinaId) -Expected ([long]$disciplina.id) -Message "Disciplina de inscripcion incorrecta"
        Assert-Equal -Actual $inscripcion.estado -Expected "ACTIVA" -Message "Estado inicial de inscripcion incorrecto"
        Invoke-Api -Method "POST" -Path "/inscripciones" -Body $inscripcionBody -ExpectedStatus 409 | Out-Null
        $inscripcionGet = Invoke-Api -Method "GET" -Path "/inscripciones/$($inscripcion.id)" -ExpectedStatus 200
        Assert-Equal -Actual ([long]$inscripcionGet.Json.id) -Expected ([long]$inscripcion.id) -Message "Inscripcion no persistida"
        $anio = $businessNow.Year
        $matricula = Invoke-Api -Method "GET" -Path "/matriculas/alumno/$($alumno.id)?anio=$anio" -ExpectedStatus 200
        Assert-Equal -Actual $matricula.Json.estado -Expected "EMITIDA" -Message "Matricula automatica ausente"
        Assert-Equal -Actual (Invoke-Sql "SELECT count(*) FROM cargo_liquidaciones l JOIN cargos c ON c.id=l.cargo_id LEFT JOIN mensualidades m ON m.id=c.mensualidad_id LEFT JOIN matriculas ma ON ma.id=c.matricula_id WHERE (m.inscripcion_id=$($inscripcion.id) OR ma.alumno_id=$($alumno.id)) AND l.formula_version=1 AND l.origen_precio='TARIFA_HISTORICA'") -Expected "2" -Message "Mensualidad y matricula no tienen snapshots historicos"
Assert-Equal -Actual (Invoke-Sql "SELECT c.importe_original FROM cargos c JOIN mensualidades m ON m.id=c.mensualidad_id WHERE m.inscripcion_id=$($inscripcion.id) AND m.anio=$anio AND m.mes=$($businessNow.Month)") -Expected "25.00" -Message "Mensualidad no uso tarifa efectiva"
Assert-Equal -Actual (Invoke-Sql "SELECT c.importe_original FROM cargos c JOIN matriculas m ON m.id=c.matricula_id WHERE m.alumno_id=$($alumno.id) AND m.anio=$anio") -Expected "10.00" -Message "Matricula no uso tarifa efectiva"
Pass "Inscripcion y liquidacion por vigencia"

        $cargoKey = "cargo-$suffix"
        $cargo = (Invoke-Api -Method "POST" -Path "/cargos/concepto" -Body @{
            alumnoId = $alumno.id; conceptoId = $concepto.id; fechaVencimiento = $businessNow.AddDays(10).ToString("yyyy-MM-dd")
            descripcion = "Cargo smoke $suffix"; idempotencyKey = $cargoKey
        } -ExpectedStatus 201).Json
        Assert-Equal -Actual $cargo.importeOriginal -Expected "100.00" -Message "Importe original incorrecto"
        Assert-Equal -Actual $cargo.saldo -Expected "100.00" -Message "Saldo inicial incorrecto"
        Assert-Equal -Actual $cargo.estado -Expected "PENDIENTE" -Message "Estado inicial de cargo incorrecto"
        Assert-Equal -Actual (Invoke-Api -Method "GET" -Path "/cargos/$($cargo.id)" -ExpectedStatus 200).Json.id -Expected $cargo.id -Message "Cargo no persistido"
        Pass "Cargo"

        $partialKey = "pago-parcial-$suffix"
        $partialBody = @{
            alumnoId = $alumno.id; metodoPagoId = $metodo.id; montoRecibido = "40.00"
            idempotencyKey = $partialKey; observaciones = "Pago parcial smoke"
            aplicaciones = @(@{ cargoId = $cargo.id; importe = "40.00" }); generarCredito = $false
        }
        $partial = (Invoke-Api -Method "POST" -Path "/pagos" -Body $partialBody -ExpectedStatus 201).Json
        Assert-Equal -Actual $partial.montoRecibido -Expected "40.00" -Message "Pago parcial incorrecto"
        Assert-Equal -Actual @($partial.aplicaciones).Count -Expected 1 -Message "Aplicacion parcial incorrecta"
        $cargoAfterPartial = (Invoke-Api -Method "GET" -Path "/cargos/$($cargo.id)" -ExpectedStatus 200).Json
        Assert-Equal -Actual $cargoAfterPartial.saldo -Expected "60.00" -Message "Saldo parcial incorrecto"
        Assert-Equal -Actual $cargoAfterPartial.estado -Expected "PARCIAL" -Message "Cargo no quedo parcial"
        Pass "Pago parcial"

        $partialRetry = (Invoke-Api -Method "POST" -Path "/pagos" -Body $partialBody -ExpectedStatus 201).Json
        Assert-Equal -Actual ([long]$partialRetry.id) -Expected ([long]$partial.id) -Message "Retry creo otro pago"
        $conflictingPartial = $partialBody.Clone()
        $conflictingPartial.montoRecibido = "41.00"
        $conflictingPartial.aplicaciones = @(@{ cargoId = $cargo.id; importe = "41.00" })
        Invoke-Api -Method "POST" -Path "/pagos" -Body $conflictingPartial -ExpectedStatus 409 | Out-Null
        Assert-Equal -Actual (Invoke-Sql "SELECT count(*) FROM pagos WHERE idempotency_key='$partialKey'") -Expected "1" -Message "Pago parcial duplicado"
        Assert-Equal -Actual (Invoke-Sql "SELECT count(*) FROM aplicaciones_pago WHERE pago_id=$($partial.id)") -Expected "1" -Message "Aplicacion parcial duplicada"
        Assert-Equal -Actual (Invoke-Sql "SELECT count(*) FROM movimientos_caja WHERE pago_id=$($partial.id) AND tipo='INGRESO_PAGO'") -Expected "1" -Message "Caja parcial duplicada"
        Pass "Idempotencia"

        $finalKey = "pago-final-$suffix"
        $finalPayment = (Invoke-Api -Method "POST" -Path "/pagos" -Body @{
            alumnoId = $alumno.id; metodoPagoId = $metodo.id; montoRecibido = "60.00"
            idempotencyKey = $finalKey; observaciones = "Pago final smoke"
            aplicaciones = @(@{ cargoId = $cargo.id; importe = "60.00" }); generarCredito = $false
        } -ExpectedStatus 201).Json
        $paidCargo = (Invoke-Api -Method "GET" -Path "/cargos/$($cargo.id)" -ExpectedStatus 200).Json
        Assert-Equal -Actual $paidCargo.saldo -Expected "0.00" -Message "Cargo no quedo en cero"
        Assert-Equal -Actual $paidCargo.estado -Expected "PAGADO" -Message "Cargo no quedo pagado"
        Assert-Equal -Actual $paidCargo.importeAplicado -Expected "100.00" -Message "Aplicacion total incorrecta"
        Pass "Pago total"

        foreach ($paymentId in @([long]$partial.id, [long]$finalPayment.id)) {
            Assert-Equal -Actual (Invoke-Sql "SELECT count(*) FROM recibos WHERE pago_id=$paymentId") -Expected "1" -Message "Recibo faltante"
            Assert-Equal -Actual (Invoke-Sql "SELECT count(*) FROM recibos_pendientes WHERE pago_id=$paymentId AND tipo='GENERAR_Y_ENVIAR' AND estado='PENDIENTE'") -Expected "1" -Message "Outbox faltante o incoherente"
        }
        Pass "Recibo/outbox"

        $caja = (Invoke-Api -Method "GET" -Path "/caja/resumen?desde=$today&hasta=$today&page=0&size=100" -ExpectedStatus 200).Json
        Assert-Equal -Actual $caja.totalIngresos -Expected "100.00" -Message "Ingresos de caja incorrectos"
        Assert-Equal -Actual $caja.saldo -Expected "100.00" -Message "Saldo de caja incorrecto"
        Assert-Equal -Actual @($caja.movimientos.content | Where-Object { $_.tipo -eq "INGRESO_PAGO" }).Count -Expected 2 -Message "Movimientos de pago incorrectos"
        $egreso = (Invoke-Api -Method "POST" -Path "/egresos" -Body @{
            fecha = $today; monto = "15.00"; observaciones = "Egreso smoke"; metodoPagoId = $metodo.id
            idempotencyKey = "egreso-$suffix"
        } -ExpectedStatus 200).Json
        $egresoReversal = @{ idempotencyKey = "egreso-reversal-$suffix"; motivo = "Reversion smoke" }
        Invoke-Api -Method "POST" -Path "/egresos/$($egreso.id)/anulacion" -Body $egresoReversal -ExpectedStatus 200 | Out-Null
        Invoke-Api -Method "POST" -Path "/egresos/$($egreso.id)/anulacion" -Body $egresoReversal -ExpectedStatus 200 | Out-Null
        $cajaAfterEgreso = (Invoke-Api -Method "GET" -Path "/caja/resumen?desde=$today&hasta=$today&page=0&size=100" -ExpectedStatus 200).Json
        Assert-Equal -Actual $cajaAfterEgreso.saldo -Expected "100.00" -Message "Reversion de egreso no recompuso caja"
        Pass "Caja"

        $saleKey = "venta-$suffix"
        $saleBody = @{
            alumnoId = $alumno.id; stockId = $stock.id; cantidad = 2
            fechaVencimiento = $businessNow.AddDays(10).ToString("yyyy-MM-dd"); idempotencyKey = $saleKey
        }
        $saleCargo = (Invoke-Api -Method "POST" -Path "/stocks/ventas" -Body $saleBody -ExpectedStatus 200).Json
        Assert-Equal -Actual $saleCargo.importeOriginal -Expected "40.00" -Message "Cargo de venta incorrecto"
        Assert-Equal -Actual (Invoke-Api -Method "GET" -Path "/stocks/$($stock.id)" -ExpectedStatus 200).Json.stock -Expected 3 -Message "Stock no descontado"
        $saleRetry = (Invoke-Api -Method "POST" -Path "/stocks/ventas" -Body $saleBody -ExpectedStatus 200).Json
        Assert-Equal -Actual $saleRetry.id -Expected $saleCargo.id -Message "Retry de venta duplico el cargo"
        $saleConflict = $saleBody.Clone(); $saleConflict.cantidad = 1
        Invoke-Api -Method "POST" -Path "/stocks/ventas" -Body $saleConflict -ExpectedStatus 409 | Out-Null
        $saleId = [long](Invoke-Sql "SELECT id FROM ventas_stock WHERE idempotency_key='$saleKey'")
        $reversalBody = @{ idempotencyKey = "venta-reversal-$suffix"; motivo = "Reversion smoke" }
        $reversedCargo = (Invoke-Api -Method "POST" -Path "/stocks/ventas/$saleId/reversion" -Body $reversalBody -ExpectedStatus 200).Json
        Assert-Equal -Actual $reversedCargo.estado -Expected "ANULADO" -Message "Cargo de venta no anulado"
        Assert-Equal -Actual (Invoke-Api -Method "GET" -Path "/stocks/$($stock.id)" -ExpectedStatus 200).Json.stock -Expected 5 -Message "Stock no restaurado"
        Invoke-Api -Method "POST" -Path "/stocks/ventas/$saleId/reversion" -Body $reversalBody -ExpectedStatus 200 | Out-Null
        $reversalConflict = @{ idempotencyKey = $reversalBody.idempotencyKey; motivo = "Otro motivo" }
        Invoke-Api -Method "POST" -Path "/stocks/ventas/$saleId/reversion" -Body $reversalConflict -ExpectedStatus 409 | Out-Null
        Assert-Equal -Actual (Invoke-Sql "SELECT count(*) FROM movimientos_stock WHERE venta_stock_id=$saleId AND tipo='REVERSO'") -Expected "1" -Message "Reversion de stock duplicada"
        Pass "Stock y reversion"

        $secretariaUsername = "smoke-secretaria-$suffix"
        $cajaUsername = "smoke-caja-$suffix"
        $limitedUsername = "smoke-limited-$suffix"
        $limitedRoleCode = "SMOKE_LIMITED_$($suffix.ToUpperInvariant())"
        Invoke-Api -Method "POST" -Path "/roles" -Body @{
            codigo = $limitedRoleCode; nombre = "Smoke limited $suffix"
            descripcionFuncional = "Actor sintetico para denegaciones"; permisos = @("PERM_APP_ACCESO")
        } -ExpectedStatus 201 | Out-Null
        Invoke-Api -Method "POST" -Path "/usuarios/registro" -Body @{
            nombreUsuario = $secretariaUsername; contrasena = $secretariaPassword; roles = @("SECRETARIA")
        } -ExpectedStatus 201 | Out-Null
        Invoke-Api -Method "POST" -Path "/usuarios/registro" -Body @{
            nombreUsuario = $cajaUsername; contrasena = $cajaPassword; roles = @("CAJA")
        } -ExpectedStatus 201 | Out-Null
        Invoke-Api -Method "POST" -Path "/usuarios/registro" -Body @{
            nombreUsuario = $limitedUsername; contrasena = $limitedPassword; roles = @($limitedRoleCode)
        } -ExpectedStatus 201 | Out-Null

        $secretariaToken = Login-Actor -Username $secretariaUsername -Password $secretariaPassword -ExpectedRole "SECRETARIA"
        $cajaToken = Login-Actor -Username $cajaUsername -Password $cajaPassword -ExpectedRole "CAJA"
        $limitedToken = Login-Actor -Username $limitedUsername -Password $limitedPassword -ExpectedRole $limitedRoleCode
        Invoke-Api -Method "GET" -Path "/roles" -Token $secretariaToken -ExpectedStatus 403 | Out-Null
        Invoke-Api -Method "POST" -Path "/pagos/$($partial.id)/anulacion" -Body @{
            idempotencyKey = "secretaria-anulacion-$suffix"; motivo = "Debe ser denegado"
        } -Token $secretariaToken -ExpectedStatus 403 | Out-Null
        Invoke-Api -Method "POST" -Path "/egresos" -Body @{
            fecha = $today; monto = "1.00"; observaciones = "Debe ser denegado"
            metodoPagoId = $metodo.id; idempotencyKey = "caja-egreso-$suffix"
        } -Token $cajaToken -ExpectedStatus 403 | Out-Null
        Invoke-Api -Method "POST" -Path "/stocks" -Body @{
            nombre = "Debe ser denegado"; precio = "1.00"; stock = 1
            requiereControlDeStock = $true; activo = $true; idempotencyKey = "caja-stock-$suffix"
        } -Token $cajaToken -ExpectedStatus 403 | Out-Null
        Invoke-Api -Method "GET" -Path "/alumnos?page=0&size=1" -Token $limitedToken -ExpectedStatus 403 | Out-Null
        Pass "Denegaciones RBAC por rol"

        Restart-Backend
        Login | Out-Null
        Assert-Equal -Actual (Invoke-Api -Method "GET" -Path "/alumnos/$($alumno.id)" -ExpectedStatus 200).Json.id -Expected $alumno.id -Message "Alumno perdido tras reinicio"
        Assert-Equal -Actual (Invoke-Api -Method "GET" -Path "/inscripciones/$($inscripcion.id)" -ExpectedStatus 200).Json.estado -Expected "ACTIVA" -Message "Inscripcion perdida tras reinicio"
        Assert-Equal -Actual (Invoke-Api -Method "GET" -Path "/cargos/$($cargo.id)" -ExpectedStatus 200).Json.estado -Expected "PAGADO" -Message "Cargo perdido tras reinicio"
        Assert-Equal -Actual (Invoke-Api -Method "GET" -Path "/pagos/$($partial.id)" -ExpectedStatus 200).Json.id -Expected $partial.id -Message "Pago perdido tras reinicio"
        Assert-Equal -Actual (Invoke-Api -Method "GET" -Path "/stocks/$($stock.id)" -ExpectedStatus 200).Json.stock -Expected 5 -Message "Stock incoherente tras reinicio"
        Assert-Equal -Actual (Invoke-Api -Method "GET" -Path "/caja/resumen?desde=$today&hasta=$today&page=0&size=100" -ExpectedStatus 200).Json.saldo -Expected "100.00" -Message "Caja incoherente tras reinicio"
        Assert-Equal -Actual (Invoke-Sql "SELECT estado FROM ventas_stock WHERE id=$saleId") -Expected "ANULADA" -Message "Reversion perdida tras reinicio"
        Pass "Persistencia tras reinicio"

        Assert-Equal -Actual (Invoke-Sql "SELECT count(*) FROM usuarios") -Expected "4" -Message "Cantidad final de usuarios incorrecta"
        $finalHash = Invoke-Sql "SELECT contrasena FROM usuarios WHERE nombre_usuario='$quotedUser'"
        Assert-True -Condition ($finalHash -ne $adminPassword -and $finalHash -match '^\$2[aby]\$') -Message "Hash final del bootstrap invalido"
        Assert-Equal -Actual (Invoke-Sql "SELECT count(*) FROM (SELECT idempotency_key FROM pagos GROUP BY idempotency_key HAVING count(*) <> 1) x") -Expected "0" -Message "Idempotencia de pagos inconsistente"
        Assert-Equal -Actual (Invoke-Sql "SELECT count(*) FROM aplicaciones_pago WHERE pago_id IN ($($partial.id),$($finalPayment.id))") -Expected "2" -Message "Cantidad final de aplicaciones incorrecta"
        Assert-Equal -Actual (Invoke-Sql "SELECT count(*) FROM stocks WHERE cantidad_actual < 0") -Expected "0" -Message "Stock negativo"
        Assert-Equal -Actual (Invoke-Sql "SELECT count(*) FROM (SELECT pago_id,tipo FROM recibos_pendientes GROUP BY pago_id,tipo HAVING count(*) > 1) x") -Expected "0" -Message "Outbox duplicado"
        Assert-Equal -Actual (Invoke-Sql "SELECT count(*) FROM flyway_schema_history WHERE NOT success OR version::int NOT BETWEEN 1 AND 7") -Expected "0" -Message "Historial Flyway final invalido"
        Assert-AuditZero -RelativePath "docs/refactor/sql/03-orphans.sql"
        Assert-AuditZero -RelativePath "docs/refactor/sql/04-financial-inconsistencies.sql"
        Assert-AuditZero -RelativePath "docs/refactor/sql/05-state-inconsistencies.sql"
        Pass "Integridad SQL"
    }
    finally { Pop-Location }
}
catch {
    $caught = $_
    $failures++
    Write-Host "[FAIL] $(Redact $_.Exception.Message)" -ForegroundColor Red
    if ($stackAttempted -and (Test-Path -LiteralPath $envFile)) { Show-Diagnostics }
}
finally {
    if ($null -ne $http) { $http.Dispose() }
    if ($KeepStack) {
        Write-Host "[INFO] Stack conservado: $project"
        Write-Host "[INFO] docker compose -p $project ps"
        Write-Host "[INFO] docker compose -p $project logs --tail 120"
        Write-Host "[INFO] docker compose -p $project down --volumes --remove-orphans"
    }
    elseif (Test-Path -LiteralPath $envFile) {
        try {
            Invoke-Compose -Arguments @("down", "--volumes", "--remove-orphans") -IgnoreDeadline
            $containers = Invoke-Docker -Arguments @("ps", "-a", "--filter", "label=com.docker.compose.project=$project", "-q") -Capture -IgnoreDeadline
            $volumes = Invoke-Docker -Arguments @("volume", "ls", "--filter", "label=com.docker.compose.project=$project", "-q") -Capture -IgnoreDeadline
            $networks = Invoke-Docker -Arguments @("network", "ls", "--filter", "label=com.docker.compose.project=$project", "-q") -Capture -IgnoreDeadline
            Assert-True -Condition ([string]::IsNullOrWhiteSpace($containers)) -Message "Quedaron contenedores del smoke"
            Assert-True -Condition ([string]::IsNullOrWhiteSpace($volumes)) -Message "Quedaron volumenes del smoke"
            Assert-True -Condition ([string]::IsNullOrWhiteSpace($networks)) -Message "Quedaron redes del smoke"
            Pass "Limpieza"
        }
        catch {
            $failures++
            if ($null -eq $caught) { $caught = $_ }
            Write-Host "[FAIL] Limpieza: $(Redact $_.Exception.Message)" -ForegroundColor Red
        }
    }
    if (Test-Path -LiteralPath $envFile) { Remove-Item -LiteralPath $envFile -Force }
    foreach ($entry in $originalEnvironment.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, "Process")
    }
    $accessToken = $null
    $refreshToken = $null
    $adminPassword = $null
    $secretariaPassword = $null
    $cajaPassword = $null
    $limitedPassword = $null
    $jwtSecret = $null
    $postgresPassword = $null
}

$duration = (Get-Date) - $startedAt
Write-Host ""
Write-Host "Duracion total: $($duration.ToString('hh\:mm\:ss'))"
Write-Host "Pasos aprobados: $passes"
Write-Host "Fallos: $failures"
Write-Host "Resultado global: $(if ($failures -eq 0) { 'PASS' } else { 'FAIL' })"

if ($null -ne $caught -or $failures -ne 0) { exit 1 }
