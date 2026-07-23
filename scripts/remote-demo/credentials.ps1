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
    $javacCommand = Get-Command javac -ErrorAction SilentlyContinue
    if ($null -ne $javacCommand) {
        $candidates.Add((Join-Path (Split-Path $javacCommand.Source -Parent) $javaName))
    }
    $roots = if ($script:isWindowsHost) {
        @(
            "$env:ProgramFiles\Java",
            "$env:ProgramFiles\Amazon Corretto",
            "$env:ProgramFiles\Eclipse Adoptium",
            "$env:ProgramFiles\Microsoft",
            "$env:USERPROFILE\.jdks"
        )
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

function Reset-DemoPassword {
    param([Parameter(Mandatory)][string] $Username)

    $allowedUsers = @(
        "demo-superadmin",
        "demo-direccion",
        "demo-administrador",
        "demo-secretaria",
        "demo-caja"
    )
    if ($Username -notin $allowedUsers) {
        throw "Usuario demo inválido: $Username. Valores permitidos: $($allowedUsers -join ', ')"
    }

    Assert-EnvironmentContract
    Assert-Prerequisites
    $databaseState = Get-ServiceState "db"
    if ($databaseState.State -ne "running" -or $databaseState.Health -ne "healthy") {
        throw "PostgreSQL remoto debe estar running/healthy antes del restablecimiento"
    }

    $confirmation = $null
    $plain = $null
    $plainConfirmation = $null
    try {
        $secure = Read-Host "Nueva contraseña para $Username" -AsSecureString
        $confirmation = Read-Host "Repetir contraseña" -AsSecureString
        $plain = ConvertFrom-SecurePassword $secure
        $plainConfirmation = ConvertFrom-SecurePassword $confirmation

        if ($plain -cne $plainConfirmation) { throw "Las contraseñas no coinciden" }
        $bytes = [Text.Encoding]::UTF8.GetByteCount($plain)
        if ([string]::IsNullOrWhiteSpace($plain) -or $bytes -lt 12 -or $bytes -gt 72) {
            throw "La contraseña debe tener entre 12 y 72 bytes UTF-8"
        }

        $script:securePasswords[$Username] = $secure
        $script:demoPasswords[$Username] = $plain
        Add-Secret $plain
        $script:tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("gestudio-demo-password-reset-$PID-" + ([Guid]::NewGuid().ToString("N").Substring(0, 8)))
        New-Item -ItemType Directory -Path $script:tempRoot -Force | Out-Null
        Initialize-BcryptHelper

        $passwordHash = Invoke-BcryptHelper ($plain + "`n")
        Assert-True ($passwordHash -match '^\$2[aby]\$12\$.{53}$') "Hash BCrypt incompatible para $Username"
        Add-Secret $passwordHash

        $usernameBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Username))
        $hashBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($passwordHash))
        Add-Secret $hashBase64

        $sql = @"
\set reset_username_base64 $usernameBase64
\set reset_hash_base64 $hashBase64
BEGIN;
CREATE TEMP TABLE _demo_password_reset (
    username text NOT NULL,
    password_hash text NOT NULL
) ON COMMIT DROP;
INSERT INTO _demo_password_reset (username, password_hash)
VALUES (
    convert_from(decode(:'reset_username_base64', 'base64'), 'UTF8'),
    convert_from(decode(:'reset_hash_base64', 'base64'), 'UTF8')
);
DO `$reset`$
BEGIN
    IF (
        SELECT count(*)
        FROM public.usuarios u
        JOIN _demo_password_reset r ON lower(u.nombre_usuario) = lower(r.username)
        WHERE lower(u.nombre_usuario) LIKE 'demo-%'
    ) <> 1 THEN
        RAISE EXCEPTION 'No se encontró exactamente una cuenta demo';
    END IF;
END
`$reset`$;
UPDATE public.usuarios u
SET contrasena = r.password_hash,
    auth_version = COALESCE(u.auth_version, 0) + 1,
    password_changed_at = CURRENT_TIMESTAMP,
    version = COALESCE(u.version, 0) + 1,
    activo = TRUE
FROM _demo_password_reset r
WHERE lower(u.nombre_usuario) = lower(r.username)
  AND lower(u.nombre_usuario) LIKE 'demo-%';
UPDATE public.refresh_sessions rs
SET revoked_at = COALESCE(rs.revoked_at, CURRENT_TIMESTAMP),
    revoke_reason = COALESCE(rs.revoke_reason, 'DEMO_PASSWORD_RESET_LOCAL')
FROM public.usuarios u
JOIN _demo_password_reset r ON lower(u.nombre_usuario) = lower(r.username)
WHERE rs.usuario_id = u.id
  AND rs.revoked_at IS NULL;
INSERT INTO public.auditoria_eventos (
    categoria, accion, entidad_tipo, entidad_id, ocurrido_at, fecha_negocio, metadata
)
SELECT
    'SEGURIDAD',
    'DEMO_PASSWORD_RESET_LOCAL',
    'Usuario',
    u.id::text,
    CURRENT_TIMESTAMP,
    (CURRENT_TIMESTAMP AT TIME ZONE 'America/Argentina/Buenos_Aires')::date,
    jsonb_build_object('username', u.nombre_usuario, 'resultado', 'ACTUALIZADA')
FROM public.usuarios u
JOIN _demo_password_reset r ON lower(u.nombre_usuario) = lower(r.username);
COMMIT;
"@
        Invoke-PsqlInput -InputText ($sql + "`n") | Out-Null

        $summary = Invoke-Sql @"
SELECT u.nombre_usuario || '|' || r.codigo || '|' || u.auth_version || '|' || u.activo
FROM public.usuarios u
JOIN public.roles r ON r.id = u.rol_id
WHERE lower(u.nombre_usuario) = lower(convert_from(decode('$usernameBase64', 'base64'), 'UTF8'));
"@
        $parts = $summary.Split("|")
        Assert-Equal $parts.Count 4 "Resumen de cuenta demo ilegible"
        Assert-Equal $parts[0] $Username "Usuario restablecido inesperado"
        Assert-Equal $parts[3] "t" "La cuenta demo no quedó activa"
        Pass "Contraseña demo" "$($parts[0]) restablecida; rol=$($parts[1]); auth_version=$($parts[2]); sesiones revocadas"
    }
    finally {
        $plain = $null
        $plainConfirmation = $null
        if ($null -ne $confirmation) {
            try { $confirmation.Dispose() } catch { }
        }
    }
}
