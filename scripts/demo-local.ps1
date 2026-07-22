param(
    [Parameter(Mandatory)]
    [ValidateSet("Start", "Status", "Stop", "Reset", "SeedNative")]
    [string] $Action,
    [ValidatePattern('^[A-Za-z0-9._:-]+$')]
    [string] $DatabaseHost = "localhost",
    [ValidateRange(1, 65535)]
    [int] $DatabasePort = 5432,
    [ValidatePattern('^[A-Za-z0-9_.-]+$')]
    [string] $DatabaseName = "gestudio_db",
    [ValidatePattern('^[A-Za-z0-9_.-]+$')]
    [string] $DatabaseUser = "postgres",
    [string] $PsqlPath = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Net.Http

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$backendRoot = Join-Path $repoRoot "backend"
$composeFile = Join-Path $repoRoot "docker-compose.yml"
$seedPath = Join-Path $PSScriptRoot "gestudio_demo_seed_full.sql"
$migrationRoot = Join-Path $backendRoot "src/main/resources/db/migration"
$project = "gestudio-demo-local"
$postgresDb = "gestudio_demo_local"
$postgresUser = "gestudio_demo_local"
$postgresPort = 15432
$backendPort = 18080
$frontendPort = 18081
$backendUrl = "http://localhost:$backendPort"
$apiBase = "$backendUrl/api"
$frontendUrl = "http://localhost:$frontendPort"
$backendImage = "gestudio-backend:demo-local"
$frontendImage = "gestudio-frontend:demo-local"
$cookieName = "gestudio_demo_refresh"
$deadline = (Get-Date).AddMinutes(45)
$isWindowsHost = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
$tempRoot = $null
$postgresPassword = $null
$databasePassword = $null
$jwtSecret = $null
$nativePsqlPath = $null
$javaExe = $null
$javacExe = $null
$bcryptClasspath = $null
$demoPasswords = @{}
$demoHashes = @{}
$securePasswords = @{}
$actorTokens = @{}
$secretValues = [Collections.Generic.List[string]]::new()
$httpClients = [Collections.Generic.List[object]]::new()
$originalEnvironment = @{}
$stackAttempted = $false
$exitCode = 0
$caughtMessage = $null

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

function Assert-True {
    param([bool] $Condition, [Parameter(Mandatory)][string] $Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param($Actual, $Expected, [Parameter(Mandatory)][string] $Message)
    if ($Actual -ne $Expected) {
        throw "$Message (esperado=$Expected, actual=$Actual)"
    }
}

function Assert-Deadline {
    if ((Get-Date) -gt $script:deadline) {
        throw "Se agotó el timeout global de 45 minutos"
    }
}

function Pass {
    param([Parameter(Mandatory)][string] $Name, [string] $Detail = "")
    $suffix = if ([string]::IsNullOrWhiteSpace($Detail)) { "" } else { " - $Detail" }
    Write-Host "[PASS] $Name$suffix" -ForegroundColor Green
}

function New-HexSecret {
    param([Parameter(Mandatory)][int] $Bytes)

    $buffer = New-Object byte[] $Bytes
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($buffer) }
    finally { $rng.Dispose() }
    return [BitConverter]::ToString($buffer).Replace("-", "").ToLowerInvariant()
}

function Set-ScopedEnvironmentVariable {
    param([Parameter(Mandatory)][string] $Name, [AllowNull()][string] $Value)

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
        if ($Capture) {
            $output = @(& $FilePath @Arguments 2>&1)
        }
        else {
            $tail = [Collections.Generic.Queue[string]]::new()
            & $FilePath @Arguments 2>&1 | ForEach-Object {
                $line = Redact $_.ToString()
                Write-Host $line
                $tail.Enqueue($line)
                if ($tail.Count -gt 100) { [void]$tail.Dequeue() }
            }
        }
        $code = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousErrorAction }

    $text = if ($Capture) {
        ($output | ForEach-Object { $_.ToString() }) -join "`n"
    }
    else {
        @($tail) -join "`n"
    }
    if ($code -ne 0) {
        $errorTail = (($text -split "`r?`n") | Select-Object -Last 100) -join "`n"
        throw "$([IO.Path]::GetFileName($FilePath)) falló con código ${code}: $(Redact $errorTail)"
    }
    if ($Capture) { return $text.Trim() }
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

function Invoke-PsqlInput {
    param([Parameter(Mandatory)][string] $InputText)

    if ($Action -eq "SeedNative") {
        return Invoke-NativePsql -InputText $InputText
    }

    Assert-Deadline
    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = "docker"
    $escapedCompose = $script:composeFile.Replace('"', '\"')
    $psi.Arguments = "compose -f `"$escapedCompose`" -p $($script:project) exec -T db psql -X -q -v ON_ERROR_STOP=1 -U $($script:postgresUser) -d $($script:postgresDb)"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    if ($psi.PSObject.Properties.Name -contains "StandardInputEncoding") {
        $psi.StandardInputEncoding = New-Object Text.UTF8Encoding($false)
    }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $psi
    [void]$process.Start()
    try {
        $process.StandardInput.Write($InputText)
        $process.StandardInput.Close()
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        $code = $process.ExitCode
    }
    finally { $process.Dispose() }

    if ($code -ne 0) {
        throw "psql falló con código ${code}: $(Redact ($stdout + "`n" + $stderr))"
    }
    return ($stdout + "`n" + $stderr).Trim()
}

function Invoke-Sql {
    param([Parameter(Mandatory)][string] $Query)

    if ($Action -eq "SeedNative") {
        return Invoke-NativePsql -InputText ($Query + "`n") -TuplesOnly
    }

    $arguments = @(
        "compose", "-f", $script:composeFile, "-p", $script:project,
        "exec", "-T", "db", "psql", "-X", "-q",
        "-v", "ON_ERROR_STOP=1", "-U", $script:postgresUser, "-d", $script:postgresDb,
        "-A", "-t", "-F", "|", "-c", $Query
    )
    return Invoke-Docker -Arguments $arguments -Capture
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
        $state = Get-ServiceState -Service $Service
        if ($state.State -eq "running" -and $state.Health -eq "healthy") { return }
        if ($state.State -in @("exited", "dead")) {
            throw "$Service terminó antes de estar healthy"
        }
        Start-Sleep -Seconds 2
    }
    throw "Timeout esperando $Service healthy"
}

function Assert-PortAvailable {
    param([Parameter(Mandatory)][int] $Port, [Parameter(Mandatory)][string] $Purpose)

    $containers = Invoke-Docker -Arguments @(
        "ps", "--filter", "publish=$Port", "--format", "{{.ID}}|{{.Names}}"
    ) -Capture
    if (-not [string]::IsNullOrWhiteSpace($containers)) {
        $ownText = Invoke-Docker -Arguments @(
            "ps", "--filter", "publish=$Port", "--filter", "label=com.docker.compose.project=$($script:project)",
            "--format", "{{.ID}}"
        ) -Capture
        $ownIds = @($ownText -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $foreign = @($containers -split "`r?`n" | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_) -and $ownIds -notcontains $_.Split("|")[0]
        })
        if ($foreign.Count -gt 0) {
            $parts = $foreign[0].Split("|")
            throw "Puerto $Port ($Purpose) ocupado por el contenedor Docker '$($parts[1])' [$($parts[0])]"
        }
        return
    }

    $probe = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Any, $Port)
    try {
        $probe.Start()
    }
    catch [Net.Sockets.SocketException] {
        throw "Puerto $Port ($Purpose) ocupado por un proceso del host"
    }
    finally {
        $probe.Stop()
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
    return $code -eq 0 -and (($output | ForEach-Object { $_.ToString() }) -join "`n") -match 'version\s+"21(?:\.|\")'
}

function Resolve-Java21 {
    $javaName = if ($script:isWindowsHost) { "java.exe" } else { "java" }
    $javacName = if ($script:isWindowsHost) { "javac.exe" } else { "javac" }
    $candidates = [Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
        $candidates.Add((Join-Path $env:JAVA_HOME "bin/$javaName"))
    }
    $javaCommand = Get-Command java -ErrorAction SilentlyContinue
    if ($null -ne $javaCommand) { $candidates.Add($javaCommand.Source) }

    $roots = if ($script:isWindowsHost) {
        @("$env:ProgramFiles\Java", "$env:ProgramFiles\Amazon Corretto", "$env:ProgramFiles\Eclipse Adoptium", "$env:USERPROFILE\.jdks")
    }
    else { @("/usr/lib/jvm", "/opt/java", "$HOME/.jdks") }
    foreach ($root in $roots) {
        if (-not [string]::IsNullOrWhiteSpace($root) -and (Test-Path -LiteralPath $root -PathType Container)) {
            Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $candidates.Add((Join-Path $_.FullName "bin/$javaName"))
            }
        }
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (Test-Java21Executable -Candidate $candidate) {
            $javaHome = Split-Path (Split-Path ([IO.Path]::GetFullPath($candidate)) -Parent) -Parent
            $javac = Join-Path $javaHome "bin/$javacName"
            if (Test-Path -LiteralPath $javac -PathType Leaf) {
                return [pscustomobject]@{ Home = $javaHome; Java = [IO.Path]::GetFullPath($candidate); Javac = $javac }
            }
        }
    }
    throw "No se encontró un JDK 21 completo; configure JAVA_HOME"
}

function Resolve-Psql {
    if (-not [string]::IsNullOrWhiteSpace($PsqlPath)) {
        $resolved = [IO.Path]::GetFullPath($PsqlPath)
        if (Test-Path -LiteralPath $resolved -PathType Leaf) { return $resolved }
        throw "No existe psql en la ruta indicada: $resolved"
    }

    $command = Get-Command psql -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }

    $roots = @(
        (Join-Path $env:ProgramFiles "PostgreSQL"),
        $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} "PostgreSQL" })
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_ -PathType Container) }
    $candidates = foreach ($root in $roots) {
        Get-ChildItem -LiteralPath $root -Filter psql.exe -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '[\\/]pgAdmin 4[\\/]runtime[\\/]' }
    }
    $candidate = $candidates | Sort-Object FullName -Descending | Select-Object -First 1
    if ($null -ne $candidate) { return $candidate.FullName }
    throw "No se encontró psql; indique -PsqlPath con la ruta de psql.exe"
}

function Read-DatabasePassword {
    if (-not [string]::IsNullOrEmpty($env:PGPASSWORD)) {
        $script:databasePassword = $env:PGPASSWORD
        Add-Secret $script:databasePassword
        return
    }

    $secure = Read-Host "Contraseña PostgreSQL para $DatabaseUser@$DatabaseHost" -AsSecureString
    $plain = ConvertFrom-SecurePassword -SecurePassword $secure
    if ([string]::IsNullOrEmpty($plain)) {
        $secure.Dispose()
        throw "La contraseña PostgreSQL no puede estar vacía; use PGPASSWORD si la conexión requiere otra configuración"
    }
    $script:securePasswords["postgresql"] = $secure
    $script:databasePassword = $plain
    Add-Secret $plain
}

function Invoke-NativePsql {
    param(
        [Parameter(Mandatory)][string] $InputText,
        [switch] $TuplesOnly
    )

    Assert-Deadline
    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $script:nativePsqlPath
    $formatArguments = if ($TuplesOnly) { " -A -t -F `"|`"" } else { "" }
    $psi.Arguments = "-X -q -v ON_ERROR_STOP=1 -h `"$DatabaseHost`" -p $DatabasePort -U `"$DatabaseUser`" -d `"$DatabaseName`"$formatArguments"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.EnvironmentVariables["PGPASSWORD"] = $script:databasePassword
    if ($psi.PSObject.Properties.Name -contains "StandardInputEncoding") {
        $psi.StandardInputEncoding = New-Object Text.UTF8Encoding($false)
    }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $psi
    [void]$process.Start()
    try {
        $process.StandardInput.Write($InputText)
        $process.StandardInput.Close()
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        $code = $process.ExitCode
    }
    finally { $process.Dispose() }

    if ($code -ne 0) {
        throw "psql local falló con código ${code}: $(Redact ($stdout + "`n" + $stderr))"
    }
    return ($stdout + "`n" + $stderr).Trim()
}

function ConvertFrom-SecurePassword {
    param([Parameter(Mandatory)][Security.SecureString] $SecurePassword)

    $pointer = [IntPtr]::Zero
    try {
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
        $value = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
        while ($value.Length -gt 0 -and $value[0] -eq [char]0xFEFF) {
            $value = $value.Substring(1)
        }
        return $value
    }
    finally {
        if ($pointer -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
        }
    }
}

function Read-DemoPasswords {
    foreach ($username in @("demo-superadmin", "demo-direccion", "demo-administrador", "demo-secretaria", "demo-caja")) {
        while ($true) {
            $secure = Read-Host "Contraseña para $username" -AsSecureString
            $plain = ConvertFrom-SecurePassword -SecurePassword $secure
            $bytes = [Text.Encoding]::UTF8.GetByteCount($plain)
            if ([string]::IsNullOrWhiteSpace($plain)) {
                Write-Host "La contraseña no puede estar vacía ni contener sólo espacios." -ForegroundColor Yellow
                $plain = $null
                $secure.Dispose()
                continue
            }
            if ($bytes -gt 72) {
                Write-Host "BCrypt admite como máximo 72 bytes UTF-8; se recibieron $bytes." -ForegroundColor Yellow
                $plain = $null
                $secure.Dispose()
                continue
            }
            $script:securePasswords[$username] = $secure
            $script:demoPasswords[$username] = $plain
            Add-Secret $plain
            break
        }
    }
}

function Initialize-BcryptHelper {
    $jdk = Resolve-Java21
    $script:javaExe = $jdk.Java
    $script:javacExe = $jdk.Javac
    Set-ScopedEnvironmentVariable -Name "JAVA_HOME" -Value $jdk.Home
    Set-ScopedEnvironmentVariable -Name "PATH" -Value ((Join-Path $jdk.Home "bin") + [IO.Path]::PathSeparator + $env:PATH)

    $wrapper = if ($script:isWindowsHost) { Join-Path $script:backendRoot "mvnw.cmd" } else { Join-Path $script:backendRoot "mvnw" }
    if (-not (Test-Path -LiteralPath $wrapper -PathType Leaf)) { throw "Falta Maven Wrapper en backend" }
    $classpathFile = Join-Path $script:tempRoot "runtime-classpath.txt"
    Push-Location $script:backendRoot
    try {
        Invoke-Native -FilePath $wrapper -Arguments @(
            "-q", "-DincludeScope=runtime", "-Dmdep.outputFile=$classpathFile", "dependency:build-classpath"
        ) -Capture | Out-Null
    }
    finally { Pop-Location }

    $runtimeClasspath = [IO.File]::ReadAllText($classpathFile).Trim()
    if ([string]::IsNullOrWhiteSpace($runtimeClasspath)) { throw "Maven no produjo el classpath BCrypt" }
    $sourcePath = Join-Path $script:tempRoot "GestudioDemoBcrypt.java"
    $source = @'
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;

public final class GestudioDemoBcrypt {
    private static String normalize(String value) {
        while (!value.isEmpty() && value.charAt(0) == '\uFEFF') value = value.substring(1);
        return value;
    }

    public static void main(String[] args) throws Exception {
        BCryptPasswordEncoder encoder = new BCryptPasswordEncoder(12);
        boolean verify = args.length > 0 && "verify".equals(args[0]);
        try (BufferedReader reader = new BufferedReader(
                new InputStreamReader(System.in, StandardCharsets.UTF_8))) {
            String password;
            while ((password = reader.readLine()) != null) {
                password = normalize(password);
                if (password.getBytes(StandardCharsets.UTF_8).length > 72) System.exit(4);
                if (verify) {
                    String hash = reader.readLine();
                    if (hash == null || !encoder.matches(password, hash)) System.exit(3);
                } else {
                    System.out.println(encoder.encode(password));
                }
            }
        }
    }
}
'@
    [IO.File]::WriteAllText($sourcePath, $source, (New-Object Text.UTF8Encoding($false)))
    Invoke-Native -FilePath $script:javacExe -Arguments @("-encoding", "UTF-8", "-cp", $runtimeClasspath, $sourcePath) -Capture | Out-Null
    $script:bcryptClasspath = $script:tempRoot + [IO.Path]::PathSeparator + $runtimeClasspath
}

function Invoke-BcryptHelper {
    param([Parameter(Mandatory)][string] $InputText, [switch] $Verify)

    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $script:javaExe
    $mode = if ($Verify) { " verify" } else { "" }
    $psi.Arguments = "-cp `"$($script:bcryptClasspath.Replace('"', '\"'))`" GestudioDemoBcrypt$mode"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    if ($psi.PSObject.Properties.Name -contains "StandardInputEncoding") {
        $psi.StandardInputEncoding = New-Object Text.UTF8Encoding($false)
    }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $psi
    [void]$process.Start()
    try {
        $process.StandardInput.Write($InputText)
        $process.StandardInput.Close()
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        $code = $process.ExitCode
    }
    finally { $process.Dispose() }
    if ($code -ne 0) { throw "BCrypt falló con código ${code}: $(Redact $stderr)" }
    return $stdout.Trim()
}

function New-BcryptHashes {
    foreach ($username in @($script:demoPasswords.Keys | Sort-Object)) {
        $hash = Invoke-BcryptHelper -InputText ($script:demoPasswords[$username] + "`n")
        Assert-True -Condition ($hash -match '^\$2[aby]\$12\$.{53}$') -Message "Hash BCrypt incompatible para $username"
        $script:demoHashes[$username] = $hash
        Add-Secret $hash
    }
    Assert-Equal -Actual @($script:demoHashes.Values | Select-Object -Unique).Count -Expected 5 -Message "Cada usuario debe tener un BCrypt diferente"
}

function Assert-BcryptPair {
    param([Parameter(Mandatory)][string] $Password, [Parameter(Mandatory)][string] $Hash, [Parameter(Mandatory)][string] $Username)
    Invoke-BcryptHelper -InputText ($Password + "`n" + $Hash + "`n") -Verify | Out-Null
}

function Get-BusinessDate {
    try { $zone = [TimeZoneInfo]::FindSystemTimeZoneById("America/Argentina/Buenos_Aires") }
    catch { $zone = [TimeZoneInfo]::FindSystemTimeZoneById("Argentina Standard Time") }
    return [TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $zone).Date
}

function Get-AnchorDate {
    $stored = Invoke-Sql -Query "SELECT substring(otras_notas from 'referencia: ([0-9]{4}-[0-9]{2}-[0-9]{2})') FROM alumnos WHERE documento='49287134';"
    if (-not [string]::IsNullOrWhiteSpace($stored)) { return [datetime]::ParseExact($stored, "yyyy-MM-dd", $null) }
    return Get-BusinessDate
}

function Get-LocalMigrationManifest {
    $entries = @(Get-ChildItem -LiteralPath $script:migrationRoot -Filter "V*__*.sql" -File | ForEach-Object {
        if ($_.Name -notmatch '^V(?<version>[0-9]+)__.+\.sql$') {
            throw "Nombre de migración Flyway inválido: $($_.Name)"
        }
        [pscustomobject]@{ Version = [int]$matches.version; Script = $_.Name }
    } | Sort-Object Version)
    if ($entries.Count -eq 0) { throw "No hay migraciones Flyway locales" }
    if (@($entries.Version | Select-Object -Unique).Count -ne $entries.Count) {
        throw "Hay versiones Flyway locales duplicadas"
    }
    for ($index = 0; $index -lt $entries.Count; $index++) {
        if ($entries[$index].Version -ne ($index + 1)) {
            throw "La cadena Flyway local no es contigua desde V1"
        }
    }
    if (@($entries | Where-Object { $_.Script -match '(?i)demo.*seed|seed.*demo' }).Count -ne 0) {
        throw "Existe una migración Flyway demo"
    }
    return [pscustomobject]@{
        Count = $entries.Count
        LatestVersion = $entries[-1].Version
        LatestScript = $entries[-1].Script
        Scripts = @($entries.Script)
    }
}

function Get-RepositoryRevision {
    $revision = Invoke-Native -FilePath "git" -Arguments @("-C", $script:repoRoot, "rev-parse", "HEAD") -Capture
    if ($revision -notmatch '^[0-9a-f]{40}$') { throw "No se pudo resolver el SHA Git del checkout" }
    return $revision
}

function Get-SourceFingerprint {
    param([Parameter(Mandatory)][ValidateSet('backend', 'frontend')][string] $RelativeRoot)

    $tree = Invoke-Native -FilePath "git" -Arguments @("-C", $script:repoRoot, "rev-parse", "HEAD:$RelativeRoot") -Capture
    $diff = Invoke-Native -FilePath "git" -Arguments @(
        "-C", $script:repoRoot, "diff", "--no-ext-diff", "--no-color", "--binary", "HEAD", "--", $RelativeRoot
    ) -Capture
    $untracked = Invoke-Native -FilePath "git" -Arguments @(
        "-C", $script:repoRoot, "ls-files", "--others", "--exclude-standard", "--", $RelativeRoot
    ) -Capture
    $untrackedMaterial = [Collections.Generic.List[string]]::new()
    foreach ($path in @($untracked -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object)) {
        $hash = Invoke-Native -FilePath "git" -Arguments @(
            "-C", $script:repoRoot, "hash-object", "--no-filters", "--", $path
        ) -Capture
        $untrackedMaterial.Add("$path|$hash")
    }

    $material = $tree + "`n" + $diff + "`n" + ($untrackedMaterial -join "`n")
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($material)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Get-ComposeSha {
    return (Get-FileHash -LiteralPath $script:composeFile -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-RbacSnapshot {
    return Invoke-Sql -Query @"
SELECT md5(jsonb_build_object(
    'roles', (SELECT COALESCE(jsonb_agg(to_jsonb(r) ORDER BY r.id), '[]'::jsonb) FROM roles r),
    'permissions', (SELECT COALESCE(jsonb_agg(to_jsonb(p) ORDER BY p.id), '[]'::jsonb) FROM permisos p),
    'matrix', (SELECT COALESCE(jsonb_agg(to_jsonb(rp) ORDER BY rp.rol_id, rp.permiso_id), '[]'::jsonb) FROM rol_permisos rp)
)::text);
"@
}

function Get-DatabaseSnapshot {
    return Invoke-Sql -Query @'
CREATE OR REPLACE FUNCTION pg_temp.gestudio_demo_snapshot()
RETURNS text LANGUAGE plpgsql AS $$
DECLARE
    item record;
    row_count bigint;
    table_hash text;
    combined text := '';
BEGIN
    FOR item IN
        SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename
    LOOP
        EXECUTE format(
            'SELECT count(*), md5(COALESCE(string_agg(to_jsonb(t)::text, E''\n'' ORDER BY to_jsonb(t)::text), '''')) FROM public.%I t',
            item.tablename
        ) INTO row_count, table_hash;
        combined := combined || item.tablename || '|' || row_count::text || '|' || table_hash || E'\n';
    END LOOP;
    RETURN md5(combined);
END;
$$;
SELECT pg_temp.gestudio_demo_snapshot();
'@
}

function Test-DemoSeedContract {
    $result = Invoke-Sql -Query @'
WITH demo_students AS (
    SELECT id FROM alumnos WHERE email LIKE '%@correo.local'
), demo_professors AS (
    SELECT id FROM profesores WHERE telefono LIKE '+54 9 11 5555-11%'
), demo_disciplines AS (
    SELECT id FROM disciplinas WHERE nombre IN (
        'Ballet Inicial (4 a 6 años)', 'Jazz Infantil (7 a 10 años)', 'Danza Urbana Teen',
        'Danza Contemporánea', 'Ritmos Latinos Adultos', 'Entrenamiento Escénico'
    )
), demo_enrollments AS (
    SELECT i.id FROM inscripciones i JOIN demo_students a ON a.id = i.alumno_id
), demo_charges AS (
    SELECT id FROM cargos WHERE idempotency_key LIKE 'demo-seed:v1:%'
), demo_payments AS (
    SELECT id FROM pagos WHERE idempotency_key LIKE 'demo-seed:v1:%'
), actual AS (
    SELECT jsonb_build_object(
        'usuarios', (SELECT count(*) FROM usuarios WHERE lower(nombre_usuario) LIKE 'demo-%'),
        'usuario_roles', (SELECT count(*) FROM usuario_roles ur JOIN usuarios u ON u.id=ur.usuario_id WHERE lower(u.nombre_usuario) LIKE 'demo-%'),
        'salones', (SELECT count(*) FROM salones WHERE nombre IN ('Sala Principal','Estudio Infantil','Sala de Ensayo')),
        'profesores', (SELECT count(*) FROM demo_professors),
        'observaciones_profesores', (SELECT count(*) FROM observaciones_profesores op JOIN demo_professors p ON p.id=op.profesor_id WHERE op.observacion='Seguimiento pedagógico trimestral al día.'),
        'bonificaciones', (SELECT count(*) FROM bonificaciones WHERE descripcion IN ('Descuento hermanos 10%','Beca institucional 25%','Convenio familiar','Promoción apertura 2025')),
        'recargos', (SELECT count(*) FROM recargos WHERE descripcion IN ('Mora por vencimiento 5%','Gastos administrativos','Recargo extraordinario 2025')),
        'metodo_pagos', (SELECT count(*) FROM metodo_pagos WHERE descripcion IN ('Efectivo','Transferencia bancaria','Tarjeta de débito','Tarjeta de crédito')),
        'sub_conceptos', (SELECT count(*) FROM sub_conceptos WHERE descripcion IN ('Indumentaria','Materiales de clase','Eventos y talleres','Trámites administrativos')),
        'conceptos', (SELECT count(*) FROM conceptos WHERE descripcion IN ('Remera institucional','Medias de danza','Kit de práctica','Cuaderno coreográfico','Entrada muestra anual','Taller intensivo de fin de semana','Certificado de alumno regular','Duplicado de credencial')),
        'stocks', (SELECT count(*) FROM stocks WHERE codigo_barras IN ('7790000000012','7790000000029','7790000000036','7790000000043','7790000000050','7790000000067')),
        'disciplinas', (SELECT count(*) FROM demo_disciplines),
        'disciplina_horarios', (SELECT count(*) FROM disciplina_horarios h JOIN demo_disciplines d ON d.id=h.disciplina_id),
        'alumnos', (SELECT count(*) FROM demo_students),
        'inscripciones', (SELECT count(*) FROM demo_enrollments),
        'disciplina_tarifas', (SELECT count(*) FROM disciplina_tarifas t JOIN demo_disciplines d ON d.id=t.disciplina_id),
        'inscripcion_condiciones_economicas', (SELECT count(*) FROM inscripcion_condiciones_economicas c JOIN demo_enrollments i ON i.id=c.inscripcion_id),
        'mensualidades', (SELECT count(*) FROM mensualidades m JOIN demo_enrollments i ON i.id=m.inscripcion_id),
        'matriculas', (SELECT count(*) FROM matriculas m JOIN demo_students a ON a.id=m.alumno_id),
        'asistencias_mensuales', (SELECT count(*) FROM asistencias_mensuales am JOIN demo_disciplines d ON d.id=am.disciplina_id),
        'asistencias_alumno_mensual', (SELECT count(*) FROM asistencias_alumno_mensual aam JOIN demo_enrollments i ON i.id=aam.inscripcion_id),
        'asistencias_diarias', (SELECT count(*) FROM asistencias_diarias ad JOIN asistencias_alumno_mensual aam ON aam.id=ad.asistencia_alumno_mensual_id JOIN demo_enrollments i ON i.id=aam.inscripcion_id),
        'ventas_stock', (SELECT count(*) FROM ventas_stock WHERE idempotency_key LIKE 'demo-seed:v1:%'),
        'cargos', (SELECT count(*) FROM demo_charges),
        'cargo_liquidaciones', (SELECT count(*) FROM cargo_liquidaciones cl JOIN demo_charges c ON c.id=cl.cargo_id),
        'pagos', (SELECT count(*) FROM demo_payments),
        'aplicaciones_pago', (SELECT count(*) FROM aplicaciones_pago ap JOIN demo_payments p ON p.id=ap.pago_id),
        'egresos', (SELECT count(*) FROM egresos WHERE idempotency_key LIKE 'demo-seed:v1:%'),
        'movimientos_caja', (SELECT count(*) FROM movimientos_caja WHERE idempotency_key LIKE 'demo-seed:v1:%'),
        'movimientos_credito', (SELECT count(*) FROM movimientos_credito WHERE idempotency_key LIKE 'demo-seed:v1:%'),
        'movimientos_stock', (SELECT count(*) FROM movimientos_stock WHERE idempotency_key LIKE 'demo-seed:v1:%'),
        'recibos', (SELECT count(*) FROM recibos r JOIN demo_payments p ON p.id=r.pago_id),
        'recibos_pendientes', (SELECT count(*) FROM recibos_pendientes rp JOIN demo_payments p ON p.id=rp.pago_id)
    ) AS counts
), expected AS (
    SELECT jsonb_build_object(
        'usuarios',5,'usuario_roles',5,'salones',3,'profesores',6,'observaciones_profesores',6,
        'bonificaciones',4,'recargos',3,'metodo_pagos',4,'sub_conceptos',4,'conceptos',8,
        'stocks',6,'disciplinas',6,'disciplina_horarios',11,'alumnos',28,'inscripciones',34,
        'disciplina_tarifas',12,'inscripcion_condiciones_economicas',40,'mensualidades',70,
        'matriculas',26,'asistencias_mensuales',6,'asistencias_alumno_mensual',18,
        'asistencias_diarias',54,'ventas_stock',6,'cargos',115,'cargo_liquidaciones',115,
        'pagos',48,'aplicaciones_pago',82,'egresos',7,'movimientos_caja',61,
        'movimientos_credito',11,'movimientos_stock',14,'recibos',48,'recibos_pendientes',48
    ) AS counts
), expected_matrix(role_code, permission_code) AS (
    SELECT 'SUPERADMIN', codigo FROM permisos
    UNION ALL SELECT 'DIRECCION', codigo FROM permisos WHERE codigo <> 'PERM_ROLES_ADMIN'
    UNION ALL SELECT 'ADMINISTRADOR', codigo FROM permisos WHERE codigo <> 'PERM_ROLES_ADMIN'
    UNION ALL SELECT 'SECRETARIA', codigo FROM permisos WHERE codigo IN ('PERM_APP_ACCESO','PERM_PAGOS_REGISTRAR','PERM_CREDITOS_CONSUMIR','PERM_CONDICIONES_ECONOMICAS_ADMIN','PERM_ALUMNOS_LEER','PERM_ALUMNOS_ADMIN','PERM_INSCRIPCIONES_LEER','PERM_INSCRIPCIONES_ADMIN','PERM_DISCIPLINAS_LEER','PERM_PROFESORES_LEER','PERM_ASISTENCIAS_LEER','PERM_ASISTENCIAS_REGISTRAR','PERM_PAGOS_LEER','PERM_CAJA_LEER','PERM_STOCK_LEER','PERM_REPORTES_LEER','PERM_CONFIG_LEER')
    UNION ALL SELECT 'CAJA', codigo FROM permisos WHERE codigo IN ('PERM_APP_ACCESO','PERM_ALUMNOS_LEER','PERM_PAGOS_LEER','PERM_PAGOS_REGISTRAR','PERM_CAJA_LEER','PERM_STOCK_LEER','PERM_CONFIG_LEER','PERM_CREDITOS_CONSUMIR')
), actual_matrix AS (
    SELECT r.codigo, p.codigo FROM roles r JOIN rol_permisos rp ON rp.rol_id=r.id JOIN permisos p ON p.id=rp.permiso_id
    WHERE r.codigo IN ('SUPERADMIN','DIRECCION','ADMINISTRADOR','SECRETARIA','CAJA','PROFESOR')
), matrix_diff AS (
    (SELECT * FROM expected_matrix EXCEPT SELECT * FROM actual_matrix)
    UNION ALL
    (SELECT * FROM actual_matrix EXCEPT SELECT * FROM expected_matrix)
), expected_demo_users(username, role_code) AS (
    VALUES ('demo-superadmin','SUPERADMIN'),('demo-direccion','DIRECCION'),
           ('demo-administrador','ADMINISTRADOR'),('demo-secretaria','SECRETARIA'),('demo-caja','CAJA')
), actual_demo_users AS (
    SELECT lower(u.nombre_usuario), r.codigo
    FROM usuarios u JOIN usuario_roles ur ON ur.usuario_id=u.id JOIN roles r ON r.id=ur.rol_id
    WHERE lower(u.nombre_usuario) LIKE 'demo-%' AND u.activo
), demo_user_diff AS (
    (SELECT * FROM expected_demo_users EXCEPT SELECT * FROM actual_demo_users)
    UNION ALL
    (SELECT * FROM actual_demo_users EXCEPT SELECT * FROM expected_demo_users)
)
SELECT CASE WHEN
    (SELECT counts FROM actual) = (SELECT counts FROM expected)
    AND (SELECT sum(value::integer) FROM actual, LATERAL jsonb_each_text(counts)) = 914
    AND (SELECT count(*) FROM roles) = 6
    AND (SELECT count(*) FROM permisos WHERE activo AND sistema) = 32
    AND (SELECT count(*) FROM rol_permisos) = 119
    AND NOT EXISTS (SELECT 1 FROM matrix_diff)
    AND NOT EXISTS (SELECT 1 FROM demo_user_diff)
    AND EXISTS (
        SELECT 1 FROM alumnos WHERE documento='49287134' AND activo
          AND extract(month FROM fecha_nacimiento)=extract(month FROM (CURRENT_TIMESTAMP AT TIME ZONE 'America/Argentina/Buenos_Aires')::date)
          AND extract(day FROM fecha_nacimiento)=extract(day FROM (CURRENT_TIMESTAMP AT TIME ZONE 'America/Argentina/Buenos_Aires')::date)
          AND otras_notas LIKE 'Ficha revisada por administración. Actualización de referencia: %'
    )
THEN 'true' ELSE 'false' END;
'@
    return $result -eq 'true'
}

function Invoke-DemoSeed {
    param(
        [Parameter(Mandatory)][datetime] $AnchorDate,
        [Parameter(Mandatory)][datetime] $BusinessDate
    )

    $manifest = Get-LocalMigrationManifest
    $containerId = $null
    $seedReference = $null
    if ($Action -eq "SeedNative") {
        $seedReference = "'" + $script:seedPath.Replace("\", "/").Replace("'", "''") + "'"
    }
    else {
        $containerId = Invoke-Compose -Arguments @("ps", "-q", "db") -Capture
        if ([string]::IsNullOrWhiteSpace($containerId)) { throw "No se pudo resolver PostgreSQL" }
        $containerId = (($containerId -split "`r?`n")[0]).Trim()
        $seedReference = "/tmp/gestudio_demo_seed_full.sql"
        Invoke-Docker -Arguments @("cp", $script:seedPath, "${containerId}:$seedReference") -Capture | Out-Null
    }
    try {
        $input = @(
            "\set ON_ERROR_STOP on",
            "\set demo_anchor_date $($AnchorDate.ToString('yyyy-MM-dd'))",
            "\set demo_business_date $($BusinessDate.ToString('yyyy-MM-dd'))",
            "\set demo_expected_flyway_count $($manifest.Count)",
            "\set demo_expected_flyway_latest $($manifest.LatestVersion)",
            "\set demo_superadmin_password_hash $($script:demoHashes['demo-superadmin'])",
            "\set demo_direccion_password_hash $($script:demoHashes['demo-direccion'])",
            "\set demo_administrador_password_hash $($script:demoHashes['demo-administrador'])",
            "\set demo_secretaria_password_hash $($script:demoHashes['demo-secretaria'])",
            "\set demo_caja_password_hash $($script:demoHashes['demo-caja'])",
            "\i $seedReference"
        ) -join "`n"
        $output = Invoke-PsqlInput -InputText ($input + "`n")
        Assert-True -Condition ($output -match "GESTUDIO DEMO SEED: ejecución completada y validada") -Message "El seed no emitió su confirmación canónica"
    }
    finally {
        if ($null -ne $containerId) {
            try { Invoke-Docker -Arguments @("exec", $containerId, "rm", "-f", $seedReference) -Capture | Out-Null }
            catch { }
        }
    }
}

function New-HttpSession {
    $cookies = [Net.CookieContainer]::new()
    $handler = [Net.Http.HttpClientHandler]::new()
    $handler.CookieContainer = $cookies
    $client = [Net.Http.HttpClient]::new($handler, $true)
    $client.Timeout = [TimeSpan]::FromSeconds(30)
    $script:httpClients.Add($client)
    return [pscustomobject]@{ Client = $client; Cookies = $cookies }
}

function Invoke-Http {
    param(
        [Parameter(Mandatory)] $Session,
        [Parameter(Mandatory)][string] $Method,
        [Parameter(Mandatory)][string] $Uri,
        $Body = $null,
        [hashtable] $Headers = @{},
        [AllowNull()][string] $Token = $null
    )

    $request = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::new($Method), $Uri)
    try {
        foreach ($entry in $Headers.GetEnumerator()) {
            [void]$request.Headers.TryAddWithoutValidation($entry.Key, [string]$entry.Value)
        }
        if (-not [string]::IsNullOrWhiteSpace($Token)) {
            $request.Headers.Authorization = [Net.Http.Headers.AuthenticationHeaderValue]::new("Bearer", $Token)
        }
        if ($null -ne $Body) {
            $json = $Body | ConvertTo-Json -Depth 15 -Compress
            $request.Content = [Net.Http.StringContent]::new($json, [Text.Encoding]::UTF8, "application/json")
        }
        $response = $Session.Client.SendAsync($request).GetAwaiter().GetResult()
        try {
            $raw = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            $responseHeaders = @{}
            foreach ($header in $response.Headers) { $responseHeaders[$header.Key] = @($header.Value) }
            foreach ($header in $response.Content.Headers) { $responseHeaders[$header.Key] = @($header.Value) }
            return [pscustomobject]@{ Status = [int]$response.StatusCode; Body = $raw; Headers = $responseHeaders }
        }
        finally { $response.Dispose() }
    }
    finally { $request.Dispose() }
}

function Get-Header {
    param([Parameter(Mandatory)] $Response, [Parameter(Mandatory)][string] $Name)
    if (-not $Response.Headers.ContainsKey($Name)) { return "" }
    return (@($Response.Headers[$Name]) -join ", ")
}

function Invoke-Api {
    param(
        [Parameter(Mandatory)] $Session,
        [Parameter(Mandatory)][string] $Method,
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][int] $ExpectedStatus,
        $Body = $null,
        [AllowNull()][string] $Token = $null,
        [hashtable] $Headers = @{}
    )
    $result = Invoke-Http -Session $Session -Method $Method -Uri ($script:apiBase + $Path) -Body $Body -Token $Token -Headers $Headers
    if ($result.Status -ne $ExpectedStatus) {
        throw "$Method $Path devolvió $($result.Status), se esperaba $ExpectedStatus; body=$(Redact $result.Body)"
    }
    $json = $null
    if (-not [string]::IsNullOrWhiteSpace($result.Body)) {
        try { $json = $result.Body | ConvertFrom-Json }
        catch { $json = $null }
    }
    return [pscustomobject]@{ Status = $result.Status; Body = $result.Body; Headers = $result.Headers; Json = $json }
}

function Login-Actor {
    param(
        [Parameter(Mandatory)] $Session,
        [Parameter(Mandatory)][string] $Username,
        [Parameter(Mandatory)][string] $ExpectedRole
    )

    $response = Invoke-Api -Session $Session -Method "POST" -Path "/login" -ExpectedStatus 200 -Headers @{ Origin = $script:frontendUrl } -Body @{
        nombreUsuario = $Username
        contrasena = [string]$script:demoPasswords[$Username]
    }
    Assert-True -Condition ($null -ne $response.Json) -Message "Login de $Username sin JSON"
    Assert-True -Condition (-not [string]::IsNullOrWhiteSpace([string]$response.Json.accessToken)) -Message "Login de $Username sin access token"
    Assert-True -Condition (@($response.Json.usuario.roles) -contains $ExpectedRole) -Message "Rol incorrecto para $Username"
    $token = [string]$response.Json.accessToken
    Add-Secret $token
    $script:actorTokens[$Username] = $token
    $cookie = $Session.Cookies.GetCookies([Uri]($script:apiBase + "/login"))[$script:cookieName]
    Assert-True -Condition ($null -ne $cookie -and -not [string]::IsNullOrWhiteSpace($cookie.Value)) -Message "Login de $Username sin refresh cookie demo"
    Add-Secret $cookie.Value
    return [pscustomobject]@{ Response = $response; Cookie = $cookie }
}

function Assert-CorsAndHttpContracts {
    param([Parameter(Mandatory)] $Session)

    $preflight = Invoke-Http -Session $Session -Method "OPTIONS" -Uri ($script:apiBase + "/login") -Headers @{
        Origin = $script:frontendUrl
        "Access-Control-Request-Method" = "POST"
        "Access-Control-Request-Headers" = "authorization,content-type"
    }
    Assert-Equal -Actual $preflight.Status -Expected 200 -Message "Preflight demo rechazado"
    Assert-Equal -Actual (Get-Header $preflight "Access-Control-Allow-Origin") -Expected $script:frontendUrl -Message "Allow-Origin incorrecto"
    Assert-Equal -Actual (Get-Header $preflight "Access-Control-Allow-Credentials") -Expected "true" -Message "Allow-Credentials incorrecto"
    $methods = Get-Header $preflight "Access-Control-Allow-Methods"
    $headers = Get-Header $preflight "Access-Control-Allow-Headers"
    Assert-True -Condition ($methods -match '(?i)(^|,\s*)POST(,|$)') -Message "Preflight sin POST"
    Assert-True -Condition ($headers -match '(?i)Authorization' -and $headers -match '(?i)Content-Type') -Message "Preflight sin headers requeridos"
    Assert-True -Condition ((Get-Header $preflight "Access-Control-Allow-Origin") -ne "*") -Message "CORS no puede usar wildcard con credenciales"

    $foreign = Invoke-Http -Session $Session -Method "OPTIONS" -Uri ($script:apiBase + "/login") -Headers @{
        Origin = "http://localhost:5173"
        "Access-Control-Request-Method" = "POST"
    }
    Assert-Equal -Actual $foreign.Status -Expected 403 -Message "El backend aceptó un origen distinto del demo"
    Assert-True -Condition ([string]::IsNullOrWhiteSpace((Get-Header $foreign "Access-Control-Allow-Origin"))) -Message "Origen ajeno recibió Allow-Origin"
    Pass "CORS efectivo" "origen exacto, credenciales, métodos y headers"
}

function Assert-FrontendBundle {
    param([Parameter(Mandatory)] $Session)

    $page = Invoke-Http -Session $Session -Method "GET" -Uri ($script:frontendUrl + "/")
    Assert-Equal -Actual $page.Status -Expected 200 -Message "Frontend demo no responde"
    Assert-True -Condition ($page.Body -match '<div id="root"></div>') -Message "La respuesta no es el frontend Gestudio"
    $match = [regex]::Match($page.Body, '<script[^>]+src="([^"]+\.js)"')
    Assert-True -Condition $match.Success -Message "No se encontró el bundle principal"
    $asset = Invoke-Http -Session $Session -Method "GET" -Uri ($script:frontendUrl + $match.Groups[1].Value)
    Assert-Equal -Actual $asset.Status -Expected 200 -Message "Bundle principal no disponible"

    $frontendId = (Get-ServiceState -Service "frontend").Id
    $expected = Invoke-Docker -Arguments @("exec", $frontendId, "sh", "-c", "grep -R -F -l 'http://localhost:18080/api' /usr/share/nginx/html | head -n 1") -Capture
    $obsolete = Invoke-Docker -Arguments @("exec", $frontendId, "sh", "-c", "grep -R -F -l 'http://localhost:8080' /usr/share/nginx/html || true") -Capture
    Assert-True -Condition (-not [string]::IsNullOrWhiteSpace($expected)) -Message "El bundle servido no contiene la API demo"
    Assert-True -Condition ([string]::IsNullOrWhiteSpace($obsolete)) -Message "El bundle servido aún contiene localhost:8080"
    Pass "Frontend servido" "$frontendUrl -> $apiBase"
}

function Assert-HttpAndRbac {
    $session = New-HttpSession
    Assert-FrontendBundle -Session $session
    Assert-CorsAndHttpContracts -Session $session

    Invoke-Api -Session $session -Method "GET" -Path "/usuarios/perfil" -ExpectedStatus 401 -Headers @{ Origin = $script:frontendUrl } | Out-Null
    Invoke-Api -Session $session -Method "POST" -Path "/login" -ExpectedStatus 401 -Headers @{ Origin = $script:frontendUrl } -Body @{
        nombreUsuario = "demo-superadmin"; contrasena = "credencial-incorrecta"
    } | Out-Null

    $roles = [ordered]@{
        "demo-superadmin" = "SUPERADMIN"
        "demo-direccion" = "DIRECCION"
        "demo-administrador" = "ADMINISTRADOR"
        "demo-secretaria" = "SECRETARIA"
        "demo-caja" = "CAJA"
    }
    $firstCookie = $null
    foreach ($entry in $roles.GetEnumerator()) {
        $login = Login-Actor -Session $session -Username $entry.Key -ExpectedRole $entry.Value
        if ($null -eq $firstCookie) {
            $firstCookie = $login.Cookie.Value
            $actual = $login.Response
            Assert-Equal -Actual (Get-Header $actual "Access-Control-Allow-Origin") -Expected $script:frontendUrl -Message "POST login sin Allow-Origin demo"
            Assert-Equal -Actual (Get-Header $actual "Access-Control-Allow-Credentials") -Expected "true" -Message "POST login sin credenciales CORS"
            Assert-True -Condition ((Get-Header $actual "Access-Control-Expose-Headers") -match '(?i)Authorization') -Message "Authorization no está expuesto por CORS"
            $setCookie = Get-Header $actual "Set-Cookie"
            Assert-True -Condition ($setCookie -match "(?i)^$($script:cookieName)=") -Message "Nombre de refresh cookie incorrecto"
            Assert-True -Condition ($setCookie -match '(?i)(^|;\s*)Path=/api/login(;|$)') -Message "Path de refresh cookie incorrecto"
            Assert-True -Condition ($setCookie -match '(?i)(^|;\s*)SameSite=Strict(;|$)') -Message "SameSite de refresh cookie incorrecto"
            Assert-True -Condition ($setCookie -match '(?i)(^|;\s*)HttpOnly(;|$)') -Message "Refresh cookie no es HttpOnly"
            Assert-True -Condition ($setCookie -notmatch '(?i)(^|;\s*)Secure(;|$)') -Message "Refresh cookie local no debe ser Secure"
            Assert-True -Condition ($setCookie -notmatch '(?i)(^|;\s*)Domain=') -Message "Refresh cookie demo debe ser host-only"
        }
    }
    $currentCookie = $session.Cookies.GetCookies([Uri]($script:apiBase + "/login"))[$script:cookieName]
    Assert-True -Condition ($null -ne $currentCookie -and $currentCookie.Value -ne $firstCookie) -Message "La cookie anterior no fue reemplazada"
    Assert-Equal -Actual $session.Cookies.GetCookies([Uri]($script:apiBase + "/login")).Count -Expected 1 -Message "Quedaron cookies demo duplicadas"
    Pass "Autenticación y cookie" "5 logins=200; cookie host-only rotada"

    $superToken = $script:actorTokens["demo-superadmin"]
    $profile = Invoke-Api -Session $session -Method "GET" -Path "/usuarios/perfil" -ExpectedStatus 200 -Token $superToken
    Assert-True -Condition (@($profile.Json.roles) -contains "SUPERADMIN") -Message "Perfil superadmin sin rol"
    Assert-Equal -Actual @($profile.Json.permisos).Count -Expected 32 -Message "Superadmin sin catálogo completo"
    $notifications = Invoke-Api -Session $session -Method "GET" -Path "/notificaciones/cumpleaneros" -ExpectedStatus 200 -Token $superToken
    $expectedBirthday = "Alumno: Sof$([char]0x00ED)a Ben$([char]0x00ED)tez"
    Assert-True -Condition (@($notifications.Json) -contains $expectedBirthday) -Message "No se generó la notificación de cumpleaños demo"
    $assignable = Invoke-Api -Session $session -Method "GET" -Path "/usuarios/roles-asignables" -ExpectedStatus 200 -Token $superToken
    Assert-True -Condition (@($assignable.Json.codigo) -notcontains "PROFESOR") -Message "PROFESOR aparece asignable"

    foreach ($actor in @("demo-direccion", "demo-administrador")) {
        Invoke-Api -Session $session -Method "GET" -Path "/usuarios" -ExpectedStatus 200 -Token $script:actorTokens[$actor] | Out-Null
        Invoke-Api -Session $session -Method "GET" -Path "/roles" -ExpectedStatus 403 -Token $script:actorTokens[$actor] | Out-Null
    }

    $studentId = Invoke-Sql -Query "SELECT id FROM alumnos WHERE documento='49287134';"
    Assert-True -Condition ($studentId -match '^\d+$') -Message "No se resolvió alumno demo"
    $secretaria = $script:actorTokens["demo-secretaria"]
    Invoke-Api -Session $session -Method "GET" -Path "/alumnos?page=0&size=1" -ExpectedStatus 200 -Token $secretaria | Out-Null
    Invoke-Api -Session $session -Method "GET" -Path "/inscripciones?page=0&size=1" -ExpectedStatus 200 -Token $secretaria | Out-Null
    Invoke-Api -Session $session -Method "POST" -Path "/pagos" -ExpectedStatus 400 -Token $secretaria -Body @{} | Out-Null
    Invoke-Api -Session $session -Method "GET" -Path "/usuarios" -ExpectedStatus 403 -Token $secretaria | Out-Null
    Invoke-Api -Session $session -Method "GET" -Path "/egresos?page=0&size=1" -ExpectedStatus 403 -Token $secretaria | Out-Null

    $caja = $script:actorTokens["demo-caja"]
    Invoke-Api -Session $session -Method "GET" -Path "/alumnos?page=0&size=1" -ExpectedStatus 200 -Token $caja | Out-Null
    Invoke-Api -Session $session -Method "GET" -Path "/pagos/alumno/${studentId}?page=0&size=1" -ExpectedStatus 200 -Token $caja | Out-Null
    Invoke-Api -Session $session -Method "POST" -Path "/pagos" -ExpectedStatus 400 -Token $caja -Body @{} | Out-Null
    Invoke-Api -Session $session -Method "POST" -Path "/egresos" -ExpectedStatus 403 -Token $caja -Body @{} | Out-Null
    Invoke-Api -Session $session -Method "GET" -Path "/inscripciones?page=0&size=1" -ExpectedStatus 403 -Token $caja | Out-Null
    Pass "RBAC HTTP" "200/400/401/403 diferenciados; notificación de cumpleaños creada"
}

function Assert-FlywayAndSchema {
    $manifest = Get-LocalMigrationManifest

    $history = Invoke-Sql -Query @"
SELECT count(*) || '|' || max(version::int) || '|' ||
       count(*) FILTER (WHERE NOT success) || '|' ||
       count(*) FILTER (WHERE lower(script) LIKE '%demo%seed%' OR lower(script) LIKE '%seed%demo%')
FROM flyway_schema_history;
"@
    $parts = $history.Split("|")
    Assert-Equal -Actual $parts.Count -Expected 4 -Message "Historial Flyway ilegible"
    Assert-Equal -Actual $parts[0] -Expected ([string]$manifest.Count) -Message "Cantidad Flyway inesperada"
    Assert-Equal -Actual $parts[1] -Expected ([string]$manifest.LatestVersion) -Message "Versión Flyway inesperada"
    Assert-Equal -Actual $parts[2] -Expected "0" -Message "Hay migraciones fallidas"
    Assert-Equal -Actual $parts[3] -Expected "0" -Message "Hay una migración demo"
    $historyScripts = @((Invoke-Sql "SELECT script FROM flyway_schema_history WHERE success ORDER BY installed_rank;") -split "`r?`n")
    Assert-Equal -Actual $historyScripts.Count -Expected $manifest.Count -Message "Cantidad de scripts Flyway inesperada"
    foreach ($migration in $manifest.Scripts) {
        Assert-True -Condition ($historyScripts -contains $migration) -Message "Flyway no aplicó $migration"
    }
    Assert-Equal -Actual (Invoke-Sql "SELECT count(*) FROM roles WHERE codigo='PROFESOR' AND NOT activo AND sistema AND NOT editable;") -Expected "1" -Message "PROFESOR no conserva su contrato"
    Assert-Equal -Actual (Invoke-Sql "SELECT count(*) FROM rol_permisos rp JOIN roles r ON r.id=rp.rol_id WHERE r.codigo='PROFESOR';") -Expected "0" -Message "PROFESOR tiene permisos"
    Pass "Flyway/Hibernate/RBAC" "$($manifest.Count) migraciones, última V$($manifest.LatestVersion), ddl-auto=validate"
}

function Assert-DatabaseEmptyForDemo {
    Invoke-Sql -Query @'
DO $$
DECLARE
    table_name text;
    has_rows boolean;
BEGIN
    FOR table_name IN
        SELECT tablename
        FROM pg_tables
        WHERE schemaname = 'public'
          AND tablename NOT IN ('flyway_schema_history', 'roles', 'permisos', 'rol_permisos')
        ORDER BY tablename
    LOOP
        EXECUTE format('SELECT EXISTS (SELECT 1 FROM public.%I)', table_name) INTO has_rows;
        IF has_rows THEN
            RAISE EXCEPTION 'La base contiene datos preservables en public.%', table_name;
        END IF;
    END LOOP;
END
$$;
'@ | Out-Null
    Pass "Base local vacía" "sin datos ajenos al catálogo productivo"
}

function Configure-DemoEnvironment {
    $script:postgresPassword = New-HexSecret 24
    $script:jwtSecret = New-HexSecret 64
    Add-Secret $script:postgresPassword
    Add-Secret $script:jwtSecret
    $values = [ordered]@{
        POSTGRES_DB = $script:postgresDb
        POSTGRES_USER = $script:postgresUser
        POSTGRES_PASSWORD = $script:postgresPassword
        POSTGRES_PORT = [string]$script:postgresPort
        BACKEND_PORT = [string]$script:backendPort
        FRONTEND_PORT = [string]$script:frontendPort
        BACKEND_IMAGE = $script:backendImage
        FRONTEND_IMAGE = $script:frontendImage
        VCS_REF = (Get-RepositoryRevision)
        COMPOSE_SHA = (Get-ComposeSha)
        BACKEND_SOURCE_SHA = (Get-SourceFingerprint -RelativeRoot 'backend')
        FRONTEND_SOURCE_SHA = (Get-SourceFingerprint -RelativeRoot 'frontend')
        SPRING_PROFILES_ACTIVE = "dev"
        SPRING_JPA_HIBERNATE_DDL_AUTO = "validate"
        SPRING_FLYWAY_ENABLED = "true"
        SPRING_FLYWAY_BASELINE_ON_MIGRATE = "false"
        SPRING_FLYWAY_BASELINE_VERSION = "1"
        JWT_SECRET = $script:jwtSecret
        JWT_ISSUER = "gestudio-demo-local"
        APP_TIME_ZONE = "America/Argentina/Buenos_Aires"
        APP_CORS_ALLOWED_ORIGINS = $script:frontendUrl
        APP_SCHEDULING_ENABLED = "false"
        APP_BOOTSTRAP_SUPERADMIN_ENABLED = "false"
        APP_LOCAL_ADMIN_PASSWORD_RESET_ENABLED = "false"
        APP_LOCAL_ADMIN_PASSWORD_RESET_USERNAME = ""
        APP_LOCAL_ADMIN_PASSWORD_RESET_PASSWORD = ""
        APP_SECURITY_REFRESH_COOKIE_NAME = $script:cookieName
        APP_SECURITY_REFRESH_COOKIE_SECURE = "false"
        APP_SECURITY_REFRESH_COOKIE_SAME_SITE = "Strict"
        APP_SECURITY_REFRESH_COOKIE_DOMAIN = ""
        APP_SECURITY_REFRESH_COOKIE_PATH = "/api/login"
        VITE_API_BASE_URL = $script:apiBase
        VITE_APP_TIME_ZONE = "America/Argentina/Buenos_Aires"
    }
    foreach ($entry in $values.GetEnumerator()) {
        Set-ScopedEnvironmentVariable -Name $entry.Key -Value ([string]$entry.Value)
    }
}

function Show-Diagnostics {
    try {
        $ps = Invoke-Compose -Arguments @("ps", "-a") -Capture -IgnoreDeadline
        if ($ps) { Write-Host (Redact $ps) }
    }
    catch { }
    try {
        $logs = Invoke-Compose -Arguments @("logs", "--tail", "100", "db", "backend", "frontend") -Capture -IgnoreDeadline
        if ($logs) { Write-Host (Redact $logs) }
    }
    catch { }
}

function Get-ImageFreshness {
    param(
        [Parameter(Mandatory)][string] $Service,
        [Parameter(Mandatory)][string] $Image,
        [Parameter(Mandatory)][string] $ExpectedRevision,
        [Parameter(Mandatory)][string] $ExpectedComposeSha,
        [Parameter(Mandatory)][string] $ExpectedSourceSha,
        [AllowEmptyString()][string] $ExpectedFlyway = "",
        [AllowEmptyString()][string] $ExpectedHealthContract = ""
    )

    try {
        $imageId = Invoke-Docker -Arguments @("image", "inspect", "--format", "{{.Id}}", $Image) -Capture -IgnoreDeadline
        $labelsJson = Invoke-Docker -Arguments @("image", "inspect", "--format", "{{json .Config.Labels}}", $Image) -Capture -IgnoreDeadline
    }
    catch {
        return [pscustomobject]@{ Ready = $false; Detail = "imagen inexistente: $Image" }
    }

    $state = Get-ServiceState -Service $Service
    if ([string]::IsNullOrWhiteSpace($state.Id)) {
        return [pscustomobject]@{ Ready = $false; Detail = "contenedor ausente para $Image" }
    }
    $containerImage = Invoke-Docker -Arguments @("inspect", "--format", "{{.Image}}", $state.Id) -Capture -IgnoreDeadline
    if ($containerImage -ne $imageId) {
        return [pscustomobject]@{ Ready = $false; Detail = "contenedor basado en imagen anterior" }
    }

    if ([string]::IsNullOrWhiteSpace($labelsJson) -or $labelsJson -eq "null") {
        return [pscustomobject]@{ Ready = $false; Detail = "imagen sin metadata de build" }
    }
    $labels = $labelsJson | ConvertFrom-Json
    $revisionProperty = $labels.PSObject.Properties['org.opencontainers.image.revision']
    $revision = if ($null -eq $revisionProperty) { "" } else { [string]$revisionProperty.Value }
    if ($revision -ne $ExpectedRevision) {
        return [pscustomobject]@{ Ready = $false; Detail = "imagen desactualizada: revisión '$revision'" }
    }
    $composeProperty = $labels.PSObject.Properties['org.gestudio.compose.sha256']
    $composeSha = if ($null -eq $composeProperty) { "" } else { [string]$composeProperty.Value }
    if ($composeSha -ne $ExpectedComposeSha) {
        return [pscustomobject]@{ Ready = $false; Detail = "imagen incompatible con Compose actual" }
    }
    $sourceProperty = $labels.PSObject.Properties['org.gestudio.source.sha256']
    $sourceSha = if ($null -eq $sourceProperty) { "" } else { [string]$sourceProperty.Value }
    if ($sourceSha -ne $ExpectedSourceSha) {
        return [pscustomobject]@{ Ready = $false; Detail = "imagen desactualizada respecto del contenido fuente" }
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedFlyway)) {
        try {
            $imageFlyway = Invoke-Docker -Arguments @(
                "run", "--rm", "--network", "none", "--entrypoint", "cat", $Image,
                "/app/build-metadata/flyway-latest"
            ) -Capture -IgnoreDeadline
        }
        catch {
            return [pscustomobject]@{ Ready = $false; Detail = "imagen sin metadata Flyway legible" }
        }
        if ($imageFlyway -ne $ExpectedFlyway) {
            return [pscustomobject]@{ Ready = $false; Detail = "imagen Flyway V$imageFlyway; esperada V$ExpectedFlyway" }
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedHealthContract)) {
        try {
            $imageHealthContract = Invoke-Docker -Arguments @(
                "run", "--rm", "--network", "none", "--entrypoint", "cat", $Image,
                "/app/build-metadata/health-contract"
            ) -Capture -IgnoreDeadline
        }
        catch {
            return [pscustomobject]@{ Ready = $false; Detail = "imagen sin contrato de health legible" }
        }
        if ($imageHealthContract -ne $ExpectedHealthContract) {
            return [pscustomobject]@{ Ready = $false; Detail = "health '$imageHealthContract'; esperado '$ExpectedHealthContract'" }
        }
    }

    return [pscustomobject]@{
        Ready = $true
        Detail = "vigente; imageId=$($imageId.Substring(7, 12)); revisión=$($revision.Substring(0, 12))"
    }
}

function Invoke-Status {
    foreach ($required in @($script:composeFile, $script:seedPath)) {
        if (-not (Test-Path -LiteralPath $required)) { throw "Falta $required" }
    }
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw "Docker no está disponible" }
    Invoke-Docker -Arguments @("info", "--format", "{{.ServerVersion}}") -Capture -IgnoreDeadline | Out-Null

    $manifest = Get-LocalMigrationManifest
    $expectedRevision = Get-RepositoryRevision
    $expectedComposeSha = Get-ComposeSha
    $expectedBackendSourceSha = Get-SourceFingerprint -RelativeRoot 'backend'
    $expectedFrontendSourceSha = Get-SourceFingerprint -RelativeRoot 'frontend'
    $states = @("db", "backend", "frontend") | ForEach-Object { Get-ServiceState -Service $_ }
    $flyway = "no disponible"
    $flywayReady = $false
    $seedReady = $false
    $databaseDetail = ""
    $frontReady = $false
    $dbState = @($states | Where-Object { $_.Service -eq "db" })[0]
    if ($dbState.State -eq "running" -and $dbState.Health -eq "healthy") {
        try {
            $history = (Invoke-Sql "SELECT count(*) || '|' || COALESCE(max(version::int), 0) || '|' || count(*) FILTER (WHERE NOT success) FROM flyway_schema_history;").Split("|")
            $historyScripts = @((Invoke-Sql "SELECT script FROM flyway_schema_history WHERE success ORDER BY installed_rank;") -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            $flyway = $history[1]
            $flywayReady = $history.Count -eq 3 `
                -and $history[0] -eq [string]$manifest.Count `
                -and $history[1] -eq [string]$manifest.LatestVersion `
                -and $history[2] -eq "0" `
                -and @(Compare-Object -ReferenceObject $manifest.Scripts -DifferenceObject $historyScripts).Count -eq 0
            $seedReady = Test-DemoSeedContract
        }
        catch {
            $flyway = "error de consulta"
            $databaseDetail = Redact $_.Exception.Message
        }
    }
    try {
        $statusSession = New-HttpSession
        $frontReady = (Invoke-Http -Session $statusSession -Method "GET" -Uri ($script:frontendUrl + "/")).Status -eq 200
    }
    catch { $frontReady = $false }

    $backendFresh = Get-ImageFreshness -Service "backend" -Image $script:backendImage `
        -ExpectedRevision $expectedRevision -ExpectedComposeSha $expectedComposeSha `
        -ExpectedSourceSha $expectedBackendSourceSha `
        -ExpectedFlyway ([string]$manifest.LatestVersion) -ExpectedHealthContract "actuator-readiness-v1"
    $frontendFresh = Get-ImageFreshness -Service "frontend" -Image $script:frontendImage `
        -ExpectedRevision $expectedRevision -ExpectedComposeSha $expectedComposeSha `
        -ExpectedSourceSha $expectedFrontendSourceSha
    $allHealthy = @($states | Where-Object { $_.State -ne "running" -or $_.Health -ne "healthy" }).Count -eq 0
    $available = $allHealthy -and $frontReady -and $seedReady -and $flywayReady `
        -and $backendFresh.Ready -and $frontendFresh.Ready
    Write-Host "Frontend: $($script:frontendUrl)"
    Write-Host "Backend:  $($script:backendUrl)"
    Write-Host "Base:     $($script:postgresDb) en localhost:$($script:postgresPort)"
    Write-Host "Flyway:   $flyway (esperada: $($manifest.LatestVersion))"
    Write-Host "Seed:     $(if ($seedReady) { 'completo (914 filas, usuarios y RBAC)' } else { 'incompleto o incompatible' })"
    if (-not [string]::IsNullOrWhiteSpace($databaseDetail)) {
        Write-Host "Base/seed: $databaseDetail"
    }
    Write-Host "Backend image:  $($backendFresh.Detail)"
    Write-Host "Frontend image: $($frontendFresh.Detail)"
    $states | Select-Object @{N="Contenedor";E={$_.Service}}, @{N="Estado";E={$_.State}}, @{N="Health";E={$_.Health}} | Format-Table -AutoSize | Out-Host
    Write-Host "Demo disponible: $(if ($available) { 'SÍ' } else { 'NO' })"
    return $available
}

function Invoke-Start {
    foreach ($required in @($script:composeFile, $script:seedPath, $script:migrationRoot, $script:backendRoot)) {
        if (-not (Test-Path -LiteralPath $required)) { throw "Falta recurso requerido: $required" }
    }
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw "Docker no está disponible en PATH" }
    Invoke-Docker -Arguments @("info", "--format", "{{.ServerVersion}}") -Capture | Out-Null
    Invoke-Docker -Arguments @("compose", "version") -Capture | Out-Null
    Assert-PortAvailable -Port $script:postgresPort -Purpose "PostgreSQL demo"
    Assert-PortAvailable -Port $script:backendPort -Purpose "backend demo"
    Assert-PortAvailable -Port $script:frontendPort -Purpose "frontend demo"
    Pass "Prerequisitos y puertos" "15432, 18080 y 18081 disponibles"

    $script:tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("gestudio-demo-local-$PID-" + ([Guid]::NewGuid().ToString("N").Substring(0, 8)))
    New-Item -ItemType Directory -Path $script:tempRoot -Force | Out-Null
    Configure-DemoEnvironment
    $script:stackAttempted = $true

    Invoke-Compose -Arguments @("up", "-d", "--force-recreate", "db") -Capture | Out-Null
    Wait-ServiceHealthy -Service "db"
    $passwordInput = "\set runtime_password $($script:postgresPassword)`nALTER ROLE $($script:postgresUser) PASSWORD :'runtime_password';`n"
    Invoke-PsqlInput -InputText $passwordInput | Out-Null
    Pass "PostgreSQL persistente" "$($script:postgresDb) en $($script:postgresPort)"

    $buildStarted = Get-Date
    Write-Host "[INFO] Construyendo imágenes backend/frontend..."
    Invoke-Compose -Arguments @("build", "backend", "frontend")
    Pass "Build de imágenes" "$([math]::Round(((Get-Date) - $buildStarted).TotalSeconds, 1)) segundos"

    Invoke-Compose -Arguments @("up", "-d", "--no-deps", "--force-recreate", "backend") -Capture | Out-Null
    Wait-ServiceHealthy -Service "backend"
    Invoke-Compose -Arguments @("up", "-d", "--no-deps", "--force-recreate", "frontend") -Capture | Out-Null
    Wait-ServiceHealthy -Service "frontend"
    Pass "Stack Compose recreado" "backend/frontend usan las imágenes recién construidas"

    Assert-FlywayAndSchema
    $rbacBefore = Get-RbacSnapshot
    Read-DemoPasswords
    Initialize-BcryptHelper
    New-BcryptHashes
    Pass "BCrypt" "5 hashes distintos; BOM normalizado; límite real validado"

    $anchor = Get-AnchorDate
    $businessDate = Get-BusinessDate
    Invoke-DemoSeed -AnchorDate $anchor -BusinessDate $businessDate
    foreach ($username in @($script:demoPasswords.Keys | Sort-Object)) {
        $storedHash = Invoke-Sql "SELECT contrasena FROM usuarios WHERE lower(nombre_usuario)='$username';"
        Add-Secret $storedHash
        Assert-Equal -Actual $storedHash -Expected $script:demoHashes[$username] -Message "Hash persistido inesperado para $username"
        Assert-BcryptPair -Password $script:demoPasswords[$username] -Hash $storedHash -Username $username
    }
    Assert-Equal -Actual (Get-RbacSnapshot) -Expected $rbacBefore -Message "La primera aplicación modificó RBAC"
    $firstSnapshot = Get-DatabaseSnapshot
    Pass "Primera aplicación del seed" "914 filas e integridad interna validadas"

    Invoke-DemoSeed -AnchorDate $anchor -BusinessDate $businessDate
    $secondSnapshot = Get-DatabaseSnapshot
    Assert-Equal -Actual $secondSnapshot -Expected $firstSnapshot -Message "La segunda aplicación cambió el snapshot"
    Assert-Equal -Actual (Get-RbacSnapshot) -Expected $rbacBefore -Message "La segunda aplicación modificó RBAC"
    foreach ($username in @($script:demoPasswords.Keys | Sort-Object)) {
        $storedHash = Invoke-Sql "SELECT contrasena FROM usuarios WHERE lower(nombre_usuario)='$username';"
        Add-Secret $storedHash
        Assert-BcryptPair -Password $script:demoPasswords[$username] -Hash $storedHash -Username $username
    }
    Pass "Segunda aplicación del seed" "snapshot idéntico y RBAC intacto"

    Assert-HttpAndRbac
    Write-Host ""
    if (-not (Invoke-Status)) { throw "El stack arrancó pero no satisface el contrato de vigencia" }
    Write-Host ""
    Write-Host "DEMO LOCAL LISTA" -ForegroundColor Green
}

function Invoke-SeedNative {
    foreach ($required in @($script:seedPath, $script:migrationRoot, $script:backendRoot)) {
        if (-not (Test-Path -LiteralPath $required)) { throw "Falta recurso requerido: $required" }
    }

    $script:nativePsqlPath = Resolve-Psql
    Read-DatabasePassword
    $connectedDatabase = Invoke-Sql -Query "SELECT current_database();"
    Assert-Equal -Actual $connectedDatabase -Expected $DatabaseName -Message "psql se conectó a otra base"
    Pass "PostgreSQL local" "$DatabaseUser@$DatabaseHost`:$DatabasePort/$DatabaseName"

    Assert-FlywayAndSchema
    Assert-DatabaseEmptyForDemo
    $rbacBefore = Get-RbacSnapshot

    $script:tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("gestudio-seed-native-$PID-" + ([Guid]::NewGuid().ToString("N").Substring(0, 8)))
    New-Item -ItemType Directory -Path $script:tempRoot -Force | Out-Null
    Read-DemoPasswords
    Initialize-BcryptHelper
    New-BcryptHashes
    Pass "BCrypt" "5 hashes distintos generados sin persistir claves en archivos"

    $businessDate = Get-BusinessDate
    Invoke-DemoSeed -AnchorDate $businessDate -BusinessDate $businessDate
    foreach ($username in @($script:demoPasswords.Keys | Sort-Object)) {
        $storedHash = Invoke-Sql "SELECT contrasena FROM usuarios WHERE lower(nombre_usuario)='$username';"
        Add-Secret $storedHash
        Assert-Equal -Actual $storedHash -Expected $script:demoHashes[$username] -Message "Hash persistido inesperado para $username"
        Assert-BcryptPair -Password $script:demoPasswords[$username] -Hash $storedHash -Username $username
    }
    Assert-Equal -Actual (Get-RbacSnapshot) -Expected $rbacBefore -Message "El seed modificó RBAC"
    Pass "Seed local completo" "914 filas sintéticas validadas"
    Write-Host "SEED LOCAL LISTO" -ForegroundColor Green
}

function Invoke-Stop {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw "Docker no está disponible en PATH" }
    Invoke-Compose -Arguments @("down", "--remove-orphans") -Capture -IgnoreDeadline | Out-Null
    Write-Host "Demo detenida. Contenedores y red eliminados; volúmenes conservados."
}

function Invoke-Reset {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw "Docker no está disponible en PATH" }
    Invoke-Compose -Arguments @("down", "--volumes", "--remove-orphans") -Capture -IgnoreDeadline | Out-Null
    Write-Host "Volúmenes demo eliminados; recreando desde cero."
    Invoke-Start
}

try {
    switch ($Action) {
        "Start" { Invoke-Start }
        "Status" { if (-not (Invoke-Status)) { $exitCode = 1 } }
        "Stop" { Invoke-Stop }
        "Reset" { Invoke-Reset }
        "SeedNative" { Invoke-SeedNative }
    }
}
catch {
    $exitCode = 1
    $caughtMessage = Redact $_.Exception.Message
    Write-Host "[FAIL] $caughtMessage" -ForegroundColor Red
    if ($stackAttempted) { Show-Diagnostics }
}
finally {
    foreach ($client in $httpClients) {
        try { $client.Dispose() } catch { }
    }
    $httpClients.Clear()
    foreach ($secure in @($securePasswords.Values)) {
        try { $secure.Dispose() } catch { }
    }
    foreach ($key in @($demoPasswords.Keys)) { $demoPasswords[$key] = $null }
    foreach ($key in @($demoHashes.Keys)) { $demoHashes[$key] = $null }
    foreach ($key in @($actorTokens.Keys)) { $actorTokens[$key] = $null }
    $securePasswords.Clear()
    $demoPasswords.Clear()
    $demoHashes.Clear()
    $actorTokens.Clear()
    $postgresPassword = $null
    $databasePassword = $null
    $jwtSecret = $null
    $nativePsqlPath = $null
    $bcryptClasspath = $null
    $javaExe = $null
    $javacExe = $null
    $secretValues.Clear()
    try { Restore-Environment } catch { if ($exitCode -eq 0) { $exitCode = 1 } }
    if (-not [string]::IsNullOrWhiteSpace($tempRoot) -and (Test-Path -LiteralPath $tempRoot)) {
        try { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
        catch { if ($exitCode -eq 0) { $exitCode = 1 } }
    }
}

if ($exitCode -ne 0) {
    if (-not [string]::IsNullOrWhiteSpace($caughtMessage)) { [Console]::Error.WriteLine($caughtMessage) }
    exit $exitCode
}
exit 0
