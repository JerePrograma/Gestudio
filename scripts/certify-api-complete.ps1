param(
    [string] $RepoPath = "C:\laburo\Gestudio",
    [string] $PublicOrigin = "https://gestudio-demo-jere-287b8c90.pages.dev",
    [string] $Username = "demo-superadmin",
    [string] $ReportDirectory = "",
    [switch] $SkipIsolatedLifecycle,
    [switch] $SkipPublic,
    [switch] $VerboseHttp
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Net.Http

$repoRoot = [IO.Path]::GetFullPath($RepoPath)
$publicOriginNormalized = $PublicOrigin.TrimEnd("/")
$apiBase = "$publicOriginNormalized/api"
$startedAt = [DateTimeOffset]::Now
$runId = $startedAt.ToString("yyyyMMdd-HHmmss") + "-" + ([Guid]::NewGuid().ToString("N").Substring(0, 8))
$reportRoot = if ([string]::IsNullOrWhiteSpace($ReportDirectory)) {
    Join-Path ([Environment]::GetFolderPath("MyDocuments")) "Gestudio-Certifications"
} else {
    [IO.Path]::GetFullPath($ReportDirectory)
}
$jsonReportPath = Join-Path $reportRoot "api-certification-$runId.json"
$markdownReportPath = Join-Path $reportRoot "api-certification-$runId.md"
$results = [Collections.Generic.List[object]]::new()
$phases = [Collections.Generic.List[object]]::new()
$passwordSecure = $null
$password = $null
$accessToken = $null
$http = $null
$cookieContainer = $null
$failure = $null
$gitHead = ""

function Redact {
    param([AllowNull()][string] $Text)

    if ($null -eq $Text) { return "" }
    $safe = $Text
    foreach ($secret in @($script:password, $script:accessToken)) {
        if (-not [string]::IsNullOrEmpty($secret)) {
            $safe = $safe.Replace($secret, "<redacted>")
        }
    }
    return $safe
}

function Pass {
    param([Parameter(Mandatory)][string] $Name, [string] $Detail = "")

    $suffix = if ([string]::IsNullOrWhiteSpace($Detail)) { "" } else { " - $Detail" }
    Write-Host "[PASS] $Name$suffix" -ForegroundColor Green
}

function Info {
    param([Parameter(Mandatory)][string] $Message)

    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Resolve-NativeCommand {
    param([Parameter(Mandatory)][string[]] $Names)

    foreach ($name in $Names) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($null -ne $command) { return $command.Source }
    }
    throw "No se encontró ningún comando requerido: $($Names -join ', ')"
}

function Invoke-Native {
    param(
        [Parameter(Mandatory)][string] $FilePath,
        [Parameter(Mandatory)][string[]] $Arguments,
        [switch] $Capture
    )

    $previous = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        if ($Capture) {
            $output = @(& $FilePath @Arguments 2>&1)
            $code = $LASTEXITCODE
            $text = ($output | ForEach-Object { $_.ToString() }) -join "`n"
        } else {
            $tail = [Collections.Generic.Queue[string]]::new()
            & $FilePath @Arguments 2>&1 | ForEach-Object {
                $line = Redact $_.ToString()
                Write-Host $line
                $tail.Enqueue($line)
                if ($tail.Count -gt 100) { [void]$tail.Dequeue() }
            }
            $code = $LASTEXITCODE
            $text = @($tail) -join "`n"
        }
    } finally {
        $ErrorActionPreference = $previous
    }

    if ($code -ne 0) {
        $tailText = (($text -split "`r?`n") | Select-Object -Last 100) -join "`n"
        throw "$([IO.Path]::GetFileName($FilePath)) falló con código ${code}: $(Redact $tailText)"
    }
    if ($Capture) { return $text.Trim() }
}

function Add-Phase {
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $Status,
        [Parameter(Mandatory)][DateTimeOffset] $Started,
        [string] $Detail = ""
    )

    $script:phases.Add([pscustomobject]@{
        name = $Name
        status = $Status
        durationMs = [long]([DateTimeOffset]::Now - $Started).TotalMilliseconds
        detail = $Detail
    })
}

function Assert-GitContract {
    $git = Resolve-NativeCommand -Names @("git.exe", "git")
    $root = Invoke-Native -FilePath $git -Arguments @("-C", $repoRoot, "rev-parse", "--show-toplevel") -Capture
    $trim = [char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    if ([IO.Path]::GetFullPath($root).TrimEnd($trim) -ne $repoRoot.TrimEnd($trim)) {
        throw "El repositorio resuelto no corresponde a $repoRoot"
    }

    $branch = Invoke-Native -FilePath $git -Arguments @("-C", $repoRoot, "branch", "--show-current") -Capture
    if ($branch -ne "main") { throw "La rama actual debe ser main; actual=$branch" }

    $status = Invoke-Native -FilePath $git -Arguments @("-C", $repoRoot, "status", "--porcelain=v1") -Capture
    if (-not [string]::IsNullOrWhiteSpace($status)) {
        throw "Existen cambios locales versionables:`n$status"
    }

    Invoke-Native -FilePath $git -Arguments @("-C", $repoRoot, "fetch", "origin", "--prune")
    $head = Invoke-Native -FilePath $git -Arguments @("-C", $repoRoot, "rev-parse", "HEAD") -Capture
    $originMain = Invoke-Native -FilePath $git -Arguments @("-C", $repoRoot, "rev-parse", "origin/main") -Capture
    if ($head -ne $originMain) {
        throw "main local no coincide con origin/main. HEAD=$head origin/main=$originMain"
    }
    $script:gitHead = $head
    Pass "Git" "main limpia y sincronizada en $head"
}

function Invoke-VerificationSuites {
    $phaseStarted = [DateTimeOffset]::Now
    $mvn = Join-Path $repoRoot "backend/mvnw.cmd"
    if (-not (Test-Path -LiteralPath $mvn -PathType Leaf)) { throw "Falta $mvn" }

    Push-Location (Join-Path $repoRoot "backend")
    try {
        Invoke-Native -FilePath $mvn -Arguments @(
            "-B", "-ntp",
            "-Dtest=SecurityHttpIntegrationTest,RemoteDemoProxyTokenFilterTest,RemoteDemoPublicDeploymentContractTest",
            "test"
        )
    } finally {
        Pop-Location
    }
    Add-Phase -Name "Inventario y seguridad de todos los endpoints" -Status "PASS" -Started $phaseStarted -Detail "SecurityHttpIntegrationTest descubre y recorre todos los mappings REST"
    Pass "Inventario/RBAC" "todos los mappings reales cubiertos por la matriz dinámica"
}

function Invoke-IsolatedLifecycle {
    if ($SkipIsolatedLifecycle) {
        Add-Phase -Name "Ciclo funcional PostgreSQL aislado" -Status "SKIPPED" -Started ([DateTimeOffset]::Now) -Detail "Omitido por parámetro"
        return
    }

    $phaseStarted = [DateTimeOffset]::Now
    $pwsh = Resolve-NativeCommand -Names @("pwsh.exe", "pwsh")
    $smoke = Join-Path $repoRoot "scripts/smoke-local.ps1"
    if (-not (Test-Path -LiteralPath $smoke -PathType Leaf)) { throw "Falta $smoke" }

    $arguments = @("-NoProfile", "-File", $smoke)
    if ($VerboseHttp) { $arguments += "-VerboseHttp" }
    Invoke-Native -FilePath $pwsh -Arguments $arguments

    Add-Phase -Name "Ciclo funcional PostgreSQL aislado" -Status "PASS" -Started $phaseStarted -Detail "Altas, liquidación, pagos, caja, egresos, stock, reversión, idempotencia, RBAC, reinicio e integridad SQL"
    Pass "Ciclo funcional aislado" "datos sintéticos y recursos destruidos al finalizar"
}

function New-PublicHttpClient {
    $script:cookieContainer = [Net.CookieContainer]::new()
    $handler = [Net.Http.HttpClientHandler]::new()
    $handler.CookieContainer = $script:cookieContainer
    $handler.UseCookies = $true
    $handler.AllowAutoRedirect = $false
    $script:http = [Net.Http.HttpClient]::new($handler, $true)
    $script:http.Timeout = [TimeSpan]::FromSeconds(45)
}

function Invoke-PublicRequest {
    param(
        [Parameter(Mandatory)][string] $Scenario,
        [Parameter(Mandatory)][ValidateSet("GET", "POST", "PUT", "DELETE", "OPTIONS")][string] $Method,
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][int[]] $ExpectedStatuses,
        $Body = $null,
        [hashtable] $Headers = @{},
        [switch] $Anonymous,
        [switch] $RequireJson
    )

    $uri = if ($Path.StartsWith("http", [StringComparison]::OrdinalIgnoreCase)) { $Path } else { "$publicOriginNormalized$Path" }
    $request = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::new($Method), $uri)
    $requestId = "cert-$runId-" + ([Guid]::NewGuid().ToString("N").Substring(0, 10))
    [void]$request.Headers.TryAddWithoutValidation("X-Request-ID", $requestId)

    if (-not $Anonymous -and -not [string]::IsNullOrWhiteSpace($script:accessToken)) {
        $request.Headers.Authorization = [Net.Http.Headers.AuthenticationHeaderValue]::new("Bearer", $script:accessToken)
    }
    foreach ($entry in $Headers.GetEnumerator()) {
        [void]$request.Headers.TryAddWithoutValidation([string]$entry.Key, [string]$entry.Value)
    }
    if ($null -ne $Body) {
        $json = $Body | ConvertTo-Json -Depth 20 -Compress
        $request.Content = [Net.Http.StringContent]::new($json, [Text.Encoding]::UTF8, "application/json")
    }

    $started = [Diagnostics.Stopwatch]::StartNew()
    try {
        $response = $script:http.SendAsync($request).GetAwaiter().GetResult()
        try {
            $raw = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            $contentType = if ($null -eq $response.Content.Headers.ContentType) { "" } else { [string]$response.Content.Headers.ContentType.MediaType }
            $responseRequestId = if ($response.Headers.Contains("X-Request-ID")) {
                $response.Headers.GetValues("X-Request-ID") -join ","
            } else { "" }
            $status = [int]$response.StatusCode
            $script:results.Add([pscustomobject]@{
                phase = "PUBLIC"
                scenario = $Scenario
                method = $Method
                path = $Path
                status = $status
                durationMs = $started.ElapsedMilliseconds
                contentType = $contentType
                requestId = $responseRequestId
            })

            if ($status -notin $ExpectedStatuses) {
                $safeBody = Redact (($raw -replace "`r|`n", " ").Substring(0, [Math]::Min(500, $raw.Length)))
                throw "$Method $Path devolvió $status; esperado=$($ExpectedStatuses -join ', '); body=$safeBody"
            }
            if ($status -ge 500) { throw "$Method $Path devolvió un 5xx no permitido: $status" }
            if ($RequireJson -and $contentType -notmatch "(?i)application/json") {
                throw "$Method $Path no respondió JSON; content-type=$contentType"
            }
            if ($VerboseHttp) { Write-Host "[HTTP] $Method $Path -> $status" }

            $parsed = $null
            if (-not [string]::IsNullOrWhiteSpace($raw) -and $contentType -match "(?i)application/json") {
                try { $parsed = $raw | ConvertFrom-Json -Depth 100 } catch { }
            }
            return [pscustomobject]@{ Status = $status; Body = $raw; Json = $parsed; ContentType = $contentType }
        } finally {
            $response.Dispose()
        }
    } finally {
        $started.Stop()
        $request.Dispose()
    }
}

function First-Item {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value.PSObject.Properties.Name -contains "content") { return @($Value.content) | Select-Object -First 1 }
    return @($Value) | Select-Object -First 1
}

function Invoke-PublicCertification {
    if ($SkipPublic) {
        Add-Phase -Name "Demo pública" -Status "SKIPPED" -Started ([DateTimeOffset]::Now) -Detail "Omitida por parámetro"
        return
    }

    $phaseStarted = [DateTimeOffset]::Now
    $script:passwordSecure = Read-Host "Contraseña de $Username para la certificación pública" -AsSecureString
    $script:password = [Net.NetworkCredential]::new("", $script:passwordSecure).Password
    if ([string]::IsNullOrWhiteSpace($script:password)) { throw "La contraseña no puede estar vacía" }

    New-PublicHttpClient
    [void](Invoke-PublicRequest -Scenario "Frontend público" -Method GET -Path $publicOriginNormalized -ExpectedStatuses @(200) -Anonymous)
    [void](Invoke-PublicRequest -Scenario "CORS login" -Method OPTIONS -Path "/api/login" -ExpectedStatuses @(200, 204) -Headers @{
        Origin = $publicOriginNormalized
        "Access-Control-Request-Method" = "POST"
        "Access-Control-Request-Headers" = "content-type"
    } -Anonymous)

    $login = Invoke-PublicRequest -Scenario "Login SUPERADMIN" -Method POST -Path "/api/login" -ExpectedStatuses @(200) -Body @{
        nombreUsuario = $Username
        contrasena = $script:password
    } -Anonymous -RequireJson
    if ($null -eq $login.Json -or [string]::IsNullOrWhiteSpace([string]$login.Json.accessToken)) {
        throw "Login público sin access token"
    }
    $script:accessToken = [string]$login.Json.accessToken
    if (@($login.Json.usuario.roles) -notcontains "SUPERADMIN") { throw "La cuenta pública no posee SUPERADMIN" }

    [void](Invoke-PublicRequest -Scenario "Perfil autenticado" -Method GET -Path "/api/usuarios/perfil" -ExpectedStatuses @(200) -RequireJson)
    $refresh = Invoke-PublicRequest -Scenario "Rotación refresh" -Method POST -Path "/api/login/refresh" -ExpectedStatuses @(200) -Headers @{ Origin = $publicOriginNormalized } -Body @{} -Anonymous -RequireJson
    if ($null -eq $refresh.Json -or [string]::IsNullOrWhiteSpace([string]$refresh.Json.accessToken)) { throw "Refresh público sin access token" }
    $script:accessToken = [string]$refresh.Json.accessToken

    $users = (Invoke-PublicRequest -Scenario "Usuarios" -Method GET -Path "/api/usuarios?activo=true" -ExpectedStatuses @(200) -RequireJson).Json
    [void](Invoke-PublicRequest -Scenario "Roles asignables" -Method GET -Path "/api/usuarios/roles-asignables" -ExpectedStatuses @(200) -RequireJson)
    $roles = (Invoke-PublicRequest -Scenario "Roles" -Method GET -Path "/api/roles" -ExpectedStatuses @(200) -RequireJson).Json
    $permissions = (Invoke-PublicRequest -Scenario "Permisos" -Method GET -Path "/api/permisos" -ExpectedStatuses @(200) -RequireJson).Json
    $studentsPage = (Invoke-PublicRequest -Scenario "Alumnos paginados" -Method GET -Path "/api/alumnos?page=0&size=50" -ExpectedStatuses @(200) -RequireJson).Json
    $professors = (Invoke-PublicRequest -Scenario "Profesores" -Method GET -Path "/api/profesores" -ExpectedStatuses @(200) -RequireJson).Json
    [void](Invoke-PublicRequest -Scenario "Profesores activos" -Method GET -Path "/api/profesores/activos" -ExpectedStatuses @(200) -RequireJson)
    $disciplines = (Invoke-PublicRequest -Scenario "Disciplinas" -Method GET -Path "/api/disciplinas" -ExpectedStatuses @(200) -RequireJson).Json
    [void](Invoke-PublicRequest -Scenario "Disciplinas resumidas" -Method GET -Path "/api/disciplinas/listado" -ExpectedStatuses @(200) -RequireJson)
    $roomsPage = (Invoke-PublicRequest -Scenario "Salones" -Method GET -Path "/api/salones?page=0&size=50" -ExpectedStatuses @(200) -RequireJson).Json
    $bonuses = (Invoke-PublicRequest -Scenario "Bonificaciones" -Method GET -Path "/api/bonificaciones" -ExpectedStatuses @(200) -RequireJson).Json
    $surcharges = (Invoke-PublicRequest -Scenario "Recargos" -Method GET -Path "/api/recargos" -ExpectedStatuses @(200) -RequireJson).Json
    $methods = (Invoke-PublicRequest -Scenario "Métodos de pago" -Method GET -Path "/api/metodos-pago" -ExpectedStatuses @(200) -RequireJson).Json
    $subconcepts = (Invoke-PublicRequest -Scenario "Subconceptos" -Method GET -Path "/api/sub-conceptos" -ExpectedStatuses @(200) -RequireJson).Json
    $concepts = (Invoke-PublicRequest -Scenario "Conceptos" -Method GET -Path "/api/conceptos" -ExpectedStatuses @(200) -RequireJson).Json
    $stockPage = (Invoke-PublicRequest -Scenario "Stock paginado" -Method GET -Path "/api/stocks?page=0&size=50" -ExpectedStatuses @(200) -RequireJson).Json
    [void](Invoke-PublicRequest -Scenario "Stock activo" -Method GET -Path "/api/stocks/activos" -ExpectedStatuses @(200) -RequireJson)
    $enrollmentsPage = (Invoke-PublicRequest -Scenario "Inscripciones" -Method GET -Path "/api/inscripciones?page=0&size=50&filtro=" -ExpectedStatuses @(200) -RequireJson).Json
    $attendanceSheets = (Invoke-PublicRequest -Scenario "Planillas de asistencia" -Method GET -Path "/api/asistencias-mensuales" -ExpectedStatuses @(200) -RequireJson).Json
    $expensesPage = (Invoke-PublicRequest -Scenario "Egresos" -Method GET -Path "/api/egresos?page=0&size=50" -ExpectedStatuses @(200) -RequireJson).Json
    $today = [DateTimeOffset]::Now.ToString("yyyy-MM-dd")
    $yearStart = [DateTime]::new([DateTimeOffset]::Now.Year, 1, 1).ToString("yyyy-MM-dd")
    [void](Invoke-PublicRequest -Scenario "Cargos vencidos" -Method GET -Path "/api/cargos/vencidos?page=0&size=50" -ExpectedStatuses @(200) -RequireJson)
    [void](Invoke-PublicRequest -Scenario "Caja" -Method GET -Path "/api/caja/resumen?desde=$yearStart&hasta=$today&page=0&size=50" -ExpectedStatuses @(200) -RequireJson)
    [void](Invoke-PublicRequest -Scenario "Reporte mensualidades" -Method GET -Path "/api/reportes/mensualidades?desde=$yearStart&hasta=$today" -ExpectedStatuses @(200) -RequireJson)
    [void](Invoke-PublicRequest -Scenario "Cumpleaños" -Method GET -Path "/api/notificaciones/cumpleaneros" -ExpectedStatuses @(200) -RequireJson)

    $student = First-Item $studentsPage
    $professor = First-Item $professors
    $discipline = First-Item $disciplines
    $room = First-Item $roomsPage
    $bonus = First-Item $bonuses
    $surcharge = First-Item $surcharges
    $method = First-Item $methods
    $subconcept = First-Item $subconcepts
    $concept = First-Item $concepts
    $stock = First-Item $stockPage
    $enrollment = First-Item $enrollmentsPage
    $role = First-Item $roles
    $user = First-Item $users
    $expense = First-Item $expensesPage

    if ($null -eq $student -or $null -eq $discipline -or $null -eq $professor) {
        throw "El seed público no contiene alumno, disciplina y profesor para pruebas relacionadas"
    }

    [void](Invoke-PublicRequest -Scenario "Alumno por ID" -Method GET -Path "/api/alumnos/$($student.id)" -ExpectedStatuses @(200) -RequireJson)
    $studentSearch = [Uri]::EscapeDataString([string]$student.nombre)
    [void](Invoke-PublicRequest -Scenario "Buscar alumno" -Method GET -Path "/api/alumnos/buscar?nombre=$studentSearch&page=0&size=20" -ExpectedStatuses @(200) -RequireJson)
    [void](Invoke-PublicRequest -Scenario "Disciplinas del alumno" -Method GET -Path "/api/alumnos/$($student.id)/disciplinas" -ExpectedStatuses @(200) -RequireJson)
    [void](Invoke-PublicRequest -Scenario "Inscripciones activas del alumno" -Method GET -Path "/api/inscripciones/alumno/$($student.id)/activas" -ExpectedStatuses @(200) -RequireJson)
    $pending = (Invoke-PublicRequest -Scenario "Cargos pendientes del alumno" -Method GET -Path "/api/cargos/alumno/$($student.id)/pendientes?page=0&size=50" -ExpectedStatuses @(200) -RequireJson).Json
    $payments = (Invoke-PublicRequest -Scenario "Pagos del alumno" -Method GET -Path "/api/pagos/alumno/$($student.id)?page=0&size=50" -ExpectedStatuses @(200) -RequireJson).Json
    [void](Invoke-PublicRequest -Scenario "Saldo de crédito" -Method GET -Path "/api/creditos/alumno/$($student.id)/saldo" -ExpectedStatuses @(200))
    [void](Invoke-PublicRequest -Scenario "Matrícula anual" -Method GET -Path "/api/matriculas/alumno/$($student.id)?anio=$([DateTimeOffset]::Now.Year)" -ExpectedStatuses @(200, 404) -RequireJson)

    [void](Invoke-PublicRequest -Scenario "Profesor por ID" -Method GET -Path "/api/profesores/$($professor.id)" -ExpectedStatuses @(200) -RequireJson)
    $professorSearch = [Uri]::EscapeDataString([string]$professor.nombre)
    [void](Invoke-PublicRequest -Scenario "Buscar profesor" -Method GET -Path "/api/profesores/buscar?nombre=$professorSearch" -ExpectedStatuses @(200) -RequireJson)
    [void](Invoke-PublicRequest -Scenario "Disciplinas del profesor" -Method GET -Path "/api/profesores/$($professor.id)/disciplinas" -ExpectedStatuses @(200) -RequireJson)
    [void](Invoke-PublicRequest -Scenario "Alumnos del profesor" -Method GET -Path "/api/profesores/$($professor.id)/alumnos" -ExpectedStatuses @(200) -RequireJson)

    [void](Invoke-PublicRequest -Scenario "Disciplina por ID" -Method GET -Path "/api/disciplinas/$($discipline.id)" -ExpectedStatuses @(200) -RequireJson)
    $disciplineSearch = [Uri]::EscapeDataString([string]$discipline.nombre)
    [void](Invoke-PublicRequest -Scenario "Buscar disciplina" -Method GET -Path "/api/disciplinas/buscar?nombre=$disciplineSearch" -ExpectedStatuses @(200) -RequireJson)
    [void](Invoke-PublicRequest -Scenario "Disciplinas por fecha" -Method GET -Path "/api/disciplinas/por-fecha?fecha=$today" -ExpectedStatuses @(200) -RequireJson)
    [void](Invoke-PublicRequest -Scenario "Disciplinas por horario" -Method GET -Path "/api/disciplinas/por-horario?horario=18%3A00" -ExpectedStatuses @(200) -RequireJson)
    [void](Invoke-PublicRequest -Scenario "Alumnos de disciplina" -Method GET -Path "/api/disciplinas/$($discipline.id)/alumnos" -ExpectedStatuses @(200) -RequireJson)
    [void](Invoke-PublicRequest -Scenario "Profesor de disciplina" -Method GET -Path "/api/disciplinas/$($discipline.id)/profesor" -ExpectedStatuses @(200, 404) -RequireJson)
    [void](Invoke-PublicRequest -Scenario "Tarifas de disciplina" -Method GET -Path "/api/disciplinas/$($discipline.id)/tarifas" -ExpectedStatuses @(200) -RequireJson)
    [void](Invoke-PublicRequest -Scenario "PDF alumnos por disciplina" -Method GET -Path "/api/disciplinas/$($discipline.id)/alumnos/pdf" -ExpectedStatuses @(200))

    foreach ($entity in @(
        @{ Name = "Usuario por ID"; Path = if ($null -eq $user) { $null } else { "/api/usuarios/$($user.id)" } },
        @{ Name = "Rol por ID"; Path = if ($null -eq $role) { $null } else { "/api/roles/$($role.id)" } },
        @{ Name = "Salón por ID"; Path = if ($null -eq $room) { $null } else { "/api/salones/$($room.id)" } },
        @{ Name = "Bonificación por ID"; Path = if ($null -eq $bonus) { $null } else { "/api/bonificaciones/$($bonus.id)" } },
        @{ Name = "Recargo por ID"; Path = if ($null -eq $surcharge) { $null } else { "/api/recargos/$($surcharge.id)" } },
        @{ Name = "Método por ID"; Path = if ($null -eq $method) { $null } else { "/api/metodos-pago/$($method.id)" } },
        @{ Name = "Subconcepto por ID"; Path = if ($null -eq $subconcept) { $null } else { "/api/sub-conceptos/$($subconcept.id)" } },
        @{ Name = "Concepto por ID"; Path = if ($null -eq $concept) { $null } else { "/api/conceptos/$($concept.id)" } },
        @{ Name = "Stock por ID"; Path = if ($null -eq $stock) { $null } else { "/api/stocks/$($stock.id)" } },
        @{ Name = "Inscripción por ID"; Path = if ($null -eq $enrollment) { $null } else { "/api/inscripciones/$($enrollment.id)" } },
        @{ Name = "Egreso por ID"; Path = if ($null -eq $expense) { $null } else { "/api/egresos/$($expense.id)" } }
    )) {
        if (-not [string]::IsNullOrWhiteSpace([string]$entity.Path)) {
            [void](Invoke-PublicRequest -Scenario $entity.Name -Method GET -Path $entity.Path -ExpectedStatuses @(200) -RequireJson)
        }
    }

    if ($null -ne $subconcept) {
        [void](Invoke-PublicRequest -Scenario "Conceptos por subconcepto" -Method GET -Path "/api/conceptos/sub-concepto/$($subconcept.id)" -ExpectedStatuses @(200) -RequireJson)
        $subSearch = [Uri]::EscapeDataString([string]$subconcept.descripcion)
        [void](Invoke-PublicRequest -Scenario "Buscar subconcepto" -Method GET -Path "/api/sub-conceptos/buscar?nombre=$subSearch" -ExpectedStatuses @(200) -RequireJson)
    }
    if ($null -ne $enrollment) {
        [void](Invoke-PublicRequest -Scenario "Condiciones económicas" -Method GET -Path "/api/inscripciones/$($enrollment.id)/condiciones-economicas" -ExpectedStatuses @(200) -RequireJson)
        [void](Invoke-PublicRequest -Scenario "Mensualidades por inscripción" -Method GET -Path "/api/mensualidades/inscripcion/$($enrollment.id)" -ExpectedStatuses @(200) -RequireJson)
    }
    $cargo = First-Item $pending
    if ($null -ne $cargo) {
        [void](Invoke-PublicRequest -Scenario "Cargo por ID" -Method GET -Path "/api/cargos/$($cargo.id)" -ExpectedStatuses @(200) -RequireJson)
    }
    $payment = First-Item $payments
    if ($null -ne $payment) {
        [void](Invoke-PublicRequest -Scenario "Pago por ID" -Method GET -Path "/api/pagos/$($payment.id)" -ExpectedStatuses @(200) -RequireJson)
        [void](Invoke-PublicRequest -Scenario "Recibo PDF" -Method GET -Path "/api/pagos/recibo/$($payment.id)" -ExpectedStatuses @(200, 404))
    }

    $sheet = First-Item $attendanceSheets
    if ($null -ne $sheet) {
        [void](Invoke-PublicRequest -Scenario "Detalle planilla" -Method GET -Path "/api/asistencias-mensuales/por-disciplina/detalle?disciplinaId=$($sheet.disciplina.id)&mes=$($sheet.mes)&anio=$($sheet.anio)" -ExpectedStatuses @(200) -RequireJson)
        [void](Invoke-PublicRequest -Scenario "Asistencias diarias de planilla" -Method GET -Path "/api/asistencias-diarias/por-asistencia-mensual/$($sheet.id)" -ExpectedStatuses @(200) -RequireJson)
    }
    [void](Invoke-PublicRequest -Scenario "Asistencias por disciplina y fecha" -Method GET -Path "/api/asistencias-diarias/por-disciplina-y-fecha?disciplinaId=$($discipline.id)&fecha=$today&page=0&size=20" -ExpectedStatuses @(200) -RequireJson)

    [void](Invoke-PublicRequest -Scenario "Reporte PDF" -Method POST -Path "/api/reportes/mensualidades/exportar" -ExpectedStatuses @(200) -Body @{
        fechaInicio = $yearStart
        fechaFin = $today
        disciplinaId = $null
        profesorId = $null
        porcentajeEscuela = "50.00"
    })

    [void](Invoke-PublicRequest -Scenario "Logout" -Method POST -Path "/api/login/logout" -ExpectedStatuses @(204) -Headers @{ Origin = $publicOriginNormalized } -Body @{} -Anonymous)
    $script:accessToken = $null
    [void](Invoke-PublicRequest -Scenario "Refresh revocado" -Method POST -Path "/api/login/refresh" -ExpectedStatuses @(401) -Headers @{ Origin = $publicOriginNormalized } -Body @{} -Anonymous -RequireJson)

    Add-Phase -Name "Demo pública" -Status "PASS" -Started $phaseStarted -Detail "$($script:results.Count) solicitudes públicas; datos existentes; sin mutaciones de negocio"
    Pass "Demo pública" "$($script:results.Count) comprobaciones sin 5xx"
}

function Write-Reports {
    New-Item -ItemType Directory -Path $reportRoot -Force | Out-Null
    $endedAt = [DateTimeOffset]::Now
    $globalStatus = if ($null -eq $script:failure) { "PASS" } else { "FAIL" }
    $report = [ordered]@{
        schemaVersion = 1
        runId = $runId
        status = $globalStatus
        startedAt = $startedAt.ToString("o")
        endedAt = $endedAt.ToString("o")
        durationMs = [long]($endedAt - $startedAt).TotalMilliseconds
        gitHead = $gitHead
        publicOrigin = $publicOriginNormalized
        username = $Username
        phases = @($phases)
        requests = @($results)
        failure = if ($null -eq $script:failure) { $null } else { Redact $script:failure.Exception.Message }
        secretsPersisted = $false
    }
    [IO.File]::WriteAllText($jsonReportPath, ($report | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))

    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add("# Certificación integral de API Gestudio")
    $lines.Add("")
    $lines.Add("- Ejecución: ``$runId``")
    $lines.Add("- Resultado: **$globalStatus**")
    $lines.Add("- Commit: ``$gitHead``")
    $lines.Add("- Origin público: ``$publicOriginNormalized``")
    $lines.Add("- Inicio: ``$($startedAt.ToString('o'))``")
    $lines.Add("- Fin: ``$($endedAt.ToString('o'))``")
    $lines.Add("")
    $lines.Add("## Fases")
    $lines.Add("")
    $lines.Add("| Fase | Estado | Duración ms | Detalle |")
    $lines.Add("|---|---:|---:|---|")
    foreach ($phase in $phases) {
        $lines.Add("| $($phase.name) | $($phase.status) | $($phase.durationMs) | $($phase.detail -replace '\|', '\|') |")
    }
    $lines.Add("")
    $lines.Add("## Solicitudes públicas")
    $lines.Add("")
    $lines.Add("| Escenario | Método | Ruta | HTTP | ms | Content-Type | Request ID |")
    $lines.Add("|---|---:|---|---:|---:|---|---|")
    foreach ($result in $results) {
        $lines.Add("| $($result.scenario) | $($result.method) | ``$($result.path)`` | $($result.status) | $($result.durationMs) | $($result.contentType) | ``$($result.requestId)`` |")
    }
    if ($null -ne $script:failure) {
        $lines.Add("")
        $lines.Add("## Fallo")
        $lines.Add("")
        $lines.Add("``$(Redact $script:failure.Exception.Message)``")
    }
    $lines.Add("")
    $lines.Add("El informe no contiene contraseñas, access tokens, refresh cookies ni secretos de infraestructura.")
    [IO.File]::WriteAllLines($markdownReportPath, $lines, [Text.UTF8Encoding]::new($false))
}

try {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw "La certificación operativa está preparada para Windows y PowerShell 7"
    }
    foreach ($path in @($repoRoot, (Join-Path $repoRoot "backend"), (Join-Path $repoRoot "scripts/smoke-local.ps1"))) {
        if (-not (Test-Path -LiteralPath $path)) { throw "Falta ruta requerida: $path" }
    }

    Assert-GitContract
    Invoke-VerificationSuites
    Invoke-IsolatedLifecycle
    Invoke-PublicCertification
} catch {
    $failure = $_
    Add-Phase -Name "Ejecución" -Status "FAIL" -Started $startedAt -Detail (Redact $_.Exception.Message)
    Write-Host "[FAIL] $(Redact $_.Exception.Message)" -ForegroundColor Red
} finally {
    if ($null -ne $http) { $http.Dispose() }
    $accessToken = $null
    $password = $null
    $passwordSecure = $null
    Write-Reports
    Write-Host ""
    Write-Host "Informe JSON: $jsonReportPath"
    Write-Host "Informe Markdown: $markdownReportPath"
}

if ($null -ne $failure) { exit 1 }
Write-Host ""
Pass "CERTIFICACIÓN INTEGRAL" "inventario/RBAC, ciclo real aislado y demo pública"
