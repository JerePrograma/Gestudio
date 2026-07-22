function Sync-DatabasePassword {
    $databaseUser = Get-EnvironmentValue "POSTGRES_USER"
    $databasePassword = Get-EnvironmentValue "POSTGRES_PASSWORD"
    $encodedPassword = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($databasePassword))
    Add-Secret $encodedPassword

    $sql = @"
\set runtime_password_base64 $encodedPassword
SELECT format(
    'ALTER ROLE %I PASSWORD %L',
    '$databaseUser',
    convert_from(decode(:'runtime_password_base64', 'base64'), 'UTF8')
) \gexec
"@
    Invoke-PsqlInput -InputText $sql | Out-Null
}

function Invoke-PsqlInput {
    param(
        [Parameter(Mandatory)][string] $InputText,
        [switch] $TuplesOnly
    )

    Assert-Deadline
    $database = Get-EnvironmentValue "POSTGRES_DB"
    $user = Get-EnvironmentValue "POSTGRES_USER"
    $psqlArguments = @("exec", "-T", "db", "psql", "-X", "-q", "-v", "ON_ERROR_STOP=1", "-U", $user, "-d", $database)
    if ($TuplesOnly) { $psqlArguments += @("-A", "-t", "-F", "|") }
    $arguments = Get-ComposeArguments -Arguments $psqlArguments

    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = @($InputText | & docker @arguments 2>&1)
        $code = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousErrorAction }

    $text = ($output | ForEach-Object { $_.ToString() }) -join "`n"
    if ($code -ne 0) {
        throw "psql falló con código ${code}: $(Redact $text)"
    }
    return $text.Trim()
}

function Invoke-Sql {
    param([Parameter(Mandatory)][string] $Query)

    return Invoke-PsqlInput -InputText ($Query + "`n") -TuplesOnly
}

function Get-BusinessDate {
    try { $zone = [TimeZoneInfo]::FindSystemTimeZoneById("America/Argentina/Buenos_Aires") }
    catch { $zone = [TimeZoneInfo]::FindSystemTimeZoneById("Argentina Standard Time") }
    return [TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $zone).Date
}

function Get-LocalMigrationManifest {
    $entries = @(Get-ChildItem -LiteralPath $script:migrationRoot -Filter "V*__*.sql" -File | ForEach-Object {
        if ($_.Name -notmatch '^V(?<version>[0-9]+)__.+\.sql$') {
            throw "Nombre de migración Flyway inválido: $($_.Name)"
        }
        [pscustomobject]@{ Version = [int]$matches.version; Script = $_.Name }
    } | Sort-Object Version)
    if ($entries.Count -eq 0) { throw "No hay migraciones Flyway locales" }
    if (@($entries.Version | Select-Object -Unique).Count -ne $entries.Count) { throw "Hay versiones Flyway duplicadas" }
    for ($index = 0; $index -lt $entries.Count; $index++) {
        if ($entries[$index].Version -ne ($index + 1)) { throw "La cadena Flyway no es contigua desde V1" }
    }
    if (@($entries | Where-Object { $_.Script -match '(?i)demo.*seed|seed.*demo' }).Count -ne 0) {
        throw "Existe una migración Flyway demo"
    }
    return [pscustomobject]@{
        Count = $entries.Count
        LatestVersion = $entries[-1].Version
        Scripts = @($entries.Script)
    }
}

function Assert-FlywayHistory {
    $manifest = Get-LocalMigrationManifest
    $history = (Invoke-Sql @"
SELECT count(*) || '|' || COALESCE(max(version::int), 0) || '|' || count(*) FILTER (WHERE NOT success)
FROM flyway_schema_history;
"@).Split("|")
    Assert-Equal $history.Count 3 "Historial Flyway ilegible"
    Assert-Equal $history[0] ([string]$manifest.Count) "Cantidad Flyway inesperada"
    Assert-Equal $history[1] ([string]$manifest.LatestVersion) "Última versión Flyway inesperada"
    Assert-Equal $history[2] "0" "Hay migraciones Flyway fallidas"
    Pass "Flyway" "$($manifest.Count) migraciones; última V$($manifest.LatestVersion)"
}

function Assert-DatabaseEmptyForDemo {
    Invoke-PsqlInput -InputText @'
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
}

function Test-DemoSeedContract {
    $result = Invoke-Sql @'
SELECT CASE WHEN
    (SELECT count(*) FROM usuarios WHERE lower(nombre_usuario) LIKE 'demo-%' AND activo) = 5
    AND (SELECT count(*) FROM alumnos WHERE email LIKE '%@correo.local') = 28
    AND (SELECT count(*) FROM disciplinas WHERE nombre IN (
        'Ballet Inicial (4 a 6 años)', 'Jazz Infantil (7 a 10 años)', 'Danza Urbana Teen',
        'Danza Contemporánea', 'Ritmos Latinos Adultos', 'Entrenamiento Escénico')) = 6
    AND (SELECT count(*) FROM inscripciones i JOIN alumnos a ON a.id=i.alumno_id WHERE a.email LIKE '%@correo.local') = 34
    AND (SELECT count(*) FROM cargos WHERE idempotency_key LIKE 'demo-seed:v1:%') = 115
    AND (SELECT count(*) FROM pagos WHERE idempotency_key LIKE 'demo-seed:v1:%') = 48
    AND (SELECT count(*) FROM recibos r JOIN pagos p ON p.id=r.pago_id WHERE p.idempotency_key LIKE 'demo-seed:v1:%') = 48
    AND (SELECT count(*) FROM roles) = 6
    AND (SELECT count(*) FROM permisos WHERE activo AND sistema) = 32
    AND (SELECT count(*) FROM rol_permisos) = 119
THEN 'true' ELSE 'false' END;
'@
    return $result -eq "true"
}

function ConvertFrom-SecurePassword {
    param([Parameter(Mandatory)][Security.SecureString] $SecurePassword)

    $pointer = [IntPtr]::Zero
    try {
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
        $value = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
        while ($value.Length -gt 0 -and $value[0] -eq [char]0xFEFF) { $value = $value.Substring(1) }
        return $value
    }
    finally {
        if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
    }
}

function Read-DemoPasswords {
    foreach ($username in @("demo-superadmin", "demo-direccion", "demo-administrador", "demo-secretaria", "demo-caja")) {
        while ($true) {
            $secure = Read-Host "Contraseña para $username" -AsSecureString
            $plain = ConvertFrom-SecurePassword $secure
            $bytes = [Text.Encoding]::UTF8.GetByteCount($plain)
            if ([string]::IsNullOrWhiteSpace($plain) -or $bytes -lt 12 -or $bytes -gt 72) {
                Write-Host "La contraseña debe tener entre 12 y 72 bytes UTF-8." -ForegroundColor Yellow
                $plain = $null
                $secure.Dispose()
                continue
            }
            if (@($script:demoPasswords.Values) -contains $plain) {
                Write-Host "Cada rol demo debe usar una contraseña distinta." -ForegroundColor Yellow
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
        if (Test-Java21Executable $candidate) {
            $javaHome = Split-Path (Split-Path ([IO.Path]::GetFullPath($candidate)) -Parent) -Parent
            $javac = Join-Path $javaHome "bin/$javacName"
            if (Test-Path -LiteralPath $javac -PathType Leaf) {
                return [pscustomobject]@{ Home = $javaHome; Java = [IO.Path]::GetFullPath($candidate); Javac = $javac }
            }
        }
    }
    throw "No se encontró un JDK 21 completo; configure JAVA_HOME"
}

function Initialize-BcryptHelper {
    $jdk = Resolve-Java21
    $script:javaExe = $jdk.Java
    $script:javacExe = $jdk.Javac
    Set-ScopedEnvironmentVariable "JAVA_HOME" $jdk.Home
    Set-ScopedEnvironmentVariable "PATH" ((Join-Path $jdk.Home "bin") + [IO.Path]::PathSeparator + $env:PATH)

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
    $sourcePath = Join-Path $script:tempRoot "GestudioRemoteDemoBcrypt.java"
    $source = @'
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;

public final class GestudioRemoteDemoBcrypt {
    public static void main(String[] args) throws Exception {
        BCryptPasswordEncoder encoder = new BCryptPasswordEncoder(12);
        try (BufferedReader reader = new BufferedReader(
                new InputStreamReader(System.in, StandardCharsets.UTF_8))) {
            String password;
            while ((password = reader.readLine()) != null) {
                if (password.getBytes(StandardCharsets.UTF_8).length > 72) System.exit(4);
                System.out.println(encoder.encode(password));
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
    param([Parameter(Mandatory)][string] $InputText)

    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $script:javaExe
    $psi.Arguments = "-cp `"$($script:bcryptClasspath.Replace('"', '\"'))`" GestudioRemoteDemoBcrypt"
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
        $hash = Invoke-BcryptHelper ($script:demoPasswords[$username] + "`n")
        Assert-True ($hash -match '^\$2[aby]\$12\$.{53}$') "Hash BCrypt incompatible para $username"
        $script:demoHashes[$username] = $hash
        Add-Secret $hash
    }
    Assert-Equal -Actual (@($script:demoHashes.Values | Select-Object -Unique).Count) -Expected 5 -Message "Cada usuario debe tener un BCrypt distinto"
}

function Invoke-DemoSeed {
    $manifest = Get-LocalMigrationManifest
    $businessDate = Get-BusinessDate
    $seed = [IO.File]::ReadAllText($script:seedPath)
    $input = @(
        "\set ON_ERROR_STOP on",
        "\set demo_anchor_date $($businessDate.ToString('yyyy-MM-dd'))",
        "\set demo_business_date $($businessDate.ToString('yyyy-MM-dd'))",
        "\set demo_expected_flyway_count $($manifest.Count)",
        "\set demo_expected_flyway_latest $($manifest.LatestVersion)",
        "\set demo_superadmin_password_hash $($script:demoHashes['demo-superadmin'])",
        "\set demo_direccion_password_hash $($script:demoHashes['demo-direccion'])",
        "\set demo_administrador_password_hash $($script:demoHashes['demo-administrador'])",
        "\set demo_secretaria_password_hash $($script:demoHashes['demo-secretaria'])",
        "\set demo_caja_password_hash $($script:demoHashes['demo-caja'])",
        $seed
    ) -join "`n"
    $output = Invoke-PsqlInput ($input + "`n")
    Assert-True ($output -match "GESTUDIO DEMO SEED: ejecución completada y validada") "El seed no emitió su confirmación canónica"
}

function Initialize-DemoSeedIfRequired {
    $userCountRaw = Invoke-Sql "SELECT count(*) FROM usuarios WHERE lower(nombre_usuario) LIKE 'demo-%';"
    $userCount = [int]$userCountRaw
    if ($userCount -eq 5 -and (Test-DemoSeedContract)) {
        Pass "Dataset demo" "existente y compatible"
        return
    }
    if ($userCount -ne 0) {
        throw "La base contiene un namespace demo parcial o incompatible; use Reset para recrearla"
    }

    Assert-DatabaseEmptyForDemo
    $script:tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("gestudio-demo-remote-$PID-" + ([Guid]::NewGuid().ToString("N").Substring(0, 8)))
    New-Item -ItemType Directory -Path $script:tempRoot -Force | Out-Null
    Write-Host "La base remota está vacía. Se solicitarán cinco contraseñas demo distintas." -ForegroundColor Yellow
    Read-DemoPasswords
    Initialize-BcryptHelper
    New-BcryptHashes
    Invoke-DemoSeed
    Assert-True (Test-DemoSeedContract) "El dataset demo remoto no satisface el contrato mínimo"
    Pass "Dataset demo" "914 filas sintéticas y cinco roles inicializados"
}

