param(
    [switch] $SkipBackendBuild,
    [switch] $VerboseHttp
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Net.Http

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$backendRoot = Join-Path $repoRoot "backend"
$composeFile = Join-Path $repoRoot "docker-compose.yml"
$seedPath = Join-Path $repoRoot "scripts/gestudio_demo_seed_full.sql"
$migrationRoot = Join-Path $backendRoot "src/main/resources/db/migration"
$startedAt = Get-Date
$deadline = $startedAt.AddMinutes(35)
$suffix = ([Guid]::NewGuid().ToString("N")).Substring(0, 10)
$project = "gestudio-demo-seed-$PID-$suffix"
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) $project
$receiptsRoot = Join-Path $tempRoot "receipts"
$backendStdout = Join-Path $tempRoot "backend.stdout.log"
$backendStderr = Join-Path $tempRoot "backend.stderr.log"
$results = [Collections.Generic.List[object]]::new()
$secretValues = [Collections.Generic.List[string]]::new()
$originalEnvironment = @{}
$backendProcess = $null
$stackAttempted = $false
$http = $null
$cookieContainer = $null
$exitCode = 0
$caughtMessage = $null
$isWindowsHost = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT

$dbPort = $null
$backendPort = $null
$postgresDb = "gestudio_demo_$suffix"
$postgresUser = "gestudio_demo_$suffix"
$postgresPassword = $null
$jwtSecret = $null
$anchorDate = $null
$apiBase = $null
$frontendOrigin = $null
$javaHome = $null
$javaExe = $null
$javacExe = $null
$mavenWrapper = $null
$backendJar = $null
$bcryptClasspath = $null
$demoPasswords = @{}
$demoHashes = @{}
$actorTokens = @{}

function Add-Result {
    param(
        [Parameter(Mandatory)][string] $Stage,
        [Parameter(Mandatory)][ValidateSet("PASS", "FAIL", "INFO")][string] $Result,
        [Parameter(Mandatory)][string] $Detail
    )

    $script:results.Add([pscustomobject]@{
        Etapa = $Stage
        Resultado = $Result
        Detalle = $Detail
    })

    $color = switch ($Result) {
        "PASS" { "Green" }
        "FAIL" { "Red" }
        default { "Cyan" }
    }
    Write-Host "[$Result] $Stage - $Detail" -ForegroundColor $color
}

function Add-Secret {
    param([AllowNull()][string] $Value)

    if (-not [string]::IsNullOrEmpty($Value) -and -not $script:secretValues.Contains($Value)) {
        $script:secretValues.Add($Value)
    }
}

function Redact {
    param([AllowNull()][string] $Text)

    if ($null -eq $Text) { return "" }
    $safe = $Text
    foreach ($secret in $script:secretValues) {
        if (-not [string]::IsNullOrEmpty($secret)) {
            $safe = $safe.Replace($secret, "<redacted>")
        }
    }
    return $safe
}

function Assert-Deadline {
    if ((Get-Date) -gt $script:deadline) {
        throw "Se agotó el timeout global de 35 minutos"
    }
}

function Assert-True {
    param(
        [Parameter(Mandatory)][bool] $Condition,
        [Parameter(Mandatory)][string] $Message
    )

    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param(
        $Actual,
        $Expected,
        [Parameter(Mandatory)][string] $Message
    )

    if ($Actual -ne $Expected) {
        throw "$Message (esperado=$Expected, actual=$Actual)"
    }
}

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

function Get-BusinessDate {
    try {
        $zone = [TimeZoneInfo]::FindSystemTimeZoneById("America/Argentina/Buenos_Aires")
    }
    catch {
        $zone = [TimeZoneInfo]::FindSystemTimeZoneById("Argentina Standard Time")
    }

    return [TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $zone).Date
}

function Set-ScopedEnvironmentVariable {
    param(
        [Parameter(Mandatory)][string] $Name,
        [AllowNull()][string] $Value
    )

    if (-not $script:originalEnvironment.ContainsKey($Name)) {
        $script:originalEnvironment[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process")
    }
    [Environment]::SetEnvironmentVariable($Name, $Value, "Process")
}

function Restore-Environment {
    foreach ($entry in $script:originalEnvironment.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, "Process")
    }
}

function Invoke-Native {
    param(
        [Parameter(Mandatory)][string] $FilePath,
        [Parameter(Mandatory)][string[]] $Arguments,
        [switch] $Capture,
        [switch] $IgnoreDeadline
    )

    if (-not $IgnoreDeadline) { Assert-Deadline }
    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = @(& $FilePath @Arguments 2>&1)
        $code = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousErrorAction }

    $text = ($output | ForEach-Object { $_.ToString() }) -join "`n"
    if ($code -ne 0) {
        $tail = (($text -split "`r?`n") | Select-Object -Last 80) -join "`n"
        throw "El comando $([IO.Path]::GetFileName($FilePath)) falló con código ${code}: $(Redact $tail)"
    }

    if ($Capture) { return $text.Trim() }
    if (-not [string]::IsNullOrWhiteSpace($text)) { Write-Host (Redact $text) }
}

function Invoke-Docker {
    param(
        [Parameter(Mandatory)][string[]] $Arguments,
        [switch] $Capture,
        [switch] $IgnoreDeadline
    )

    return Invoke-Native -FilePath "docker" -Arguments $Arguments -Capture:$Capture -IgnoreDeadline:$IgnoreDeadline
}

function Invoke-Compose {
    param(
        [Parameter(Mandatory)][string[]] $Arguments,
        [switch] $Capture,
        [switch] $IgnoreDeadline
    )

    $all = @("compose", "-f", $script:composeFile, "-p", $script:project) + $Arguments
    return Invoke-Docker -Arguments $all -Capture:$Capture -IgnoreDeadline:$IgnoreDeadline
}

function Wait-DatabaseHealthy {
    while ((Get-Date) -lt $script:deadline) {
        $containerId = Invoke-Compose -Arguments @("ps", "-q", "db") -Capture
        if (-not [string]::IsNullOrWhiteSpace($containerId)) {
            $state = Invoke-Docker -Arguments @(
                "inspect", "--format",
                "{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{end}}",
                $containerId
            ) -Capture
            if ($state -eq "running|healthy") { return }
            if ($state.StartsWith("exited|") -or $state.StartsWith("dead|")) {
                throw "PostgreSQL terminó antes de estar healthy"
            }
        }
        Start-Sleep -Seconds 2
    }
    throw "Timeout esperando PostgreSQL healthy"
}

function Invoke-Sql {
    param([Parameter(Mandatory)][string] $Query)

    Assert-Deadline
    $arguments = @(
        "compose", "-f", $script:composeFile, "-p", $script:project,
        "exec", "-T", "db", "psql",
        "-v", "ON_ERROR_STOP=1",
        "-U", $script:postgresUser,
        "-d", $script:postgresDb,
        "-A", "-t", "-F", "|",
        "-c", $Query
    )

    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = @(& docker @arguments 2>&1)
        $code = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousErrorAction }

    $text = ($output | ForEach-Object { $_.ToString() }) -join "`n"
    if ($code -ne 0) {
        throw "La consulta SQL falló: $(Redact $text)"
    }
    return $text.Trim()
}

function Assert-SqlZero {
    param(
        [Parameter(Mandatory)][string] $Stage,
        [Parameter(Mandatory)][string] $Query
    )

    $actual = Invoke-Sql -Query $Query
    Assert-Equal -Actual $actual -Expected "0" -Message "Falló la regla de integridad: $Stage"
    Add-Result -Stage $Stage -Result "PASS" -Detail "0 inconsistencias"
}

function Assert-SeedStaticContract {
    $seed = [IO.File]::ReadAllText($script:seedPath)

    foreach ($requiredText in @(
        "ESTE ARCHIVO NO ES UNA MIGRACIÓN FLYWAY",
        "\set ON_ERROR_STOP on",
        "BEGIN;",
        "COMMIT;"
    )) {
        if (-not $seed.Contains($requiredText)) {
            throw "El seed no contiene el contrato obligatorio: $requiredText"
        }
    }

    $forbiddenPatterns = [ordered]@{
        '(?im)^\s*(INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+(?:public\.)?(roles|permisos|rol_permisos)\b' = "El seed intenta modificar el RBAC productivo"
        '(?im)^\s*(INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+(?:public\.)?(refresh_sessions|bootstrap_ejecuciones|auditoria_eventos|cargo_eventos|notificaciones)\b' = "El seed intenta poblar tablas derivadas de servicios productivos"
        '(?im)^\s*TRUNCATE\b' = "El seed contiene TRUNCATE"
        '(?im)^\s*ALTER\s+TABLE\b' = "El seed intenta alterar el esquema"
        '(?im)^\s*DROP\s+SCHEMA\b' = "El seed intenta eliminar un esquema"
        '(?im)^\s*SET\s+session_replication_role\b' = "El seed intenta desactivar integridad referencial"
        '(?im)^\s*ALTER\s+TABLE\b.*DISABLE\s+TRIGGER\b' = "El seed intenta desactivar triggers"
        '(?i)admin[/]admin' = "El seed contiene una credencial conocida"
        '(?i)V6__.*demo.*seed|V6__.*seed.*demo' = "El seed se presenta como una migración V6 demo"
        '(?<!\\)\$2[aby]\$[0-9]{2}\$[./A-Za-z0-9]{53}' = "El seed contiene un hash BCrypt fijo"
    }

    foreach ($entry in $forbiddenPatterns.GetEnumerator()) {
        if ([regex]::IsMatch($seed, $entry.Key)) {
            throw [string]$entry.Value
        }
    }

    Add-Result -Stage "Contrato estático del seed" -Result "PASS" -Detail "Manual, transaccional, sin DML RBAC, secretos ni operaciones destructivas"
}

function Test-ByteSequence {
    param(
        [Parameter(Mandatory)][byte[]] $Haystack,
        [Parameter(Mandatory)][byte[]] $Needle
    )

    if ($Needle.Length -eq 0 -or $Haystack.Length -lt $Needle.Length) { return $false }
    $last = $Haystack.Length - $Needle.Length
    for ($offset = 0; $offset -le $last; $offset++) {
        if ($Haystack[$offset] -ne $Needle[0]) { continue }
        $matches = $true
        for ($index = 1; $index -lt $Needle.Length; $index++) {
            if ($Haystack[$offset + $index] -ne $Needle[$index]) {
                $matches = $false
                break
            }
        }
        if ($matches) { return $true }
    }
    return $false
}

function Assert-NoSecretsInTemporaryFiles {
    foreach ($file in @(Get-ChildItem -LiteralPath $script:tempRoot -File -Recurse -ErrorAction SilentlyContinue)) {
        if ($file.Length -gt 20MB) {
            throw "No se puede auditar un temporal mayor a 20 MB: $($file.FullName)"
        }
        $bytes = [IO.File]::ReadAllBytes($file.FullName)
        if ($bytes.Length -eq 0) { continue }
        foreach ($secret in $script:secretValues) {
            if ([string]::IsNullOrEmpty($secret)) { continue }
            $needle = [Text.Encoding]::UTF8.GetBytes($secret)
            if (Test-ByteSequence -Haystack $bytes -Needle $needle) {
                throw "Se detectó un secreto efímero persistido en $($file.FullName)"
            }
        }
    }
    Add-Result -Stage "Persistencia de secretos" -Result "PASS" -Detail "Ninguna password, hash, token o secreto aparece en temporales"
}

function Invoke-DemoSeed {
    Assert-Deadline
    $containerId = Invoke-Compose -Arguments @("ps", "-q", "db") -Capture
    if ([string]::IsNullOrWhiteSpace($containerId)) {
        throw "No se pudo resolver el contenedor PostgreSQL aislado"
    }

    $containerSeedPath = "/tmp/gestudio_demo_seed_full.sql"
    Invoke-Docker -Arguments @("cp", $script:seedPath, "${containerId}:$containerSeedPath") | Out-Null
    try {
        $arguments = @(
            "compose", "-f", $script:composeFile, "-p", $script:project,
            "exec", "-T", "db", "psql",
            "-v", "ON_ERROR_STOP=1",
            "-U", $script:postgresUser,
            "-d", $script:postgresDb,
            "-v", "demo_anchor_date=$($script:anchorDate.ToString('yyyy-MM-dd'))",
            "-v", "demo_superadmin_password_hash=$($script:demoHashes['demo-superadmin'])",
            "-v", "demo_direccion_password_hash=$($script:demoHashes['demo-direccion'])",
            "-v", "demo_administrador_password_hash=$($script:demoHashes['demo-administrador'])",
            "-v", "demo_secretaria_password_hash=$($script:demoHashes['demo-secretaria'])",
            "-v", "demo_caja_password_hash=$($script:demoHashes['demo-caja'])",
            "-f", $containerSeedPath
        )

        $previousErrorAction = $ErrorActionPreference
        try {
            $ErrorActionPreference = "Continue"
            $output = @(& docker @arguments 2>&1)
            $code = $LASTEXITCODE
        }
        finally { $ErrorActionPreference = $previousErrorAction }

        $text = ($output | ForEach-Object { $_.ToString() }) -join "`n"
        if ($code -ne 0) {
            throw "El seed demo falló con código ${code}: $(Redact $text)"
        }
        if ($text -notmatch "GESTUDIO DEMO SEED: ejecución completada y validada") {
            throw "El seed terminó sin emitir su confirmación canónica"
        }
        return $text.Trim()
    }
    finally {
        try { Invoke-Docker -Arguments @("exec", $containerId, "rm", "-f", $containerSeedPath) | Out-Null }
        catch { }
    }
}

function Test-Java21Executable {
    param([Parameter(Mandatory)][string] $Candidate)

    if (-not (Test-Path -LiteralPath $Candidate -PathType Leaf)) { return $false }
    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = @(& $Candidate -version 2>&1)
        $code = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousErrorAction }
    if ($code -ne 0) { return $false }
    $text = ($output | ForEach-Object { $_.ToString() }) -join "`n"
    return $text -match 'version\s+"21(?:\.|\")'
}

function Resolve-Java21 {
    $javaName = if ($script:isWindowsHost) { "java.exe" } else { "java" }
    $candidates = [Collections.Generic.List[string]]::new()

    if (-not [string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
        $candidates.Add((Join-Path $env:JAVA_HOME "bin/$javaName"))
    }

    $command = Get-Command java -ErrorAction SilentlyContinue
    if ($null -ne $command) { $candidates.Add($command.Source) }

    $roots = [Collections.Generic.List[string]]::new()
    if ($script:isWindowsHost) {
        foreach ($root in @(
            "$env:ProgramFiles\Java",
            "$env:ProgramFiles\Amazon Corretto",
            "$env:ProgramFiles\Eclipse Adoptium",
            "$env:ProgramFiles\Microsoft",
            "$env:USERPROFILE\.jdks"
        )) {
            if (-not [string]::IsNullOrWhiteSpace($root) -and (Test-Path -LiteralPath $root -PathType Container)) {
                $roots.Add($root)
            }
        }
    }
    else {
        foreach ($root in @("/usr/lib/jvm", "/opt/java", "$HOME/.jdks")) {
            if (Test-Path -LiteralPath $root -PathType Container) { $roots.Add($root) }
        }
    }

    foreach ($root in $roots) {
        Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $candidates.Add((Join-Path $_.FullName "bin/$javaName"))
        }
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (Test-Java21Executable -Candidate $candidate) {
            $resolvedJava = [IO.Path]::GetFullPath($candidate)
            $resolvedHome = Split-Path (Split-Path $resolvedJava -Parent) -Parent
            $javacName = if ($script:isWindowsHost) { "javac.exe" } else { "javac" }
            $resolvedJavac = Join-Path $resolvedHome "bin/$javacName"
            if (-not (Test-Path -LiteralPath $resolvedJavac -PathType Leaf)) {
                throw "Se encontró Java 21, pero no javac en $resolvedHome"
            }
            return [pscustomobject]@{
                Home = $resolvedHome
                Java = $resolvedJava
                Javac = $resolvedJavac
            }
        }
    }

    throw "No se encontró un JDK 21 completo. Configure JAVA_HOME para esta sesión."
}

function Resolve-MavenWrapper {
    $candidate = if ($script:isWindowsHost) {
        Join-Path $script:backendRoot "mvnw.cmd"
    }
    else {
        Join-Path $script:backendRoot "mvnw"
    }

    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw "No se encontró Maven Wrapper en $candidate"
    }
    return $candidate
}

function Build-Backend {
    Push-Location $script:backendRoot
    try {
        Invoke-Native -FilePath $script:mavenWrapper -Arguments @(
            "-q", "-DskipTests", "package"
        )
    }
    finally { Pop-Location }

    $jars = @(Get-ChildItem -LiteralPath (Join-Path $script:backendRoot "target") -Filter "*.jar" -File |
        Where-Object { $_.Name -notlike "*.original" } |
        Sort-Object Length -Descending)
    if ($jars.Count -eq 0) { throw "El build no produjo un JAR ejecutable" }
    $script:backendJar = $jars[0].FullName
}

function New-BcryptHashes {
    param([Parameter(Mandatory)][hashtable] $Passwords)

    $classpathFile = Join-Path $script:tempRoot "runtime-classpath.txt"
    Push-Location $script:backendRoot
    try {
        Invoke-Native -FilePath $script:mavenWrapper -Arguments @(
            "-q",
            "-DincludeScope=runtime",
            "-Dmdep.outputFile=$classpathFile",
            "dependency:build-classpath"
        )
    }
    finally { Pop-Location }

    if (-not (Test-Path -LiteralPath $classpathFile -PathType Leaf)) {
        throw "Maven no produjo el classpath requerido para BCrypt"
    }
    $runtimeClasspath = [IO.File]::ReadAllText($classpathFile).Trim()
    if ([string]::IsNullOrWhiteSpace($runtimeClasspath)) {
        throw "El classpath runtime para BCrypt está vacío"
    }

    $sourcePath = Join-Path $script:tempRoot "GestudioDemoBcrypt.java"
    $source = @'
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;

public final class GestudioDemoBcrypt {
    private GestudioDemoBcrypt() {}

    public static void main(String[] args) throws Exception {
        int strength = Integer.parseInt(args[0]);
        BCryptPasswordEncoder encoder = new BCryptPasswordEncoder(strength);
        try (BufferedReader reader = new BufferedReader(
                new InputStreamReader(System.in, StandardCharsets.UTF_8))) {
            boolean verify = args.length > 1 && "verify".equals(args[1]);
            String password;
            int pair = 0;
            while ((password = reader.readLine()) != null) {
                if (!password.isEmpty() && password.charAt(0) == '\uFEFF') {
                    password = password.substring(1);
                }
                if (verify) {
                    pair++;
                    String hash = reader.readLine();
                    if (hash == null || !encoder.matches(password, hash)) {
                        System.err.println("BCrypt pair " + pair + " failed");
                        System.exit(3);
                    }
                } else {
                    System.out.println(encoder.encode(password));
                }
            }
        }
    }
}
'@
    [IO.File]::WriteAllText($sourcePath, $source, [Text.UTF8Encoding]::new($false))

    Invoke-Native -FilePath $script:javacExe -Arguments @(
        "-encoding", "UTF-8", "-cp", $runtimeClasspath, $sourcePath
    )

    $classpath = $script:tempRoot + [IO.Path]::PathSeparator + $runtimeClasspath
    $script:bcryptClasspath = $classpath
    $escapedClasspath = $classpath.Replace('"', '\"')
    $orderedUsers = @($Passwords.Keys | Sort-Object)
    $result = @{}
    foreach ($username in $orderedUsers) {
        $psi = [Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $script:javaExe
        $psi.Arguments = "-cp `"$escapedClasspath`" GestudioDemoBcrypt 12"
        $psi.UseShellExecute = $false
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true

        $process = [Diagnostics.Process]::new()
        $process.StartInfo = $psi
        [void]$process.Start()
        try {
            $process.StandardInput.WriteLine([string]$Passwords[$username])
            $process.StandardInput.Close()
            $stdout = $process.StandardOutput.ReadToEnd()
            $stderr = $process.StandardError.ReadToEnd()
            $process.WaitForExit()
            $bcryptExitCode = $process.ExitCode
        }
        finally { $process.Dispose() }

        if ($bcryptExitCode -ne 0) {
            throw "El generador BCrypt falló para ${username}: $(Redact $stderr)"
        }

        $hashLines = @($stdout -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        Assert-Equal -Actual $hashLines.Count -Expected 1 -Message "Cantidad inesperada de hashes BCrypt para $username"
        $hash = $hashLines[0].Trim()
        if ($hash -notmatch '^\$2[aby]\$12\$.{53}$') {
            throw "El backend generó un hash BCrypt incompatible"
        }
        $result[$username] = $hash
        Add-Secret $hash
    }

    if (@($result.Values | Select-Object -Unique).Count -ne $orderedUsers.Count) {
        throw "Los hashes BCrypt efímeros deben ser diferentes"
    }

    foreach ($username in $orderedUsers) {
        Assert-BcryptPair -Password ([string]$Passwords[$username]) -Hash ([string]$result[$username]) -Username $username
    }

    return $result
}

function Assert-BcryptPair {
    param(
        [Parameter(Mandatory)][string] $Password,
        [Parameter(Mandatory)][string] $Hash,
        [Parameter(Mandatory)][string] $Username
    )

    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $script:javaExe
    $psi.Arguments = "-cp `"$($script:bcryptClasspath.Replace('"', '\"'))`" GestudioDemoBcrypt 12 verify"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $psi
    [void]$process.Start()
    try {
        $process.StandardInput.WriteLine($Password)
        $process.StandardInput.WriteLine($Hash)
        $process.StandardInput.Close()
        [void]$process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
            throw "La password efímera de $Username no coincide con el BCrypt persistido: $(Redact $stderr)"
        }
    }
    finally { $process.Dispose() }
}

function Configure-BackendEnvironment {
    Set-ScopedEnvironmentVariable -Name "SPRING_PROFILES_ACTIVE" -Value "dev"
    Set-ScopedEnvironmentVariable -Name "SPRING_DATASOURCE_URL" -Value "jdbc:postgresql://127.0.0.1:$($script:dbPort)/$($script:postgresDb)"
    Set-ScopedEnvironmentVariable -Name "SPRING_DATASOURCE_USERNAME" -Value $script:postgresUser
    Set-ScopedEnvironmentVariable -Name "SPRING_DATASOURCE_PASSWORD" -Value $script:postgresPassword
    Set-ScopedEnvironmentVariable -Name "SPRING_JPA_HIBERNATE_DDL_AUTO" -Value "validate"
    Set-ScopedEnvironmentVariable -Name "SPRING_FLYWAY_ENABLED" -Value "true"
    Set-ScopedEnvironmentVariable -Name "SPRING_FLYWAY_BASELINE_ON_MIGRATE" -Value "false"
    Set-ScopedEnvironmentVariable -Name "SPRING_FLYWAY_BASELINE_VERSION" -Value "1"
    Set-ScopedEnvironmentVariable -Name "SERVER_PORT" -Value ([string]$script:backendPort)
    Set-ScopedEnvironmentVariable -Name "JWT_SECRET" -Value $script:jwtSecret
    Set-ScopedEnvironmentVariable -Name "JWT_ISSUER" -Value "gestudio-demo-validation"
    Set-ScopedEnvironmentVariable -Name "JWT_ACCESS_TOKEN_TTL" -Value "PT15M"
    Set-ScopedEnvironmentVariable -Name "JWT_REFRESH_TOKEN_TTL" -Value "PT2H"
    Set-ScopedEnvironmentVariable -Name "APP_TIME_ZONE" -Value "America/Argentina/Buenos_Aires"
    Set-ScopedEnvironmentVariable -Name "APP_SCHEDULING_ENABLED" -Value "false"
    Set-ScopedEnvironmentVariable -Name "APP_BOOTSTRAP_SUPERADMIN_ENABLED" -Value "false"
    Set-ScopedEnvironmentVariable -Name "APP_BOOTSTRAP_ADMIN_ENABLED" -Value "false"
    Set-ScopedEnvironmentVariable -Name "APP_BOOTSTRAP_ADMIN_RESET_EXISTING_PASSWORD" -Value "false"
    Set-ScopedEnvironmentVariable -Name "APP_SECURITY_REFRESH_COOKIE_SECURE" -Value "false"
    Set-ScopedEnvironmentVariable -Name "APP_CORS_ALLOWED_ORIGINS" -Value $script:frontendOrigin
    Set-ScopedEnvironmentVariable -Name "APP_RECEIPTS_PATH" -Value $script:receiptsRoot
    Set-ScopedEnvironmentVariable -Name "GESTUDIO_HOME" -Value $script:tempRoot
    Set-ScopedEnvironmentVariable -Name "LOGGING_LEVEL_ROOT" -Value "WARN"
}

function Start-Backend {
    if ($null -ne $script:backendProcess -and -not $script:backendProcess.HasExited) {
        throw "Ya existe un backend iniciado por el validador"
    }

    Remove-Item -LiteralPath $script:backendStdout, $script:backendStderr -Force -ErrorAction SilentlyContinue
    $argumentString = "-jar `"$($script:backendJar)`""
    $startParameters = @{
        FilePath = $script:javaExe
        ArgumentList = $argumentString
        WorkingDirectory = $script:backendRoot
        PassThru = $true
        RedirectStandardOutput = $script:backendStdout
        RedirectStandardError = $script:backendStderr
    }
    if ($script:isWindowsHost) { $startParameters.WindowStyle = 'Hidden' }
    $script:backendProcess = Start-Process @startParameters
}

function Get-BackendLogTail {
    $lines = [Collections.Generic.List[string]]::new()
    foreach ($path in @($script:backendStdout, $script:backendStderr)) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            Get-Content -LiteralPath $path -Tail 100 -ErrorAction SilentlyContinue | ForEach-Object {
                $lines.Add($_.ToString())
            }
        }
    }
    return Redact (($lines -join "`n").Trim())
}

function Wait-BackendAvailable {
    while ((Get-Date) -lt $script:deadline) {
        if ($null -ne $script:backendProcess -and $script:backendProcess.HasExited) {
            throw "El backend terminó con código $($script:backendProcess.ExitCode): $(Get-BackendLogTail)"
        }

        try {
            $result = Invoke-HttpRaw -Method "GET" -Uri ($script:apiBase + "/usuarios/perfil") -Body $null -Token $null
            if ($result.Status -eq 401) { return }
        }
        catch {
            # El socket todavía puede no estar escuchando.
        }
        Start-Sleep -Milliseconds 750
    }
    throw "Timeout esperando disponibilidad del backend: $(Get-BackendLogTail)"
}

function Stop-Backend {
    if ($null -eq $script:backendProcess) { return }
    try {
        if (-not $script:backendProcess.HasExited) {
            Stop-Process -Id $script:backendProcess.Id -Force -ErrorAction SilentlyContinue
            try { Wait-Process -Id $script:backendProcess.Id -Timeout 15 -ErrorAction SilentlyContinue }
            catch { }
        }
    }
    finally {
        $script:backendProcess.Dispose()
        $script:backendProcess = $null
    }
}

function Invoke-HttpRaw {
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
        if ($null -ne $Body) {
            $json = $Body | ConvertTo-Json -Depth 15 -Compress
            if ($Body -is [Collections.IDictionary] -and $Body.Contains('contrasena')) {
                $roundTrip = $json | ConvertFrom-Json
                Assert-Equal -Actual ([string]$roundTrip.contrasena) -Expected ([string]$Body['contrasena']) -Message "La serialización HTTP alteró la password efímera"
            }
            $request.Content = [Net.Http.StringContent]::new($json, [Text.Encoding]::UTF8, "application/json")
        }
        $response = $script:http.SendAsync($request).GetAwaiter().GetResult()
        try {
            $raw = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            if ($script:VerboseHttp) {
                Write-Host "[HTTP] $Method $Uri -> $([int]$response.StatusCode)"
            }
            return [pscustomobject]@{
                Status = [int]$response.StatusCode
                Body = $raw
            }
        }
        finally { $response.Dispose() }
    }
    finally { $request.Dispose() }
}

function Invoke-Api {
    param(
        [Parameter(Mandatory)][string] $Method,
        [Parameter(Mandatory)][string] $Path,
        $Body = $null,
        [AllowNull()][string] $Token = $null,
        [Parameter(Mandatory)][int] $ExpectedStatus
    )

    $result = Invoke-HttpRaw -Method $Method -Uri ($script:apiBase + $Path) -Body $Body -Token $Token
    if ($result.Status -ne $ExpectedStatus) {
        throw "$Method $Path devolvió estado inesperado (esperado=$ExpectedStatus, actual=$($result.Status), body=$(Redact $result.Body))"
    }

    $json = $null
    if (-not [string]::IsNullOrWhiteSpace($result.Body)) {
        try { $json = $result.Body | ConvertFrom-Json }
        catch { $json = $null }
    }
    return [pscustomobject]@{
        Status = $result.Status
        Body = $result.Body
        Json = $json
    }
}

function Register-RefreshCookieSecret {
    $cookie = $script:cookieContainer.GetCookies([Uri]($script:apiBase + "/login"))["gestudio_refresh"]
    if ($null -ne $cookie -and -not [string]::IsNullOrWhiteSpace($cookie.Value)) {
        Add-Secret ([string]$cookie.Value)
    }
}

function Login-Actor {
    param(
        [Parameter(Mandatory)][string] $Username,
        [Parameter(Mandatory)][string] $ExpectedRole
    )

    $storedHash = Invoke-Sql "SELECT contrasena FROM usuarios WHERE lower(nombre_usuario)='$Username';"
    Add-Secret $storedHash
    Assert-Equal -Actual $storedHash -Expected $script:demoHashes[$Username] -Message "El backend alteró el hash de $Username antes del login"
    Assert-True -Condition (-not [string]::IsNullOrWhiteSpace([string]$script:demoPasswords[$Username])) -Message "Password efímera ausente para $Username"
    Assert-BcryptPair -Password ([string]$script:demoPasswords[$Username]) -Hash $storedHash -Username $Username

    try {
        $response = Invoke-Api -Method "POST" -Path "/login" -Body @{
            nombreUsuario = $Username
            contrasena = [string]($script:demoPasswords[$Username])
        } -Token $null -ExpectedStatus 200
    }
    catch {
        throw "Login de ${Username}: $($_.Exception.Message)"
    }

    Assert-True -Condition ($null -ne $response.Json) -Message "Login de $Username sin JSON"
    Assert-True -Condition (-not [string]::IsNullOrWhiteSpace([string]$response.Json.accessToken)) -Message "Login de $Username sin access token"
    Assert-True -Condition (@($response.Json.usuario.roles) -contains $ExpectedRole) -Message "Login de $Username con rol inesperado"
    Assert-Equal -Actual ([bool]$response.Json.usuario.activo) -Expected $true -Message "Usuario $Username inactivo"

    $token = [string]$response.Json.accessToken
    Add-Secret $token
    Register-RefreshCookieSecret
    $script:actorTokens[$Username] = $token
    return $response.Json.usuario
}

function Assert-Endpoint {
    param(
        [Parameter(Mandatory)][string] $Stage,
        [Parameter(Mandatory)][string] $Method,
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Actor,
        [Parameter(Mandatory)][int] $ExpectedStatus,
        $Body = $null
    )

    Invoke-Api -Method $Method -Path $Path -Body $Body -Token $script:actorTokens[$Actor] -ExpectedStatus $ExpectedStatus | Out-Null
    Add-Result -Stage $Stage -Result "PASS" -Detail "$Actor -> $Method $Path = $ExpectedStatus"
}

function Get-RbacSnapshot {
    return Invoke-Sql -Query @"
SELECT jsonb_build_object(
    'rolesCount', (SELECT count(*) FROM roles),
    'rolesHash', (SELECT md5(COALESCE(string_agg(id::text || '|' || codigo || '|' || activo::text || '|' || sistema::text || '|' || editable::text, E'\n' ORDER BY id), '')) FROM roles),
    'permissionsCount', (SELECT count(*) FROM permisos),
    'permissionsHash', (SELECT md5(COALESCE(string_agg(id::text || '|' || codigo || '|' || activo::text || '|' || sistema::text || '|' || modulo || '|' || descripcion, E'\n' ORDER BY id), '')) FROM permisos),
    'matrixCount', (SELECT count(*) FROM rol_permisos),
    'matrixHash', (SELECT md5(COALESCE(string_agg(rol_id::text || '|' || permiso_id::text, E'\n' ORDER BY rol_id, permiso_id), '')) FROM rol_permisos)
)::text;
"@
}

function Get-DemoSnapshot {
    return Invoke-Sql -Query @"
WITH demo_users AS (
    SELECT id FROM usuarios WHERE lower(nombre_usuario) LIKE 'demo-%'
), demo_alumnos AS (
    SELECT id FROM alumnos WHERE email LIKE '%@correo.local'
), demo_inscripciones AS (
    SELECT i.id FROM inscripciones i JOIN demo_alumnos a ON a.id = i.alumno_id
), demo_mensualidades AS (
    SELECT m.id FROM mensualidades m JOIN demo_inscripciones i ON i.id = m.inscripcion_id
), demo_matriculas AS (
    SELECT m.id FROM matriculas m JOIN demo_alumnos a ON a.id = m.alumno_id
), demo_cargos AS (
    SELECT c.id FROM cargos c JOIN demo_alumnos a ON a.id = c.alumno_id
), demo_pagos AS (
    SELECT p.id FROM pagos p JOIN demo_alumnos a ON a.id = p.alumno_id
), demo_ventas AS (
    SELECT v.id FROM ventas_stock v JOIN demo_alumnos a ON a.id = v.alumno_id
), demo_stocks AS (
    SELECT s.id FROM stocks s WHERE s.codigo_barras IN (
        '7790000000012', '7790000000029', '7790000000036',
        '7790000000043', '7790000000050', '7790000000067'
    )
), demo_asistencia_mensual AS (
    SELECT am.id FROM asistencias_mensuales am
    JOIN disciplinas d ON d.id = am.disciplina_id
    WHERE d.nombre IN (
        'Ballet Inicial (4 a 6 años)', 'Jazz Infantil (7 a 10 años)',
        'Danza Urbana Teen', 'Danza Contemporánea',
        'Ritmos Latinos Adultos', 'Entrenamiento Escénico'
    )
), demo_asistencia_alumno AS (
    SELECT aam.id FROM asistencias_alumno_mensual aam
    JOIN demo_inscripciones i ON i.id = aam.inscripcion_id
)
SELECT (jsonb_build_object(
    'usersCount', (SELECT count(*) FROM demo_users),
    'usersIds', (SELECT md5(COALESCE(string_agg(id::text, ',' ORDER BY id), '')) FROM demo_users),
    'usersHash', (SELECT md5(COALESCE(string_agg(u.id::text || '|' || lower(u.nombre_usuario) || '|' || u.rol_id::text || '|' || u.activo::text || '|' || u.auth_version::text, E'\n' ORDER BY u.id), '')) FROM usuarios u JOIN demo_users du ON du.id=u.id),
    'userRolesCount', (SELECT count(*) FROM usuario_roles ur JOIN demo_users u ON u.id = ur.usuario_id),
    'userRolesIds', (SELECT md5(COALESCE(string_agg(ur.usuario_id::text || ':' || ur.rol_id::text, ',' ORDER BY ur.usuario_id, ur.rol_id), '')) FROM usuario_roles ur JOIN demo_users u ON u.id = ur.usuario_id),
    'studentsCount', (SELECT count(*) FROM demo_alumnos),
    'studentsIds', (SELECT md5(COALESCE(string_agg(id::text, ',' ORDER BY id), '')) FROM demo_alumnos),
    'enrollmentsCount', (SELECT count(*) FROM demo_inscripciones),
    'enrollmentsIds', (SELECT md5(COALESCE(string_agg(id::text, ',' ORDER BY id), '')) FROM demo_inscripciones),
    'enrollmentsHash', (SELECT md5(COALESCE(string_agg(i.id::text || '|' || i.alumno_id::text || '|' || i.disciplina_id::text || '|' || i.estado || '|' || COALESCE(i.costo_particular::text,''), E'\n' ORDER BY i.id), '')) FROM inscripciones i JOIN demo_inscripciones di ON di.id=i.id),
    'monthlyCount', (SELECT count(*) FROM demo_mensualidades),
    'monthlyIds', (SELECT md5(COALESCE(string_agg(id::text, ',' ORDER BY id), '')) FROM demo_mensualidades),
    'monthlyHash', (SELECT md5(COALESCE(string_agg(m.id::text || '|' || m.inscripcion_id::text || '|' || m.anio::text || '|' || m.mes::text || '|' || m.estado, E'\n' ORDER BY m.id), '')) FROM mensualidades m JOIN demo_mensualidades dm ON dm.id=m.id),
    'registrationsCount', (SELECT count(*) FROM demo_matriculas),
    'registrationsIds', (SELECT md5(COALESCE(string_agg(id::text, ',' ORDER BY id), '')) FROM demo_matriculas),
    'registrationsHash', (SELECT md5(COALESCE(string_agg(m.id::text || '|' || m.alumno_id::text || '|' || m.anio::text || '|' || m.estado, E'\n' ORDER BY m.id), '')) FROM matriculas m JOIN demo_matriculas dm ON dm.id=m.id),
    'chargesCount', (SELECT count(*) FROM demo_cargos),
    'chargesIds', (SELECT md5(COALESCE(string_agg(id::text, ',' ORDER BY id), '')) FROM demo_cargos),
    'chargesHash', (SELECT md5(COALESCE(string_agg(c.id::text || '|' || c.tipo || '|' || c.importe_original::text || '|' || c.estado || '|' || COALESCE(c.idempotency_key,''), E'\n' ORDER BY c.id), '')) FROM cargos c JOIN demo_cargos dc ON dc.id=c.id),
    'liquidationsCount', (SELECT count(*) FROM cargo_liquidaciones cl JOIN demo_cargos c ON c.id = cl.cargo_id),
    'paymentsCount', (SELECT count(*) FROM demo_pagos),
    'paymentsIds', (SELECT md5(COALESCE(string_agg(id::text, ',' ORDER BY id), '')) FROM demo_pagos),
    'paymentsHash', (SELECT md5(COALESCE(string_agg(p.id::text || '|' || p.monto_recibido::text || '|' || p.estado || '|' || p.idempotency_key || '|' || COALESCE(p.reversal_idempotency_key,''), E'\n' ORDER BY p.id), '')) FROM pagos p JOIN demo_pagos dp ON dp.id=p.id),
    'applicationsCount', (SELECT count(*) FROM aplicaciones_pago ap JOIN demo_pagos p ON p.id = ap.pago_id),
    'applicationsIds', (SELECT md5(COALESCE(string_agg(ap.id::text, ',' ORDER BY ap.id), '')) FROM aplicaciones_pago ap JOIN demo_pagos p ON p.id = ap.pago_id),
    'applicationsHash', (SELECT md5(COALESCE(string_agg(ap.id::text || '|' || ap.pago_id::text || '|' || ap.cargo_id::text || '|' || ap.importe_aplicado::text || '|' || ap.estado, E'\n' ORDER BY ap.id), '')) FROM aplicaciones_pago ap JOIN demo_pagos p ON p.id=ap.pago_id),
    'salesCount', (SELECT count(*) FROM demo_ventas),
    'salesIds', (SELECT md5(COALESCE(string_agg(id::text, ',' ORDER BY id), '')) FROM demo_ventas),
    'salesHash', (SELECT md5(COALESCE(string_agg(v.id::text || '|' || v.stock_id::text || '|' || v.cantidad::text || '|' || v.precio_unitario::text || '|' || v.estado || '|' || v.idempotency_key, E'\n' ORDER BY v.id), '')) FROM ventas_stock v JOIN demo_ventas dv ON dv.id=v.id),
    'cashCount', (SELECT count(*) FROM movimientos_caja WHERE idempotency_key LIKE 'demo-seed:v1:%'),
    'cashIds', (SELECT md5(COALESCE(string_agg(id::text, ',' ORDER BY id), '')) FROM movimientos_caja WHERE idempotency_key LIKE 'demo-seed:v1:%'),
    'cashHash', (SELECT md5(COALESCE(string_agg(id::text || '|' || tipo || '|' || importe::text || '|' || metodo_pago_id::text || '|' || COALESCE(movimiento_revertido_id::text,'') || '|' || idempotency_key, E'\n' ORDER BY id), '')) FROM movimientos_caja WHERE idempotency_key LIKE 'demo-seed:v1:%')
) || jsonb_build_object(
    'creditCount', (SELECT count(*) FROM movimientos_credito WHERE idempotency_key LIKE 'demo-seed:v1:%'),
    'creditIds', (SELECT md5(COALESCE(string_agg(id::text, ',' ORDER BY id), '')) FROM movimientos_credito WHERE idempotency_key LIKE 'demo-seed:v1:%'),
    'creditHash', (SELECT md5(COALESCE(string_agg(id::text || '|' || alumno_id::text || '|' || tipo || '|' || importe::text || '|' || COALESCE(cargo_id::text,'') || '|' || COALESCE(movimiento_revertido_id::text,'') || '|' || idempotency_key, E'\n' ORDER BY id), '')) FROM movimientos_credito WHERE idempotency_key LIKE 'demo-seed:v1:%'),
    'stockMovementsCount', (SELECT count(*) FROM movimientos_stock WHERE idempotency_key LIKE 'demo-seed:v1:%'),
    'stockMovementIds', (SELECT md5(COALESCE(string_agg(id::text, ',' ORDER BY id), '')) FROM movimientos_stock WHERE idempotency_key LIKE 'demo-seed:v1:%'),
    'stockMovementsHash', (SELECT md5(COALESCE(string_agg(id::text || '|' || stock_id::text || '|' || tipo || '|' || cantidad::text || '|' || COALESCE(venta_stock_id::text,'') || '|' || COALESCE(movimiento_revertido_id::text,'') || '|' || idempotency_key, E'\n' ORDER BY id), '')) FROM movimientos_stock WHERE idempotency_key LIKE 'demo-seed:v1:%'),
    'stocksCount', (SELECT count(*) FROM demo_stocks),
    'stocksHash', (SELECT md5(COALESCE(string_agg(s.id::text || ':' || s.cantidad_actual::text, ',' ORDER BY s.id), '')) FROM stocks s JOIN demo_stocks ds ON ds.id = s.id),
    'attendanceSheetsCount', (SELECT count(*) FROM demo_asistencia_mensual),
    'attendanceStudentsCount', (SELECT count(*) FROM demo_asistencia_alumno),
    'attendanceDailyCount', (SELECT count(*) FROM asistencias_diarias ad JOIN demo_asistencia_alumno a ON a.id = ad.asistencia_alumno_mensual_id),
    'attendanceHash', (SELECT md5(COALESCE(string_agg(ad.id::text || '|' || ad.asistencia_alumno_mensual_id::text || '|' || ad.fecha::text || '|' || ad.estado || '|' || ad.vigente::text, E'\n' ORDER BY ad.id), '')) FROM asistencias_diarias ad JOIN demo_asistencia_alumno a ON a.id=ad.asistencia_alumno_mensual_id),
    'receiptsCount', (SELECT count(*) FROM recibos r JOIN demo_pagos p ON p.id = r.pago_id),
    'receiptIds', (SELECT md5(COALESCE(string_agg(r.id::text, ',' ORDER BY r.id), '')) FROM recibos r JOIN demo_pagos p ON p.id = r.pago_id),
    'receiptsHash', (SELECT md5(COALESCE(string_agg(r.id::text || '|' || r.pago_id::text || '|' || COALESCE(r.storage_key,'') || '|' || COALESCE(r.generado_at::text,'') || '|' || COALESCE(r.enviado_at::text,''), E'\n' ORDER BY r.id), '')) FROM recibos r JOIN demo_pagos p ON p.id=r.pago_id),
    'outboxCount', (SELECT count(*) FROM recibos_pendientes rp JOIN demo_pagos p ON p.id = rp.pago_id),
    'outboxIds', (SELECT md5(COALESCE(string_agg(rp.id::text, ',' ORDER BY rp.id), '')) FROM recibos_pendientes rp JOIN demo_pagos p ON p.id = rp.pago_id),
    'outboxHash', (SELECT md5(COALESCE(string_agg(rp.id::text || '|' || rp.pago_id::text || '|' || rp.tipo || '|' || rp.estado || '|' || rp.intentos::text || '|' || rp.idempotency_key || '|' || COALESCE(rp.processed_at::text,''), E'\n' ORDER BY rp.id), '')) FROM recibos_pendientes rp JOIN demo_pagos p ON p.id=rp.pago_id),
    'registeredPayments', (SELECT COALESCE(sum(p.monto_recibido), 0)::text FROM pagos p JOIN demo_pagos dp ON dp.id = p.id WHERE p.estado = 'REGISTRADO'),
    'activeApplications', (SELECT COALESCE(sum(ap.importe_aplicado), 0)::text FROM aplicaciones_pago ap JOIN demo_pagos p ON p.id = ap.pago_id WHERE ap.estado = 'APLICADA'),
    'activePaymentCredit', (SELECT COALESCE(sum(CASE mc.tipo WHEN 'GENERACION' THEN mc.importe WHEN 'REVERSO' THEN -mc.importe ELSE 0 END), 0)::text FROM movimientos_credito mc WHERE mc.idempotency_key LIKE 'demo-seed:v1:%' AND (mc.pago_id IS NOT NULL OR (mc.tipo = 'REVERSO' AND mc.idempotency_key LIKE 'demo-seed:v1:credito:reversa-generacion%'))),
    'netCredit', (SELECT COALESCE(sum(CASE mc.tipo WHEN 'GENERACION' THEN mc.importe WHEN 'AJUSTE_CREDITO' THEN mc.importe WHEN 'CONSUMO' THEN -mc.importe WHEN 'AJUSTE_DEBITO' THEN -mc.importe WHEN 'REVERSO' THEN CASE WHEN original.tipo = 'CONSUMO' THEN mc.importe ELSE -mc.importe END ELSE 0 END), 0)::text FROM movimientos_credito mc LEFT JOIN movimientos_credito original ON original.id = mc.movimiento_revertido_id WHERE mc.idempotency_key LIKE 'demo-seed:v1:%')
))::text;
"@
}

function Assert-ExpectedDemoCounts {
    param([Parameter(Mandatory)] $Snapshot)

    $expected = [ordered]@{
        usersCount = 5
        userRolesCount = 5
        studentsCount = 28
        enrollmentsCount = 34
        monthlyCount = 70
        registrationsCount = 26
        chargesCount = 115
        liquidationsCount = 115
        paymentsCount = 48
        applicationsCount = 82
        salesCount = 6
        cashCount = 61
        creditCount = 11
        stockMovementsCount = 14
        stocksCount = 6
        attendanceSheetsCount = 6
        attendanceStudentsCount = 18
        attendanceDailyCount = 54
        receiptsCount = 48
        outboxCount = 48
    }

    foreach ($entry in $expected.GetEnumerator()) {
        $property = $Snapshot.PSObject.Properties[$entry.Key]
        if ($null -eq $property) { throw "Snapshot sin propiedad $($entry.Key)" }
        Assert-Equal -Actual ([int64]$property.Value) -Expected ([int64]$entry.Value) -Message "Conteo demo inesperado para $($entry.Key)"
    }

    $expectedTotals = [ordered]@{
        registeredPayments = "1956700.00"
        activeApplications = "1938700.00"
        activePaymentCredit = "18000.00"
        netCredit = "21000.00"
    }
    foreach ($entry in $expectedTotals.GetEnumerator()) {
        $property = $Snapshot.PSObject.Properties[$entry.Key]
        if ($null -eq $property) { throw "Snapshot sin propiedad $($entry.Key)" }
        $actual = [decimal]::Parse([string]$property.Value, [Globalization.CultureInfo]::InvariantCulture)
        $expectedTotal = [decimal]::Parse($entry.Value, [Globalization.CultureInfo]::InvariantCulture)
        Assert-Equal -Actual $actual -Expected $expectedTotal -Message "Total demo inesperado para $($entry.Key)"
    }
}

function Invoke-IntegrityChecks {
    Assert-SqlZero -Stage "Usuarios demo con roles inactivos" -Query @"
SELECT count(*) FROM usuarios u
JOIN usuario_roles ur ON ur.usuario_id = u.id
JOIN roles r ON r.id = ur.rol_id
WHERE lower(u.nombre_usuario) LIKE 'demo-%' AND NOT r.activo;
"@

    Assert-SqlZero -Stage "Usuario operativo con rol Profesor" -Query @"
SELECT count(*) FROM usuarios u
JOIN usuario_roles ur ON ur.usuario_id = u.id
JOIN roles r ON r.id = ur.rol_id
WHERE lower(u.nombre_usuario) LIKE 'demo-%' AND r.codigo = 'PROFESOR';
"@

    Assert-SqlZero -Stage "FK demo huérfanas" -Query @"
WITH demo_alumnos AS (SELECT id FROM alumnos WHERE email LIKE '%@correo.local')
SELECT sum(invalidos) FROM (
    SELECT count(*) AS invalidos FROM inscripciones i JOIN demo_alumnos da ON da.id=i.alumno_id LEFT JOIN disciplinas d ON d.id=i.disciplina_id WHERE d.id IS NULL
    UNION ALL SELECT count(*) FROM cargos c JOIN demo_alumnos da ON da.id=c.alumno_id LEFT JOIN alumnos a ON a.id=c.alumno_id WHERE a.id IS NULL
    UNION ALL SELECT count(*) FROM pagos p JOIN demo_alumnos da ON da.id=p.alumno_id LEFT JOIN metodo_pagos mp ON mp.id=p.metodo_pago_id WHERE mp.id IS NULL
    UNION ALL SELECT count(*) FROM ventas_stock v JOIN demo_alumnos da ON da.id=v.alumno_id LEFT JOIN stocks s ON s.id=v.stock_id WHERE s.id IS NULL
) q;
"@

    Assert-SqlZero -Stage "Aplicaciones superiores al pago" -Query @"
SELECT count(*) FROM (
    SELECT p.id
    FROM pagos p
    JOIN alumnos a ON a.id=p.alumno_id AND a.email LIKE '%@correo.local'
    LEFT JOIN aplicaciones_pago ap ON ap.pago_id=p.id AND ap.estado='APLICADA'
    GROUP BY p.id, p.monto_recibido
    HAVING COALESCE(sum(ap.importe_aplicado),0) > p.monto_recibido
) q;
"@

    Assert-SqlZero -Stage "Aplicaciones superiores al cargo" -Query @"
WITH pagos AS (
    SELECT cargo_id, sum(importe_aplicado) AS importe
    FROM aplicaciones_pago WHERE estado='APLICADA' GROUP BY cargo_id
), credito AS (
    SELECT cargo_id, sum(importe) AS importe FROM (
        SELECT cargo_id, importe FROM movimientos_credito WHERE tipo='CONSUMO'
        UNION ALL
        SELECT original.cargo_id, -reverso.importe
        FROM movimientos_credito reverso
        JOIN movimientos_credito original ON original.id=reverso.movimiento_revertido_id
        WHERE reverso.tipo='REVERSO' AND original.tipo='CONSUMO'
    ) x GROUP BY cargo_id
)
SELECT count(*) FROM cargos c
JOIN alumnos a ON a.id=c.alumno_id AND a.email LIKE '%@correo.local'
LEFT JOIN pagos p ON p.cargo_id=c.id
LEFT JOIN credito cr ON cr.cargo_id=c.id
WHERE COALESCE(p.importe,0) + COALESCE(cr.importe,0) > c.importe_original;
"@

    Assert-SqlZero -Stage "Estados de cargo incoherentes" -Query @"
WITH pagos AS (
    SELECT cargo_id, sum(importe_aplicado) AS importe FROM aplicaciones_pago WHERE estado='APLICADA' GROUP BY cargo_id
), credito AS (
    SELECT cargo_id, sum(importe) AS importe FROM (
        SELECT cargo_id, importe FROM movimientos_credito WHERE tipo='CONSUMO'
        UNION ALL
        SELECT original.cargo_id, -reverso.importe FROM movimientos_credito reverso
        JOIN movimientos_credito original ON original.id=reverso.movimiento_revertido_id
        WHERE reverso.tipo='REVERSO' AND original.tipo='CONSUMO'
    ) x GROUP BY cargo_id
)
SELECT count(*) FROM cargos c
JOIN alumnos a ON a.id=c.alumno_id AND a.email LIKE '%@correo.local'
LEFT JOIN pagos p ON p.cargo_id=c.id
LEFT JOIN credito cr ON cr.cargo_id=c.id
WHERE c.estado <> CASE
    WHEN c.estado='ANULADO' THEN 'ANULADO'
    WHEN c.importe_original-COALESCE(p.importe,0)-COALESCE(cr.importe,0)=0 THEN 'PAGADO'
    WHEN c.importe_original-COALESCE(p.importe,0)-COALESCE(cr.importe,0)<c.importe_original THEN 'PARCIAL'
    ELSE 'PENDIENTE' END;
"@

    Assert-SqlZero -Stage "Crédito demo negativo" -Query @"
SELECT count(*) FROM (
    SELECT mc.alumno_id, sum(CASE mc.tipo
        WHEN 'GENERACION' THEN mc.importe
        WHEN 'AJUSTE_CREDITO' THEN mc.importe
        WHEN 'CONSUMO' THEN -mc.importe
        WHEN 'AJUSTE_DEBITO' THEN -mc.importe
        WHEN 'REVERSO' THEN CASE WHEN original.tipo='CONSUMO' THEN mc.importe ELSE -mc.importe END
        ELSE 0 END) AS saldo
    FROM movimientos_credito mc
    LEFT JOIN movimientos_credito original ON original.id=mc.movimiento_revertido_id
    WHERE mc.idempotency_key LIKE 'demo-seed:v1:%'
    GROUP BY mc.alumno_id
    HAVING sum(CASE mc.tipo
        WHEN 'GENERACION' THEN mc.importe
        WHEN 'AJUSTE_CREDITO' THEN mc.importe
        WHEN 'CONSUMO' THEN -mc.importe
        WHEN 'AJUSTE_DEBITO' THEN -mc.importe
        WHEN 'REVERSO' THEN CASE WHEN original.tipo='CONSUMO' THEN mc.importe ELSE -mc.importe END
        ELSE 0 END) < 0
) q;
"@

    Assert-SqlZero -Stage "Stock controlado inconsistente" -Query @"
WITH libro AS (
    SELECT ms.stock_id, sum(CASE ms.tipo
        WHEN 'INGRESO' THEN ms.cantidad
        WHEN 'AJUSTE_POSITIVO' THEN ms.cantidad
        WHEN 'REVERSO' THEN ms.cantidad
        WHEN 'VENTA' THEN -ms.cantidad
        WHEN 'AJUSTE_NEGATIVO' THEN -ms.cantidad
        ELSE 0 END) AS cantidad
    FROM movimientos_stock ms
    WHERE ms.idempotency_key LIKE 'demo-seed:v1:%'
    GROUP BY ms.stock_id
)
SELECT count(*) FROM stocks s JOIN libro l ON l.stock_id=s.id
WHERE s.requiere_control_de_stock AND (s.cantidad_actual<0 OR s.cantidad_actual<>l.cantidad);
"@

    Assert-SqlZero -Stage "Ventas demo inconsistentes" -Query @"
SELECT count(*) FROM ventas_stock v
JOIN alumnos a ON a.id=v.alumno_id AND a.email LIKE '%@correo.local'
LEFT JOIN cargos c ON c.venta_stock_id=v.id
LEFT JOIN movimientos_stock original ON original.venta_stock_id=v.id AND original.tipo='VENTA'
LEFT JOIN movimientos_stock reverso ON reverso.movimiento_revertido_id=original.id AND reverso.tipo='REVERSO'
WHERE c.id IS NULL OR original.id IS NULL
   OR (v.estado='REGISTRADA' AND (c.estado='ANULADO' OR reverso.id IS NOT NULL))
   OR (v.estado='ANULADA' AND (c.estado<>'ANULADO' OR reverso.id IS NULL));
"@

    Assert-SqlZero -Stage "Períodos demo duplicados" -Query @"
SELECT sum(duplicados) FROM (
    SELECT count(*) AS duplicados FROM (SELECT inscripcion_id,anio,mes FROM mensualidades GROUP BY inscripcion_id,anio,mes HAVING count(*)>1) a
    UNION ALL SELECT count(*) FROM (SELECT alumno_id,anio FROM matriculas GROUP BY alumno_id,anio HAVING count(*)>1) b
    UNION ALL SELECT count(*) FROM (SELECT disciplina_id,anio,mes FROM asistencias_mensuales GROUP BY disciplina_id,anio,mes HAVING count(*)>1) c
    UNION ALL SELECT count(*) FROM (SELECT disciplina_id,vigente_desde FROM disciplina_tarifas GROUP BY disciplina_id,vigente_desde HAVING count(*)>1) d
    UNION ALL SELECT count(*) FROM (SELECT inscripcion_id,vigente_desde FROM inscripcion_condiciones_economicas GROUP BY inscripcion_id,vigente_desde HAVING count(*)>1) e
) q;
"@

    Assert-SqlZero -Stage "Idempotencia demo duplicada" -Query @"
SELECT sum(duplicados) FROM (
    SELECT count(*) AS duplicados FROM (SELECT idempotency_key FROM pagos WHERE idempotency_key LIKE 'demo-seed:v1:%' GROUP BY idempotency_key HAVING count(*)>1) a
    UNION ALL SELECT count(*) FROM (SELECT idempotency_key FROM ventas_stock WHERE idempotency_key LIKE 'demo-seed:v1:%' GROUP BY idempotency_key HAVING count(*)>1) b
    UNION ALL SELECT count(*) FROM (SELECT idempotency_key FROM movimientos_caja WHERE idempotency_key LIKE 'demo-seed:v1:%' GROUP BY idempotency_key HAVING count(*)>1) c
    UNION ALL SELECT count(*) FROM (SELECT idempotency_key FROM movimientos_credito WHERE idempotency_key LIKE 'demo-seed:v1:%' GROUP BY idempotency_key HAVING count(*)>1) d
    UNION ALL SELECT count(*) FROM (SELECT idempotency_key FROM movimientos_stock WHERE idempotency_key LIKE 'demo-seed:v1:%' GROUP BY idempotency_key HAVING count(*)>1) e
    UNION ALL SELECT count(*) FROM (SELECT idempotency_key FROM recibos_pendientes WHERE idempotency_key LIKE 'demo-seed:v1:%' GROUP BY idempotency_key HAVING count(*)>1) f
) q;
"@

    Assert-SqlZero -Stage "Recibos u outbox duplicados" -Query @"
SELECT sum(duplicados) FROM (
    SELECT count(*) AS duplicados FROM (SELECT pago_id FROM recibos GROUP BY pago_id HAVING count(*)>1) a
    UNION ALL SELECT count(*) FROM (SELECT pago_id,tipo FROM recibos_pendientes GROUP BY pago_id,tipo HAVING count(*)>1) b
) q;
"@

    Assert-SqlZero -Stage "Reversiones demo duplicadas" -Query @"
SELECT sum(duplicados) FROM (
    SELECT count(*) AS duplicados FROM (SELECT movimiento_revertido_id FROM movimientos_caja WHERE movimiento_revertido_id IS NOT NULL GROUP BY movimiento_revertido_id HAVING count(*)>1) a
    UNION ALL SELECT count(*) FROM (SELECT movimiento_revertido_id FROM movimientos_credito WHERE movimiento_revertido_id IS NOT NULL GROUP BY movimiento_revertido_id HAVING count(*)>1) b
    UNION ALL SELECT count(*) FROM (SELECT movimiento_revertido_id FROM movimientos_stock WHERE movimiento_revertido_id IS NOT NULL GROUP BY movimiento_revertido_id HAVING count(*)>1) c
) q;
"@

    $cashNet = Invoke-Sql -Query @"
SELECT COALESCE(sum(CASE mc.tipo
    WHEN 'INGRESO_PAGO' THEN mc.importe
    WHEN 'AJUSTE_INGRESO' THEN mc.importe
    WHEN 'EGRESO' THEN -mc.importe
    WHEN 'AJUSTE_EGRESO' THEN -mc.importe
    WHEN 'REVERSO' THEN CASE WHEN original.tipo IN ('INGRESO_PAGO','AJUSTE_INGRESO') THEN -mc.importe ELSE mc.importe END
    ELSE 0 END),0)::text
FROM movimientos_caja mc
LEFT JOIN movimientos_caja original ON original.id=mc.movimiento_revertido_id
WHERE mc.idempotency_key LIKE 'demo-seed:v1:%';
"@
    Add-Result -Stage "Caja demo conciliable" -Result "PASS" -Detail "saldo neto=$cashNet"
}

function Show-Diagnostics {
    try {
        $composePs = Invoke-Compose -Arguments @("ps", "-a") -Capture -IgnoreDeadline
        if ($composePs) { Write-Host (Redact $composePs) }
    }
    catch { Write-Host "No se pudo obtener docker compose ps." }

    try {
        $dbLogs = Invoke-Compose -Arguments @("logs", "--tail", "120", "db") -Capture -IgnoreDeadline
        if ($dbLogs) { Write-Host (Redact $dbLogs) }
    }
    catch { Write-Host "No se pudieron obtener logs de PostgreSQL." }

    $backendTail = Get-BackendLogTail
    if (-not [string]::IsNullOrWhiteSpace($backendTail)) {
        Write-Host $backendTail
    }
}

function Remove-IsolatedDockerResources {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { return }

    try { Invoke-Compose -Arguments @("down", "--volumes", "--remove-orphans", "--timeout", "10") -IgnoreDeadline | Out-Null }
    catch { Write-Host "[WARN] docker compose down falló: $(Redact $_.Exception.Message)" }

    try {
        $containers = Invoke-Docker -Arguments @("ps", "-aq", "--filter", "label=com.docker.compose.project=$($script:project)") -Capture -IgnoreDeadline
        foreach ($id in @($containers -split "`r?`n" | Where-Object { $_ })) {
            try { Invoke-Docker -Arguments @("rm", "-f", $id) -IgnoreDeadline | Out-Null } catch { }
        }
    }
    catch { }

    try {
        $networks = Invoke-Docker -Arguments @("network", "ls", "-q", "--filter", "label=com.docker.compose.project=$($script:project)") -Capture -IgnoreDeadline
        foreach ($id in @($networks -split "`r?`n" | Where-Object { $_ })) {
            try { Invoke-Docker -Arguments @("network", "rm", $id) -IgnoreDeadline | Out-Null } catch { }
        }
    }
    catch { }

    try {
        $volumes = Invoke-Docker -Arguments @("volume", "ls", "-q", "--filter", "label=com.docker.compose.project=$($script:project)") -Capture -IgnoreDeadline
        foreach ($id in @($volumes -split "`r?`n" | Where-Object { $_ })) {
            try { Invoke-Docker -Arguments @("volume", "rm", "-f", $id) -IgnoreDeadline | Out-Null } catch { }
        }
    }
    catch { }

    $remainingContainers = Invoke-Docker -Arguments @("ps", "-aq", "--filter", "label=com.docker.compose.project=$($script:project)") -Capture -IgnoreDeadline
    $remainingNetworks = Invoke-Docker -Arguments @("network", "ls", "-q", "--filter", "label=com.docker.compose.project=$($script:project)") -Capture -IgnoreDeadline
    $remainingVolumes = Invoke-Docker -Arguments @("volume", "ls", "-q", "--filter", "label=com.docker.compose.project=$($script:project)") -Capture -IgnoreDeadline
    if (-not [string]::IsNullOrWhiteSpace($remainingContainers) -or
        -not [string]::IsNullOrWhiteSpace($remainingNetworks) -or
        -not [string]::IsNullOrWhiteSpace($remainingVolumes)) {
        throw "Quedaron recursos Docker del proyecto aislado"
    }
}

try {
    New-Item -ItemType Directory -Path $tempRoot, $receiptsRoot -Force | Out-Null

    $parseTokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $PSCommandPath,
        [ref]$parseTokens,
        [ref]$parseErrors
    )
    if ($parseErrors.Count -gt 0) {
        $messages = ($parseErrors | ForEach-Object { $_.Message }) -join "; "
        throw "El propio script no supera el parser de PowerShell: $messages"
    }
    Add-Result -Stage "Sintaxis PowerShell" -Result "PASS" -Detail "Parser nativo sin errores"

    foreach ($required in @($composeFile, $seedPath, $migrationRoot, $backendRoot)) {
        if (-not (Test-Path -LiteralPath $required)) { throw "Falta recurso requerido: $required" }
    }
    Add-Result -Stage "Estructura del repositorio" -Result "PASS" -Detail "Compose, backend, migraciones y seed presentes"
    Assert-SeedStaticContract

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw "Docker no está disponible en PATH" }
    Invoke-Docker -Arguments @("info", "--format", "{{.ServerVersion}}") -Capture | Out-Null
    Invoke-Docker -Arguments @("compose", "version") -Capture | Out-Null
    Add-Result -Stage "Docker" -Result "PASS" -Detail "Engine y Compose disponibles"

    $jdk = Resolve-Java21
    $javaHome = $jdk.Home
    $javaExe = $jdk.Java
    $javacExe = $jdk.Javac
    Set-ScopedEnvironmentVariable -Name "JAVA_HOME" -Value $javaHome
    $pathSeparator = [IO.Path]::PathSeparator
    Set-ScopedEnvironmentVariable -Name "PATH" -Value ((Join-Path $javaHome "bin") + $pathSeparator + $env:PATH)
    $javaVersion = Invoke-Native -FilePath $javaExe -Arguments @("-version") -Capture
    Add-Result -Stage "Java 21" -Result "PASS" -Detail (($javaVersion -split "`r?`n")[0])

    $mavenWrapper = Resolve-MavenWrapper
    if (-not $SkipBackendBuild) {
        Build-Backend
        Add-Result -Stage "Build backend" -Result "PASS" -Detail ([IO.Path]::GetFileName($backendJar))
    }
    else {
        $jars = @(Get-ChildItem -LiteralPath (Join-Path $backendRoot "target") -Filter "*.jar" -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike "*.original" } |
            Sort-Object Length -Descending)
        if ($jars.Count -eq 0) { throw "-SkipBackendBuild requiere un JAR existente en backend/target" }
        $backendJar = $jars[0].FullName
        Add-Result -Stage "Build backend" -Result "INFO" -Detail "Se reutilizó $([IO.Path]::GetFileName($backendJar))"
    }

    $dbPort = Get-FreePort
    $backendPort = Get-FreePort
    $frontendPort = Get-FreePort
    $apiBase = "http://127.0.0.1:$backendPort/api"
    $frontendOrigin = "http://127.0.0.1:$frontendPort"
    $anchorDate = Get-BusinessDate
    $postgresPassword = New-HexSecret 24
    $jwtSecret = New-HexSecret 64
    Add-Secret $postgresPassword
    Add-Secret $jwtSecret

    Set-ScopedEnvironmentVariable -Name "POSTGRES_DB" -Value $postgresDb
    Set-ScopedEnvironmentVariable -Name "POSTGRES_USER" -Value $postgresUser
    Set-ScopedEnvironmentVariable -Name "POSTGRES_PASSWORD" -Value $postgresPassword
    Set-ScopedEnvironmentVariable -Name "POSTGRES_PORT" -Value ([string]$dbPort)
    Set-ScopedEnvironmentVariable -Name "APP_TIME_ZONE" -Value "America/Argentina/Buenos_Aires"
    Configure-BackendEnvironment

    Write-Host "[INFO] Proyecto Compose aislado: $project"
    Write-Host "[INFO] Puertos aleatorios: PostgreSQL=$dbPort backend=$backendPort"
    Write-Host "[INFO] Fecha ancla: $($anchorDate.ToString('yyyy-MM-dd'))"

    $stackAttempted = $true
    Invoke-Compose -Arguments @("up", "-d", "db")
    Wait-DatabaseHealthy
    Add-Result -Stage "PostgreSQL efímero" -Result "PASS" -Detail "Base $postgresDb healthy en puerto aleatorio"

    $cookieContainer = [Net.CookieContainer]::new()
    $handler = [Net.Http.HttpClientHandler]::new()
    $handler.CookieContainer = $cookieContainer
    $http = [Net.Http.HttpClient]::new($handler, $true)
    $http.Timeout = [TimeSpan]::FromSeconds(30)

    Start-Backend
    Wait-BackendAvailable
    Add-Result -Stage "Flyway mediante backend real" -Result "PASS" -Detail "Backend inició con ddl-auto=validate"

    $history = Invoke-Sql -Query "SELECT installed_rank, COALESCE(version,''), description, type, script, COALESCE(checksum::text,''), success FROM flyway_schema_history ORDER BY installed_rank;"
    Assert-Equal -Actual (Invoke-Sql "SELECT count(*) FROM flyway_schema_history WHERE script='V6__rbac_permission_catalog_and_base_roles.sql' AND success") -Expected "1" -Message "La V6 productiva no fue aplicada"
    Assert-Equal -Actual (Invoke-Sql "SELECT count(*) FROM flyway_schema_history WHERE NOT success") -Expected "0" -Message "Flyway contiene migraciones fallidas"
    Assert-Equal -Actual (Invoke-Sql "SELECT count(*) FROM flyway_schema_history WHERE lower(script) LIKE '%demo%seed%'") -Expected "0" -Message "Se detectó una migración Flyway demo"

    $localMigrations = @(Get-ChildItem -LiteralPath $migrationRoot -Filter "V*__*.sql" -File | Sort-Object Name)
    $demoMigrations = @($localMigrations | Where-Object { $_.Name -match '(?i)demo.*seed|seed.*demo' })
    Assert-Equal -Actual $demoMigrations.Count -Expected 0 -Message "Existe una migración demo en db/migration"
    $historyScripts = @((Invoke-Sql "SELECT script FROM flyway_schema_history WHERE success ORDER BY installed_rank;") -split "`r?`n")
    foreach ($migration in $localMigrations) {
        Assert-True -Condition ($historyScripts -contains $migration.Name) -Message "Flyway no aplicó $($migration.Name)"
    }
    Add-Result -Stage "Historial Flyway" -Result "PASS" -Detail "$($localMigrations.Count) migraciones reales; V6 productiva presente; ninguna demo"
    Write-Host "[INFO] flyway_schema_history:`n$history"

    $rbacBefore = Get-RbacSnapshot
    Assert-Equal -Actual (Invoke-Sql "SELECT count(*) FROM permisos WHERE activo AND sistema") -Expected "32" -Message "Catálogo RBAC productivo inesperado"
    Assert-Equal -Actual (Invoke-Sql "SELECT count(*) FROM roles WHERE codigo='PROFESOR' AND NOT activo AND sistema AND NOT editable") -Expected "1" -Message "PROFESOR no mantiene su contrato productivo"
    Add-Result -Stage "Baseline RBAC" -Result "PASS" -Detail "32 permisos activos y rol Profesor deshabilitado"

    Stop-Backend

    $script:demoPasswords = @{
        "demo-superadmin" = New-HexSecret 24
        "demo-direccion" = New-HexSecret 24
        "demo-administrador" = New-HexSecret 24
        "demo-secretaria" = New-HexSecret 24
        "demo-caja" = New-HexSecret 24
    }
    foreach ($password in $script:demoPasswords.Values) { Add-Secret $password }
    Assert-True -Condition ($script:demoPasswords["demo-superadmin"].Length -ge 16) -Message "Password técnica demasiado corta"
    $script:demoHashes = New-BcryptHashes -Passwords $script:demoPasswords
    Add-Result -Stage "Credenciales efímeras" -Result "PASS" -Detail "5 passwords en memoria y 5 hashes BCrypt del backend"

    Invoke-DemoSeed | Out-Null
    foreach ($username in @($script:demoPasswords.Keys | Sort-Object)) {
        $storedHash = Invoke-Sql "SELECT contrasena FROM usuarios WHERE lower(nombre_usuario)='$username';"
        Add-Secret $storedHash
        Assert-Equal -Actual $storedHash -Expected $script:demoHashes[$username] -Message "El hash persistido no corresponde a $username"
    }
    $snapshotFirstRaw = Get-DemoSnapshot
    $snapshotFirst = $snapshotFirstRaw | ConvertFrom-Json
    Assert-ExpectedDemoCounts -Snapshot $snapshotFirst
    $rbacAfterFirst = Get-RbacSnapshot
    Assert-Equal -Actual $rbacAfterFirst -Expected $rbacBefore -Message "El seed modificó RBAC"
    Add-Result -Stage "Primera aplicación del seed" -Result "PASS" -Detail "Conteos esperados e invariantes internas satisfechas"

    Start-Backend
    Wait-BackendAvailable
    Add-Result -Stage "Backend sobre dataset demo" -Result "PASS" -Detail "Hibernate validate y Flyway sin cambios"

    Invoke-Api -Method "GET" -Path "/usuarios/perfil" -Token $null -ExpectedStatus 401 | Out-Null
    Add-Result -Stage "Health/autenticación anónima" -Result "PASS" -Detail "Backend disponible; perfil anónimo=401"

    $rolesEsperados = [ordered]@{
        "demo-superadmin" = "SUPERADMIN"
        "demo-direccion" = "DIRECCION"
        "demo-administrador" = "ADMINISTRADOR"
        "demo-secretaria" = "SECRETARIA"
        "demo-caja" = "CAJA"
    }
    foreach ($entry in $rolesEsperados.GetEnumerator()) {
        $user = Login-Actor -Username $entry.Key -ExpectedRole $entry.Value
        Assert-Equal -Actual ([string]$user.nombreUsuario) -Expected $entry.Key -Message "Username de login incorrecto"
    }
    Add-Result -Stage "Login de usuarios demo" -Result "PASS" -Detail "5/5 actores autenticados"

    $superToken = $actorTokens["demo-superadmin"]
    $profile = Invoke-Api -Method "GET" -Path "/usuarios/perfil" -Token $superToken -ExpectedStatus 200
    Assert-True -Condition (@($profile.Json.permisos).Count -eq 32) -Message "Perfil técnico sin catálogo completo"
    $assignable = Invoke-Api -Method "GET" -Path "/usuarios/roles-asignables" -Token $superToken -ExpectedStatus 200
    Assert-True -Condition (@($assignable.Json.codigo) -notcontains "PROFESOR") -Message "PROFESOR aparece como rol asignable"
    Add-Result -Stage "Perfil y roles asignables" -Result "PASS" -Detail "32 permisos; Profesor no asignable"

    $ids = Invoke-Sql -Query @"
SELECT a.id, i.id
FROM alumnos a
JOIN inscripciones i ON i.alumno_id=a.id AND i.estado='ACTIVA'
WHERE a.documento='49287134'
ORDER BY i.id LIMIT 1;
"@
    $idParts = $ids.Split("|")
    Assert-Equal -Actual $idParts.Count -Expected 2 -Message "No se resolvieron IDs demo representativos"
    $alumnoId = [long]$idParts[0]
    $inscripcionId = [long]$idParts[1]
    $reportFrom = $anchorDate.AddMonths(-3).ToString("yyyy-MM-dd")
    $reportTo = $anchorDate.ToString("yyyy-MM-dd")
    $attendancePeriod = $anchorDate.AddMonths(-1)

    foreach ($endpoint in @(
        @{ Name="Alumnos"; Path="/alumnos?page=0&size=5" },
        @{ Name="Disciplinas"; Path="/disciplinas" },
        @{ Name="Profesores"; Path="/profesores" },
        @{ Name="Inscripciones"; Path="/inscripciones?page=0&size=5" },
        @{ Name="Mensualidades"; Path="/mensualidades/inscripcion/$inscripcionId" },
        @{ Name="Cargos"; Path="/cargos/alumno/$alumnoId/pendientes?page=0&size=5" },
        @{ Name="Pagos"; Path="/pagos/alumno/${alumnoId}?page=0&size=5" },
        @{ Name="Caja"; Path="/caja/resumen?desde=$reportFrom&hasta=$reportTo&page=0&size=5" },
        @{ Name="Stock"; Path="/stocks?page=0&size=5" },
        @{ Name="Asistencias"; Path="/asistencias-mensuales?mes=$($attendancePeriod.Month)&anio=$($attendancePeriod.Year)" },
        @{ Name="Reportes"; Path="/reportes/mensualidades?desde=$reportFrom&hasta=$reportTo" },
        @{ Name="Configuración"; Path="/metodos-pago" },
        @{ Name="Usuarios"; Path="/usuarios" },
        @{ Name="Roles"; Path="/roles" }
    )) {
        Assert-Endpoint -Stage "Endpoint $($endpoint.Name)" -Method "GET" -Path $endpoint.Path -Actor "demo-superadmin" -ExpectedStatus 200
    }

    Assert-Endpoint -Stage "Dirección administra usuarios" -Method "GET" -Path "/usuarios" -Actor "demo-direccion" -ExpectedStatus 200
    Assert-Endpoint -Stage "Dirección no administra roles" -Method "GET" -Path "/roles" -Actor "demo-direccion" -ExpectedStatus 403
    Assert-Endpoint -Stage "Administrador administra usuarios" -Method "GET" -Path "/usuarios" -Actor "demo-administrador" -ExpectedStatus 200
    Assert-Endpoint -Stage "Administrador no administra roles" -Method "GET" -Path "/roles" -Actor "demo-administrador" -ExpectedStatus 403

    Assert-Endpoint -Stage "Secretaría consulta alumnos" -Method "GET" -Path "/alumnos?page=0&size=1" -Actor "demo-secretaria" -ExpectedStatus 200
    Assert-Endpoint -Stage "Secretaría consulta inscripciones" -Method "GET" -Path "/inscripciones?page=0&size=1" -Actor "demo-secretaria" -ExpectedStatus 200
    Assert-Endpoint -Stage "Secretaría consulta asistencias" -Method "GET" -Path "/asistencias-mensuales?mes=$($attendancePeriod.Month)&anio=$($attendancePeriod.Year)" -Actor "demo-secretaria" -ExpectedStatus 200
    Assert-Endpoint -Stage "Secretaría consulta reportes" -Method "GET" -Path "/reportes/mensualidades?desde=$reportFrom&hasta=$reportTo" -Actor "demo-secretaria" -ExpectedStatus 200
    Assert-Endpoint -Stage "Secretaría autoriza registro de pago" -Method "POST" -Path "/pagos" -Actor "demo-secretaria" -ExpectedStatus 400 -Body @{}
    Assert-Endpoint -Stage "Secretaría autoriza registro de asistencia" -Method "POST" -Path "/asistencias-mensuales" -Actor "demo-secretaria" -ExpectedStatus 400 -Body @{}
    Assert-Endpoint -Stage "Secretaría no administra usuarios" -Method "GET" -Path "/usuarios" -Actor "demo-secretaria" -ExpectedStatus 403
    Assert-Endpoint -Stage "Secretaría no administra roles" -Method "GET" -Path "/roles" -Actor "demo-secretaria" -ExpectedStatus 403
    Assert-Endpoint -Stage "Secretaría no administra egresos" -Method "GET" -Path "/egresos?page=0&size=1" -Actor "demo-secretaria" -ExpectedStatus 403

    Assert-Endpoint -Stage "Caja consulta alumnos" -Method "GET" -Path "/alumnos?page=0&size=1" -Actor "demo-caja" -ExpectedStatus 200
    Assert-Endpoint -Stage "Caja consulta pagos" -Method "GET" -Path "/pagos/alumno/${alumnoId}?page=0&size=1" -Actor "demo-caja" -ExpectedStatus 200
    Assert-Endpoint -Stage "Caja consulta caja" -Method "GET" -Path "/caja/resumen?desde=$reportFrom&hasta=$reportTo&page=0&size=1" -Actor "demo-caja" -ExpectedStatus 200
    Assert-Endpoint -Stage "Caja consulta stock" -Method "GET" -Path "/stocks?page=0&size=1" -Actor "demo-caja" -ExpectedStatus 200
    Assert-Endpoint -Stage "Caja consulta configuración" -Method "GET" -Path "/metodos-pago" -Actor "demo-caja" -ExpectedStatus 200
    Assert-Endpoint -Stage "Caja autoriza registro de pago" -Method "POST" -Path "/pagos" -Actor "demo-caja" -ExpectedStatus 400 -Body @{}
    Assert-Endpoint -Stage "Caja no administra egresos por escritura" -Method "POST" -Path "/egresos" -Actor "demo-caja" -ExpectedStatus 403
    Assert-Endpoint -Stage "Caja no consulta inscripciones" -Method "GET" -Path "/inscripciones?page=0&size=1" -Actor "demo-caja" -ExpectedStatus 403
    Assert-Endpoint -Stage "Caja no consulta reportes" -Method "GET" -Path "/reportes/mensualidades?desde=$reportFrom&hasta=$reportTo" -Actor "demo-caja" -ExpectedStatus 403
    Assert-Endpoint -Stage "Caja no consulta profesores" -Method "GET" -Path "/profesores" -Actor "demo-caja" -ExpectedStatus 403
    Assert-Endpoint -Stage "Caja no administra egresos" -Method "GET" -Path "/egresos?page=0&size=1" -Actor "demo-caja" -ExpectedStatus 403

    Invoke-IntegrityChecks
    $rbacAfterHttp = Get-RbacSnapshot
    Assert-Equal -Actual $rbacAfterHttp -Expected $rbacBefore -Message "Los smoke HTTP modificaron RBAC"
    Add-Result -Stage "RBAC tras smoke HTTP" -Result "PASS" -Detail "Catálogo y matrices sin cambios"

    Stop-Backend
    Invoke-DemoSeed | Out-Null
    $snapshotSecondRaw = Get-DemoSnapshot
    $snapshotSecond = $snapshotSecondRaw | ConvertFrom-Json
    Assert-ExpectedDemoCounts -Snapshot $snapshotSecond
    Assert-Equal -Actual $snapshotSecondRaw -Expected $snapshotFirstRaw -Message "La segunda ejecución cambió conteos, IDs o totales"
    Assert-Equal -Actual (Get-RbacSnapshot) -Expected $rbacBefore -Message "La segunda ejecución modificó RBAC"
    Add-Result -Stage "Segunda aplicación del seed" -Result "PASS" -Detail "Idempotencia completa; snapshot idéntico"

    Start-Backend
    Wait-BackendAvailable
    $actorTokens.Clear()
    Login-Actor -Username "demo-superadmin" -ExpectedRole "SUPERADMIN" | Out-Null
    Invoke-Api -Method "GET" -Path "/usuarios/perfil" -Token $actorTokens["demo-superadmin"] -ExpectedStatus 200 | Out-Null
    Add-Result -Stage "Login posterior a reejecución" -Result "PASS" -Detail "Backend y credenciales continúan operativos"

    Stop-Backend
    Assert-NoSecretsInTemporaryFiles
    Add-Result -Stage "Validación integral" -Result "PASS" -Detail "Seed reproducible, autorizaciones y datos consistentes"
}
catch {
    $exitCode = 1
    $caughtMessage = Redact $_.Exception.Message
    Add-Result -Stage "Validación integral" -Result "FAIL" -Detail $caughtMessage
    Show-Diagnostics
}
finally {
    try { Stop-Backend } catch { }
    if ($null -ne $http) {
        try { $http.Dispose() } catch { }
        $http = $null
    }

    if ($stackAttempted) {
        try {
            Remove-IsolatedDockerResources
            Add-Result -Stage "Limpieza Docker" -Result "PASS" -Detail "Contenedores, red y volúmenes aislados eliminados"
        }
        catch {
            if ($exitCode -eq 0) { $exitCode = 1 }
            Add-Result -Stage "Limpieza Docker" -Result "FAIL" -Detail (Redact $_.Exception.Message)
        }
    }

    try {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
        Add-Result -Stage "Limpieza temporal" -Result "PASS" -Detail "Archivos auxiliares eliminados"
    }
    catch {
        if ($exitCode -eq 0) { $exitCode = 1 }
        Add-Result -Stage "Limpieza temporal" -Result "FAIL" -Detail (Redact $_.Exception.Message)
    }

    try { Restore-Environment }
    catch {
        if ($exitCode -eq 0) { $exitCode = 1 }
        Add-Result -Stage "Restauración de entorno" -Result "FAIL" -Detail (Redact $_.Exception.Message)
    }

    $script:demoPasswords.Clear()
    $script:demoHashes.Clear()
    $actorTokens.Clear()
    $secretValues.Clear()
    $postgresPassword = $null
    $jwtSecret = $null
}

Write-Host ""
Write-Host "Resumen de validación" -ForegroundColor Cyan
$results | Format-Table -AutoSize Etapa, Resultado, Detalle
Write-Host "Duración: $([math]::Round(((Get-Date) - $startedAt).TotalSeconds, 1)) segundos"

if ($exitCode -ne 0) {
    $finalError = if ([string]::IsNullOrWhiteSpace($caughtMessage)) { "La validación del seed demo falló" } else { $caughtMessage }
    [Console]::Error.WriteLine($finalError)
    exit $exitCode
}
exit 0
