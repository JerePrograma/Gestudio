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
        $output = @(& $FilePath @Arguments 2>&1)
        $code = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousErrorAction }

    $text = ($output | ForEach-Object { $_.ToString() }) -join "`n"
    if ($code -ne 0) {
        $tail = (($text -split "`r?`n") | Select-Object -Last 100) -join "`n"
        throw "$([IO.Path]::GetFileName($FilePath)) falló con código ${code}: $(Redact $tail)"
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

    $listeners = @()
    if (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue) {
        $listeners = @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue)
    }
    if ($listeners.Count -gt 0) {
        $pidValue = [int]$listeners[0].OwningProcess
        $process = Get-Process -Id $pidValue -ErrorAction SilentlyContinue
        $processName = if ($null -eq $process) { "desconocido" } else { $process.ProcessName }
        throw "Puerto $Port ($Purpose) ocupado por PID $pidValue ($processName)"
    }

    $netstat = @(& netstat -ano -p tcp 2>$null)
    foreach ($line in $netstat) {
        if ($line -match "^\s*TCP\s+\S+:$Port\s+\S+\s+LISTENING\s+(\d+)\s*$") {
            $pidValue = [int]$matches[1]
            $process = Get-Process -Id $pidValue -ErrorAction SilentlyContinue
            $processName = if ($null -eq $process) { "desconocido" } else { $process.ProcessName }
            throw "Puerto $Port ($Purpose) ocupado por PID $pidValue ($processName)"
        }
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

function Invoke-DemoSeed {
    param([Parameter(Mandatory)][datetime] $AnchorDate)

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
    Assert-True -Condition (@($notifications.Json).Count -ge 1) -Message "No se generó la notificación de cumpleaños demo"
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
    $localMigrations = @(Get-ChildItem -LiteralPath $script:migrationRoot -Filter "V*__*.sql" -File | Sort-Object Name)
    Assert-Equal -Actual $localMigrations.Count -Expected 6 -Message "Se esperaban exactamente V1-V6"
    Assert-Equal -Actual $localMigrations[-1].Name -Expected "V6__rbac_permission_catalog_and_base_roles.sql" -Message "V6 no es la última migración productiva"
    Assert-Equal -Actual @($localMigrations | Where-Object { $_.Name -match '(?i)demo.*seed|seed.*demo' }).Count -Expected 0 -Message "Existe una migración demo"

    $history = Invoke-Sql -Query @"
SELECT count(*) || '|' || max(version::int) || '|' ||
       count(*) FILTER (WHERE NOT success) || '|' ||
       count(*) FILTER (WHERE script='V6__rbac_permission_catalog_and_base_roles.sql' AND success) || '|' ||
       count(*) FILTER (WHERE lower(script) LIKE '%demo%seed%' OR lower(script) LIKE '%seed%demo%')
FROM flyway_schema_history;
"@
    $parts = $history.Split("|")
    Assert-Equal -Actual $parts.Count -Expected 5 -Message "Historial Flyway ilegible"
    Assert-Equal -Actual $parts[0] -Expected "6" -Message "Cantidad Flyway inesperada"
    Assert-Equal -Actual $parts[1] -Expected "6" -Message "Versión Flyway inesperada"
    Assert-Equal -Actual $parts[2] -Expected "0" -Message "Hay migraciones fallidas"
    Assert-Equal -Actual $parts[3] -Expected "1" -Message "V6 productiva ausente"
    Assert-Equal -Actual $parts[4] -Expected "0" -Message "Hay una migración demo"
    Assert-Equal -Actual (Invoke-Sql "SELECT count(*) FROM roles WHERE codigo='PROFESOR' AND NOT activo AND sistema AND NOT editable;") -Expected "1" -Message "PROFESOR no conserva su contrato"
    Assert-Equal -Actual (Invoke-Sql "SELECT count(*) FROM rol_permisos rp JOIN roles r ON r.id=rp.rol_id WHERE r.codigo='PROFESOR';") -Expected "0" -Message "PROFESOR tiene permisos"
    Pass "Flyway/Hibernate/RBAC" "V1-V6, ddl-auto=validate, sin migración demo"
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
    Pass "Base local vacía" "sin datos ajenos al catálogo productivo V1-V6"
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
        BACKEND_IMAGE = "gestudio-backend:demo-local"
        FRONTEND_IMAGE = "gestudio-frontend:demo-local"
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
        APP_BOOTSTRAP_ADMIN_ENABLED = "false"
        APP_BOOTSTRAP_ADMIN_RESET_EXISTING_PASSWORD = "false"
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

function Invoke-Status {
    foreach ($required in @($script:composeFile, $script:seedPath)) {
        if (-not (Test-Path -LiteralPath $required)) { throw "Falta $required" }
    }
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw "Docker no está disponible" }
    Invoke-Docker -Arguments @("info", "--format", "{{.ServerVersion}}") -Capture -IgnoreDeadline | Out-Null

    $states = @("db", "backend", "frontend") | ForEach-Object { Get-ServiceState -Service $_ }
    $flyway = "no disponible"
    $seedReady = $false
    $frontReady = $false
    $dbState = @($states | Where-Object { $_.Service -eq "db" })[0]
    if ($dbState.State -eq "running" -and $dbState.Health -eq "healthy") {
        try {
            $flyway = Invoke-Sql "SELECT COALESCE(max(version::int)::text, 'ninguna') FROM flyway_schema_history WHERE success;"
            $seedReady = (Invoke-Sql @"
SELECT CASE WHEN
    (SELECT count(*) FROM usuarios WHERE lower(nombre_usuario) LIKE 'demo-%') = 5 AND
    (SELECT count(*) FROM alumnos WHERE email LIKE '%@correo.local') = 28 AND
    EXISTS (
        SELECT 1 FROM alumnos
        WHERE documento='49287134'
          AND otras_notas LIKE 'Ficha revisada por administración. Actualización de referencia: %'
    )
THEN 'true' ELSE 'false' END;
"@) -eq "true"
        }
        catch { $flyway = "error de consulta" }
    }
    try {
        $statusSession = New-HttpSession
        $frontReady = (Invoke-Http -Session $statusSession -Method "GET" -Uri ($script:frontendUrl + "/")).Status -eq 200
    }
    catch { $frontReady = $false }

    $allHealthy = @($states | Where-Object { $_.State -ne "running" -or $_.Health -ne "healthy" }).Count -eq 0
    $available = $allHealthy -and $frontReady -and $seedReady -and $flyway -eq "6"
    Write-Host "Frontend: $($script:frontendUrl)"
    Write-Host "Backend:  $($script:backendUrl)"
    Write-Host "Base:     $($script:postgresDb) en localhost:$($script:postgresPort)"
    Write-Host "Flyway:   $flyway"
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

    Invoke-Compose -Arguments @("up", "-d", "db") -Capture | Out-Null
    Wait-ServiceHealthy -Service "db"
    $passwordInput = "\set runtime_password $($script:postgresPassword)`nALTER ROLE $($script:postgresUser) PASSWORD :'runtime_password';`n"
    Invoke-PsqlInput -InputText $passwordInput | Out-Null
    Pass "PostgreSQL persistente" "$($script:postgresDb) en $($script:postgresPort)"

    Invoke-Compose -Arguments @("build", "backend", "frontend") -Capture | Out-Null
    Invoke-Compose -Arguments @("up", "-d", "backend", "frontend") -Capture | Out-Null
    Wait-ServiceHealthy -Service "backend"
    Wait-ServiceHealthy -Service "frontend"
    Pass "Imágenes y stack Compose" "proyecto $($script:project)"

    Assert-FlywayAndSchema
    $rbacBefore = Get-RbacSnapshot
    Read-DemoPasswords
    Initialize-BcryptHelper
    New-BcryptHashes
    Pass "BCrypt" "5 hashes distintos; BOM normalizado; límite real validado"

    $anchor = Get-AnchorDate
    Invoke-DemoSeed -AnchorDate $anchor
    foreach ($username in @($script:demoPasswords.Keys | Sort-Object)) {
        $storedHash = Invoke-Sql "SELECT contrasena FROM usuarios WHERE lower(nombre_usuario)='$username';"
        Add-Secret $storedHash
        Assert-Equal -Actual $storedHash -Expected $script:demoHashes[$username] -Message "Hash persistido inesperado para $username"
        Assert-BcryptPair -Password $script:demoPasswords[$username] -Hash $storedHash -Username $username
    }
    Assert-Equal -Actual (Get-RbacSnapshot) -Expected $rbacBefore -Message "La primera aplicación modificó RBAC"
    $firstSnapshot = Get-DatabaseSnapshot
    Pass "Primera aplicación del seed" "914 filas e integridad interna validadas"

    Invoke-DemoSeed -AnchorDate $anchor
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
    [void](Invoke-Status)
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

    Invoke-DemoSeed -AnchorDate (Get-BusinessDate)
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
        "Status" { [void](Invoke-Status) }
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
