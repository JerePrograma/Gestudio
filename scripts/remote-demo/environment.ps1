function Read-EnvironmentFile {
    if (-not (Test-Path -LiteralPath $script:envPath -PathType Leaf)) {
        throw "Falta $($script:envPath). Copie .env.remote-demo.example y complete los valores locales."
    }

    $values = @{}
    $lineNumber = 0
    foreach ($rawLine in [IO.File]::ReadAllLines($script:envPath)) {
        $lineNumber++
        $line = $rawLine.Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) { continue }

        $separator = $rawLine.IndexOf("=")
        if ($separator -lt 1) { throw "Línea inválida en .env.remote-demo:${lineNumber}" }
        $name = $rawLine.Substring(0, $separator).Trim()
        $value = $rawLine.Substring($separator + 1).Trim()
        if ($name -notmatch '^[A-Z][A-Z0-9_]*$') {
            throw "Nombre de variable inválido en .env.remote-demo:${lineNumber}"
        }
        if ($values.ContainsKey($name)) {
            throw "Variable duplicada en .env.remote-demo: $name"
        }
        if ($value.Length -ge 2 -and (($value.StartsWith('"') -and $value.EndsWith('"')) -or
                ($value.StartsWith("'") -and $value.EndsWith("'")))) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        $values[$name] = $value
    }
    $script:environmentValues = $values

    foreach ($secretName in @("POSTGRES_PASSWORD", "JWT_SECRET", "APP_OBSERVABILITY_METRICS_TOKEN")) {
        if ($values.ContainsKey($secretName)) { Add-Secret ([string]$values[$secretName]) }
    }
}

function Get-EnvironmentValue {
    param(
        [Parameter(Mandatory)][string] $Name,
        [switch] $AllowEmpty
    )

    if (-not $script:environmentValues.ContainsKey($Name)) {
        throw "Falta la variable $Name en .env.remote-demo"
    }
    $value = [string]$script:environmentValues[$Name]
    if (-not $AllowEmpty -and [string]::IsNullOrWhiteSpace($value)) {
        throw "$Name no puede estar vacía"
    }
    return $value
}

function Assert-BooleanValue {
    param([Parameter(Mandatory)][string] $Name, [Parameter(Mandatory)][bool] $Expected)

    $raw = Get-EnvironmentValue -Name $Name
    $parsed = $false
    if (-not [bool]::TryParse($raw, [ref]$parsed) -or $parsed -ne $Expected) {
        throw "$Name debe ser $($Expected.ToString().ToLowerInvariant())"
    }
}

function Assert-PublicOrigin {
    param([Parameter(Mandatory)][string] $Value)

    if ($Value.Contains(",") -or $Value.Contains("*") -or $Value -match '(?i)REPLACE_WITH|\.invalid(?:$|[/:])|<|>') {
        throw "APP_CORS_ALLOWED_ORIGINS debe contener un único origin HTTPS real y explícito"
    }
    $uri = $null
    if (-not [Uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$uri)) {
        throw "APP_CORS_ALLOWED_ORIGINS no es un origin válido"
    }
    if ($uri.Scheme -ne "https" -or [string]::IsNullOrWhiteSpace($uri.Host) -or
            -not [string]::IsNullOrWhiteSpace($uri.UserInfo) -or
            -not [string]::IsNullOrWhiteSpace($uri.Query) -or
            -not [string]::IsNullOrWhiteSpace($uri.Fragment) -or
            $uri.AbsolutePath -ne "/") {
        throw "APP_CORS_ALLOWED_ORIGINS debe ser HTTPS y no incluir path, credenciales, query ni fragmento"
    }
}

function Assert-EnvironmentContract {
    Read-EnvironmentFile

    foreach ($name in @(
        "SPRING_PROFILES_ACTIVE", "SPRING_JPA_HIBERNATE_DDL_AUTO", "SPRING_FLYWAY_ENABLED",
        "POSTGRES_DB", "POSTGRES_USER", "POSTGRES_PASSWORD", "JWT_SECRET", "JWT_ISSUER",
        "JWT_ACCESS_TOKEN_TTL", "JWT_REFRESH_TOKEN_TTL", "APP_TIME_ZONE", "APP_RECEIPTS_PATH",
        "APP_CORS_ALLOWED_ORIGINS", "APP_OBSERVABILITY_METRICS_TOKEN",
        "APP_SECURITY_REFRESH_COOKIE_NAME", "APP_SECURITY_REFRESH_COOKIE_SECURE",
        "APP_SECURITY_REFRESH_COOKIE_SAME_SITE", "APP_SECURITY_REFRESH_COOKIE_DOMAIN",
        "APP_SECURITY_REFRESH_COOKIE_PATH", "APP_SCHEDULING_ENABLED",
        "APP_BOOTSTRAP_SUPERADMIN_ENABLED", "APP_LOCAL_ADMIN_PASSWORD_RESET_ENABLED",
        "APP_JERE_PLATFORM_STUDENT_EXPORT_ENABLED", "SERVER_PORT", "BACKEND_PORT", "BACKEND_IMAGE",
        "COMPOSE_PROJECT_NAME"
    )) {
        [void](Get-EnvironmentValue -Name $name -AllowEmpty:($name -eq "APP_SECURITY_REFRESH_COOKIE_DOMAIN"))
    }

    Assert-Equal (Get-EnvironmentValue "SPRING_PROFILES_ACTIVE") "remote-demo" "Perfil Spring remoto incorrecto"
    Assert-Equal (Get-EnvironmentValue "SPRING_JPA_HIBERNATE_DDL_AUTO") "validate" "ddl-auto remoto incorrecto"
    Assert-BooleanValue "SPRING_FLYWAY_ENABLED" $true
    Assert-BooleanValue "APP_SCHEDULING_ENABLED" $false
    Assert-BooleanValue "APP_BOOTSTRAP_SUPERADMIN_ENABLED" $false
    Assert-BooleanValue "APP_LOCAL_ADMIN_PASSWORD_RESET_ENABLED" $false
    Assert-BooleanValue "APP_JERE_PLATFORM_STUDENT_EXPORT_ENABLED" $false
    Assert-BooleanValue "APP_SECURITY_REFRESH_COOKIE_SECURE" $true
    Assert-Equal (Get-EnvironmentValue "APP_SECURITY_REFRESH_COOKIE_SAME_SITE") "Strict" "SameSite remoto incorrecto"
    Assert-Equal (Get-EnvironmentValue "APP_SECURITY_REFRESH_COOKIE_DOMAIN" -AllowEmpty) "" "La cookie remota debe ser host-only"
    Assert-Equal (Get-EnvironmentValue "APP_SECURITY_REFRESH_COOKIE_PATH") "/api/login" "Path de cookie remoto incorrecto"
    Assert-Equal (Get-EnvironmentValue "APP_TIME_ZONE") "America/Argentina/Buenos_Aires" "Zona horaria remota incorrecta"
    Assert-Equal (Get-EnvironmentValue "APP_RECEIPTS_PATH") "/app/data/receipts" "Ruta de recibos remota inesperada"
    Assert-Equal (Get-EnvironmentValue "COMPOSE_PROJECT_NAME") $script:project "COMPOSE_PROJECT_NAME remoto incorrecto"
    Assert-Equal (Get-EnvironmentValue "POSTGRES_DB") "gestudio_remote_demo" "POSTGRES_DB remoto incorrecto"
    Assert-Equal (Get-EnvironmentValue "POSTGRES_USER") "gestudio_remote_demo" "POSTGRES_USER remoto incorrecto"
    Assert-Equal (Get-EnvironmentValue "JWT_ISSUER") "gestudio-remote-demo" "JWT_ISSUER remoto incorrecto"
    Assert-Equal (Get-EnvironmentValue "JWT_REFRESH_TOKEN_TTL") "P1D" "JWT_REFRESH_TOKEN_TTL remoto incorrecto"
    Assert-Equal (Get-EnvironmentValue "APP_SECURITY_REFRESH_COOKIE_NAME") "gestudio_remote_demo_refresh" "Nombre de cookie remoto incorrecto"
    Assert-Equal (Get-EnvironmentValue "SERVER_PORT") "8080" "SERVER_PORT remoto incorrecto"
    Assert-Equal (Get-EnvironmentValue "BACKEND_PORT") "18080" "BACKEND_PORT remoto incorrecto"

    foreach ($name in @("POSTGRES_PASSWORD", "JWT_SECRET", "APP_OBSERVABILITY_METRICS_TOKEN")) {
        $value = Get-EnvironmentValue $name
        if ($value -match '(?i)REPLACE_WITH|CHANGE[_-]?ME|<|>') {
            throw "$name todavía contiene un placeholder"
        }
    }

    $databasePassword = Get-EnvironmentValue "POSTGRES_PASSWORD"
    if ([Text.Encoding]::UTF8.GetByteCount($databasePassword) -lt 16) {
        throw "POSTGRES_PASSWORD debe tener al menos 16 bytes UTF-8"
    }
    $jwtSecret = Get-EnvironmentValue "JWT_SECRET"
    if ([Text.Encoding]::UTF8.GetByteCount($jwtSecret) -lt 32) {
        throw "JWT_SECRET debe tener al menos 32 bytes UTF-8"
    }
    $metricsToken = Get-EnvironmentValue "APP_OBSERVABILITY_METRICS_TOKEN"
    if ([Text.Encoding]::UTF8.GetByteCount($metricsToken) -lt 32) {
        throw "APP_OBSERVABILITY_METRICS_TOKEN debe tener al menos 32 bytes UTF-8"
    }
    if ($jwtSecret -eq $metricsToken) {
        throw "JWT_SECRET y APP_OBSERVABILITY_METRICS_TOKEN deben ser independientes"
    }

    $databaseName = Get-EnvironmentValue "POSTGRES_DB"
    $databaseUser = Get-EnvironmentValue "POSTGRES_USER"
    if ($databaseName -notmatch '^[A-Za-z0-9_.-]+$' -or $databaseUser -notmatch '^[A-Za-z0-9_.-]+$') {
        throw "POSTGRES_DB y POSTGRES_USER sólo pueden contener letras, números, punto, guion o guion bajo"
    }

    $backendPort = 0
    if (-not [int]::TryParse((Get-EnvironmentValue "BACKEND_PORT"), [ref]$backendPort) -or
            $backendPort -lt 1 -or $backendPort -gt 65535) {
        throw "BACKEND_PORT debe estar entre 1 y 65535"
    }
    Assert-PublicOrigin (Get-EnvironmentValue "APP_CORS_ALLOWED_ORIGINS")

    $defaultEnvPath = [IO.Path]::GetFullPath((Join-Path $script:repoRoot ".env.remote-demo"))
    if ([IO.Path]::GetFullPath($script:envPath) -eq $defaultEnvPath -and (Get-Command git -ErrorAction SilentlyContinue)) {
        $tracked = @(& git -C $script:repoRoot ls-files --error-unmatch .env.remote-demo 2>$null)
        if ($LASTEXITCODE -eq 0 -and $tracked.Count -gt 0) {
            throw ".env.remote-demo está versionado; elimínelo del índice antes de continuar"
        }
        & git -C $script:repoRoot check-ignore --quiet .env.remote-demo
        if ($LASTEXITCODE -ne 0) {
            throw ".env.remote-demo no está ignorado por Git"
        }
    }

    Pass "Entorno remoto" "perfil, secretos, CORS y cookie cumplen el contrato"
}

function Assert-Prerequisites {
    foreach ($required in @($script:composeFile, $script:remoteComposeFile, $script:seedPath, $script:migrationRoot, $script:backendRoot)) {
        if (-not (Test-Path -LiteralPath $required)) { throw "Falta recurso requerido: $required" }
    }
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw "Docker no está disponible en PATH" }
    Invoke-Docker -Arguments @("info", "--format", "{{.ServerVersion}}") -Capture | Out-Null
    Invoke-Docker -Arguments @("compose", "version") -Capture | Out-Null
    Invoke-Compose -Arguments @("config", "--quiet") -Capture | Out-Null
    Pass "Prerequisitos" "Docker, Compose y configuración remota disponibles"
}

function Get-ServiceState {
    param([Parameter(Mandatory)][string] $Service)

    $id = Invoke-Compose -Arguments @("ps", "-a", "-q", $Service) -Capture -IgnoreDeadline
    if ([string]::IsNullOrWhiteSpace($id)) {
        return [pscustomobject]@{ Service = $Service; State = "absent"; Health = "n/a"; Id = "" }
    }
    $id = (($id -split "`r?`n")[0]).Trim()
    $state = Invoke-Docker -Arguments @(
        "inspect", "--format", "{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}", $id
    ) -Capture -IgnoreDeadline
    $parts = $state.Split("|")
    return [pscustomobject]@{ Service = $Service; State = $parts[0]; Health = $parts[1]; Id = $id }
}

function Wait-ServiceHealthy {
    param([Parameter(Mandatory)][string] $Service)

    while ((Get-Date) -lt $script:deadline) {
        $state = Get-ServiceState $Service
        if ($state.State -eq "running" -and $state.Health -eq "healthy") { return }
        if ($state.State -in @("exited", "dead")) { throw "$Service terminó antes de estar healthy" }
        Start-Sleep -Seconds 2
    }
    throw "Timeout esperando $Service healthy"
}

function Assert-PortAvailable {
    param([Parameter(Mandatory)][int] $Port)

    $containers = Invoke-Docker -Arguments @(
        "ps", "--filter", "publish=$Port", "--format", "{{.ID}}|{{.Names}}|{{.Label `"com.docker.compose.project`"}}"
    ) -Capture
    $foreign = @($containers -split "`r?`n" | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_) -and $_.Split("|")[-1] -ne $script:project
    })
    if ($foreign.Count -gt 0) {
        throw "BACKEND_PORT $Port está ocupado por otro contenedor: $($foreign[0])"
    }
    if (-not [string]::IsNullOrWhiteSpace($containers)) { return }

    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $Port)
    try { $listener.Start() }
    catch [Net.Sockets.SocketException] { throw "BACKEND_PORT $Port está ocupado por un proceso del host" }
    finally { $listener.Stop() }
}

function Assert-NetworkExposure {
    $db = Get-ServiceState "db"
    $backend = Get-ServiceState "backend"
    if ([string]::IsNullOrWhiteSpace($db.Id) -or [string]::IsNullOrWhiteSpace($backend.Id)) {
        throw "No se pudieron resolver los contenedores remotos"
    }

    $dbBindingsJson = Invoke-Docker -Arguments @("inspect", "--format", "{{json .HostConfig.PortBindings}}", $db.Id) -Capture
    if (-not [string]::IsNullOrWhiteSpace($dbBindingsJson) -and $dbBindingsJson -ne "null" -and $dbBindingsJson -ne "{}") {
        $dbBindings = $dbBindingsJson | ConvertFrom-Json
        foreach ($property in $dbBindings.PSObject.Properties) {
            if (@($property.Value).Count -gt 0) { throw "PostgreSQL tiene un puerto publicado: $($property.Name)" }
        }
    }

    $backendBindingsJson = Invoke-Docker -Arguments @("inspect", "--format", "{{json .HostConfig.PortBindings}}", $backend.Id) -Capture
    $backendBindings = $backendBindingsJson | ConvertFrom-Json
    $httpBindingProperty = $backendBindings.PSObject.Properties["8080/tcp"]
    if ($null -eq $httpBindingProperty) { throw "El backend no publica 8080/tcp" }
    $bindings = @($httpBindingProperty.Value)
    Assert-Equal $bindings.Count 1 "El backend debe tener un único binding"
    Assert-Equal ([string]$bindings[0].HostIp) "127.0.0.1" "El backend remoto debe estar ligado sólo a loopback"
    Assert-Equal ([string]$bindings[0].HostPort) (Get-EnvironmentValue "BACKEND_PORT") "Puerto backend publicado inesperado"
    Pass "Aislamiento de red" "PostgreSQL sin puerto y backend sólo en 127.0.0.1"
}

