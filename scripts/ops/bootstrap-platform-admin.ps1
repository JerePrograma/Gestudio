<#
.SYNOPSIS
Crea el primer administrador de plataforma o recupera sus códigos one-shot.

.DESCRIPTION
El modo Bootstrap crea el primer SUPERADMIN mediante un contenedor Compose
one-shot. Si la base confirma el commit pero la entrega local de recovery codes
falla, conserva ese contenedor exacto para una recuperación explícita.

El modo Recovery valida el ID completo, los labels Compose, el nombre del job y
el estado comprometido en PostgreSQL antes de copiar los códigos. Nunca
sobrescribe el destino ni imprime credenciales, secretos TOTP o recovery codes.

.PARAMETER RecoverJobId
ID completo del contenedor one-shot conservado por una ejecución fallida.

.PARAMETER ConfirmRecovery
Confirmación explícita para recuperar los códigos y eliminar el job sólo después
de proteger y verificar el archivo local.

.EXAMPLE
pwsh -NoProfile -File .\scripts\ops\bootstrap-platform-admin.ps1 -EnvFile .\.gestudio-deploy\config\deploy.env -ProjectName gestudio-windows -Username platform-root -RecoveryCodesPath C:\secure\codes.txt -ConfirmBootstrap

.EXAMPLE
pwsh -NoProfile -File .\scripts\ops\bootstrap-platform-admin.ps1 -EnvFile .\.gestudio-deploy\config\deploy.env -ProjectName gestudio-windows -RecoveryCodesPath C:\secure\codes.txt -RecoverJobId aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa -ConfirmRecovery
#>
[CmdletBinding(DefaultParameterSetName = 'Bootstrap')]
param(
    [string] $ComposeFile,
    [Parameter(Mandatory)][string] $EnvFile,
    [Parameter(Mandatory)][string] $ProjectName,
    [Parameter(Mandatory, ParameterSetName = 'Bootstrap')][string] $Username,
    [Parameter(ParameterSetName = 'Bootstrap')][Security.SecureString] $Password,
    [Parameter(ParameterSetName = 'Bootstrap')][Security.SecureString] $TotpSecret,
    [Parameter(ParameterSetName = 'Bootstrap')][Security.SecureString] $TotpCode,
    [Parameter(Mandatory)][string] $RecoveryCodesPath,
    [Parameter(ParameterSetName = 'Bootstrap')][int] $TimeoutSeconds = 180,
    [Parameter(ParameterSetName = 'Bootstrap')][switch] $ConfirmBootstrap,
    [Parameter(Mandatory, ParameterSetName = 'Recovery')]
    [ValidatePattern('^[a-f0-9]{64}$')][string] $RecoverJobId,
    [Parameter(ParameterSetName = 'Recovery')][switch] $ConfirmRecovery
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
if ([string]::IsNullOrWhiteSpace($ComposeFile)) {
    $ComposeFile = Join-Path $repoRoot 'docker-compose.yml'
}
$isRecovery = $PSCmdlet.ParameterSetName -ceq 'Recovery'
if ($isRecovery) {
    if (-not $ConfirmRecovery) {
        throw 'La recuperación extrae códigos one-shot y elimina el job sólo al finalizar. Reejecute con -ConfirmRecovery.'
    }
}
elseif (-not $ConfirmBootstrap) {
    throw 'El bootstrap crea la identidad inicial de plataforma. Reejecute con -ConfirmBootstrap.'
}
if ($ProjectName -ceq 'gestudio-remote-demo') {
    throw 'gestudio-remote-demo está protegido y no puede recibir bootstrap desde este comando.'
}
if ($ProjectName -notmatch '^[a-z0-9][a-z0-9_-]{2,62}$') {
    throw 'ProjectName no cumple el contrato de nombres Compose.'
}
if (-not (Test-Path -LiteralPath $ComposeFile -PathType Leaf)) {
    throw "No existe Compose: $ComposeFile"
}
if (-not (Test-Path -LiteralPath $EnvFile -PathType Leaf)) {
    throw "No existe env file: $EnvFile"
}
$recoveryCodesFullPath = [IO.Path]::GetFullPath($RecoveryCodesPath)
$repoBoundary = $repoRoot.TrimEnd(
    [IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) +
    [IO.Path]::DirectorySeparatorChar
if ($recoveryCodesFullPath.Equals($repoRoot, [StringComparison]::OrdinalIgnoreCase) -or
    $recoveryCodesFullPath.StartsWith($repoBoundary, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'RecoveryCodesPath debe quedar fuera del checkout de Gestudio.'
}
if (Test-Path -LiteralPath $recoveryCodesFullPath) {
    throw "RecoveryCodesPath ya existe; se rechaza sobrescribirlo: $recoveryCodesFullPath"
}
$recoveryCodesDirectory = Split-Path $recoveryCodesFullPath -Parent
if (-not (Test-Path -LiteralPath $recoveryCodesDirectory -PathType Container)) {
    throw "El directorio destino de recovery codes no existe: $recoveryCodesDirectory"
}
$normalizedUsername = $null
if (-not $isRecovery) {
    $normalizedUsername = $Username.Trim()
    if ($normalizedUsername.Length -lt 3 -or $normalizedUsername.Length -gt 100) {
        throw 'Username debe tener entre 3 y 100 caracteres.'
    }
    if ($TimeoutSeconds -lt 30 -or $TimeoutSeconds -gt 900) {
        throw 'TimeoutSeconds debe estar entre 30 y 900.'
    }
    if ($null -eq $Password) {
        $Password = Read-Host 'Password inicial de plataforma' -AsSecureString
    }
    if ($null -eq $TotpSecret) {
        $TotpSecret = Read-Host 'Secret TOTP Base32 inicial' -AsSecureString
    }
    if ($null -eq $TotpCode) {
        $TotpCode = Read-Host 'Código TOTP actual (6 dígitos)' -AsSecureString
    }
}

$jobId = if ($isRecovery) { $RecoverJobId.ToLowerInvariant() } else { $null }
$secretValues = New-Object System.Collections.Generic.List[string]
$securePointers = New-Object System.Collections.Generic.List[IntPtr]
$environmentBackup = @{}
$environmentApplied = $false
$jobCreatedByInvocation = $false
$jobOwnedAndValidated = $false
$bootstrapCommitted = $false
$recoveryCodesSecured = $false
$jobCleanupError = $null
$jobRetentionError = $null
$primaryFailure = $null
$preserveJobForRecovery = $false

function ConvertTo-SafeText {
    param([AllowNull()][string] $Text)
    if ($null -eq $Text) { return '' }
    $sanitized = $Text
    foreach ($secret in $script:secretValues) {
        if (-not [string]::IsNullOrEmpty($secret)) {
            $sanitized = $sanitized.Replace($secret, '<redacted>')
        }
    }
    return $sanitized
}

function ConvertFrom-SecureValue {
    param([Parameter(Mandatory)][Security.SecureString] $Value)

    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    $securePointers.Add($pointer)
    $text = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    $secretValues.Add($text)
    return $text
}

function Invoke-Native {
    param(
        [Parameter(Mandatory)][string] $FilePath,
        [Parameter(Mandatory)][string[]] $Arguments,
        [switch] $Capture,
        [int[]] $ExpectedExitCodes = @(0)
    )

    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $FilePath @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousPreference }
    $text = ConvertTo-SafeText (($output | ForEach-Object { $_.ToString() }) -join "`n")
    if ($exitCode -notin $ExpectedExitCodes) {
        $tail = (($text -split "`r?`n") | Select-Object -Last 80) -join "`n"
        throw "$FilePath devolvió $exitCode`: $tail"
    }
    if ($Capture) { return $text.Trim() }
    if (-not [string]::IsNullOrWhiteSpace($text)) { Write-Host $text }
}

function Get-ComposePrefix {
    return @(
        'compose', '-f', ([IO.Path]::GetFullPath($ComposeFile)),
        '--env-file', ([IO.Path]::GetFullPath($EnvFile)),
        '-p', $ProjectName
    )
}

function Invoke-Compose {
    param([Parameter(Mandatory)][string[]] $Arguments, [switch] $Capture)
    return Invoke-Native -FilePath 'docker' -Arguments ((Get-ComposePrefix) + $Arguments) -Capture:$Capture
}

function Invoke-DatabaseSql {
    param([Parameter(Mandatory)][string] $Sql)

    $dbContainer = Invoke-Compose -Arguments @('ps', '-q', 'db') -Capture
    if ([string]::IsNullOrWhiteSpace($dbContainer) -or ($dbContainer -split "`r?`n").Count -ne 1) {
        throw 'El proyecto debe tener exactamente un contenedor db iniciado.'
    }
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Sql))
    return Invoke-Native -FilePath 'docker' -Arguments @(
        'exec', $dbContainer.Trim(), 'sh', '-ec',
        'printf "%s" "$1" | base64 -d | psql --no-psqlrc --tuples-only --no-align --set ON_ERROR_STOP=1 --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" --file=-',
        'sh', $encoded
    ) -Capture
}

function Get-BootstrapState {
    param([AllowNull()][string] $ExpectedUsername)

    $usernamePredicate = ''
    if (-not [string]::IsNullOrWhiteSpace($ExpectedUsername)) {
        $quotedUsername = $ExpectedUsername.Replace("'", "''")
        $usernamePredicate = " AND u.nombre_usuario = '$quotedUsername'"
    }
    return (Invoke-DatabaseSql -Sql @"
SELECT
  (SELECT count(*) FROM bootstrap_ejecuciones WHERE tipo = 'SUPERADMIN_INICIAL')::text || '|' ||
  (SELECT count(*)
   FROM bootstrap_ejecuciones b
   JOIN usuarios u ON u.id = b.usuario_id AND u.activo
   JOIN platform_admins pa ON pa.usuario_id = u.id AND pa.active
   JOIN platform_mfa_credentials mc ON mc.usuario_id = u.id
     AND mc.method = 'TOTP' AND mc.verified_at IS NOT NULL AND mc.revoked_at IS NULL
   WHERE b.tipo = 'SUPERADMIN_INICIAL'$usernamePredicate)::text || '|' ||
  (SELECT count(*)
   FROM bootstrap_ejecuciones b
   JOIN platform_mfa_credentials mc ON mc.usuario_id = b.usuario_id
     AND mc.method = 'TOTP' AND mc.verified_at IS NOT NULL AND mc.revoked_at IS NULL
   JOIN platform_recovery_codes rc ON rc.credential_id = mc.id
   WHERE b.tipo = 'SUPERADMIN_INICIAL' AND rc.used_at IS NULL)::text || '|' ||
  (SELECT count(*)
   FROM bootstrap_ejecuciones b
   JOIN tenant_memberships tm ON tm.usuario_id = b.usuario_id
   WHERE b.tipo = 'SUPERADMIN_INICIAL')::text;
"@).Trim()
}

function Assert-RecoveryJob {
    param([Parameter(Mandatory)][string] $ContainerId)

    $metadata = Invoke-Native -FilePath 'docker' -Arguments @(
        'inspect', '--format',
        '{{.Id}}|{{index .Config.Labels "com.docker.compose.project"}}|{{index .Config.Labels "com.docker.compose.service"}}|{{index .Config.Labels "com.docker.compose.oneoff"}}|{{.Name}}',
        $ContainerId
    ) -Capture
    $parts = @($metadata -split '\|', 5)
    $expectedName = "^/$([Regex]::Escape($ProjectName))-platform-bootstrap-[a-f0-9]{8}$"
    if ($parts.Count -ne 5 -or
        $parts[0] -cne $ContainerId -or
        $parts[1] -cne $ProjectName -or
        $parts[2] -cne 'backend' -or
        $parts[3] -ine 'True' -or
        $parts[4] -notmatch $expectedName) {
        throw 'El ID no identifica exactamente un job bootstrap one-shot del proyecto y servicio esperados.'
    }
}

function Set-OwnerOnlyAcl {
    param(
        [Parameter(Mandatory)][string] $Path,
        [switch] $Directory
    )

    $acl = Get-Acl -LiteralPath $Path
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($rule in @($acl.Access)) { [void]$acl.RemoveAccessRuleAll($rule) }
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent().User
    if ($Directory) {
        $ownerRule = [Security.AccessControl.FileSystemAccessRule]::new(
            $currentIdentity,
            [Security.AccessControl.FileSystemRights]::FullControl,
            ([Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
                [Security.AccessControl.InheritanceFlags]::ObjectInherit),
            [Security.AccessControl.PropagationFlags]::None,
            [Security.AccessControl.AccessControlType]::Allow)
    }
    else {
        $ownerRule = [Security.AccessControl.FileSystemAccessRule]::new(
            $currentIdentity,
            [Security.AccessControl.FileSystemRights]::FullControl,
            [Security.AccessControl.AccessControlType]::Allow)
    }
    $acl.SetOwner($currentIdentity)
    $acl.AddAccessRule($ownerRule)
    Set-Acl -LiteralPath $Path -AclObject $acl

    $effectiveAcl = Get-Acl -LiteralPath $Path
    $unexpectedRules = @($effectiveAcl.Access | Where-Object {
        $_.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow -and
        $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -cne $currentIdentity.Value
    })
    if (-not $effectiveAcl.AreAccessRulesProtected -or $unexpectedRules.Count -gt 0) {
        throw 'No se pudo restringir el recurso exclusivamente al usuario Windows actual.'
    }
}

function Copy-RecoveryCodesSecurely {
    param([Parameter(Mandatory)][string] $ContainerId)

    if (Test-Path -LiteralPath $recoveryCodesFullPath) {
        throw "RecoveryCodesPath apareció durante la operación; se rechaza sobrescribirlo: $recoveryCodesFullPath"
    }
    $stagingDirectory = [IO.Path]::GetFullPath((Join-Path $recoveryCodesDirectory `
        ('.gestudio-bootstrap-' + [Guid]::NewGuid().ToString('N'))))
    if ([IO.Path]::GetDirectoryName($stagingDirectory) -cne
        [IO.Path]::GetFullPath($recoveryCodesDirectory).TrimEnd([IO.Path]::DirectorySeparatorChar)) {
        throw 'No se pudo resolver un directorio privado junto al destino de recovery codes.'
    }
    $stagedFile = Join-Path $stagingDirectory 'recovery-codes.txt'
    $movedToDestination = $false
    $copyFailure = $null
    $cleanupFailure = $null
    try {
        [void](New-Item -ItemType Directory -Path $stagingDirectory)
        Set-OwnerOnlyAcl -Path $stagingDirectory -Directory
        Invoke-Native -FilePath 'docker' -Arguments @(
            'cp', "${ContainerId}:/tmp/gestudio-platform-recovery-codes.txt", $stagedFile
        ) | Out-Null
        if (-not (Test-Path -LiteralPath $stagedFile -PathType Leaf) -or
            (Get-Item -LiteralPath $stagedFile).Length -le 0) {
            throw 'El job no entregó un archivo de recovery codes válido.'
        }
        $codeCount = 0
        foreach ($code in [IO.File]::ReadLines($stagedFile, [Text.Encoding]::ASCII)) {
            if ($code -notmatch '^[A-Z2-7]{8}(?:-[A-Z2-7]{8}){2}-[A-Z2-7]{2}$') {
                throw 'El archivo de recovery codes no cumple el formato esperado.'
            }
            $codeCount++
        }
        if ($codeCount -ne 10) {
            throw 'El archivo de recovery codes no contiene exactamente diez entradas.'
        }
        Set-OwnerOnlyAcl -Path $stagedFile
        [IO.File]::Move($stagedFile, $recoveryCodesFullPath)
        $movedToDestination = $true
        Set-OwnerOnlyAcl -Path $recoveryCodesFullPath
    }
    catch {
        $copyFailure = ConvertTo-SafeText $_.Exception.Message
    }
    finally {
        if ($movedToDestination -and $null -ne $copyFailure -and
            (Test-Path -LiteralPath $recoveryCodesFullPath -PathType Leaf)) {
            try { Remove-Item -LiteralPath $recoveryCodesFullPath -Force }
            catch { $cleanupFailure = 'No se pudo eliminar el archivo local cuya protección no fue confirmada.' }
        }
        if (Test-Path -LiteralPath $stagedFile -PathType Leaf) {
            try { Remove-Item -LiteralPath $stagedFile -Force }
            catch { $cleanupFailure = 'No se pudo eliminar el archivo temporal privado de recovery codes.' }
        }
        if (Test-Path -LiteralPath $stagingDirectory -PathType Container) {
            try { Remove-Item -LiteralPath $stagingDirectory -Force }
            catch {
                if ($null -eq $cleanupFailure) {
                    $cleanupFailure = 'No se pudo eliminar el directorio temporal privado de recovery codes.'
                }
            }
        }
    }
    if ($null -ne $copyFailure) {
        if ($null -ne $cleanupFailure) { throw "$copyFailure $cleanupFailure" }
        throw $copyFailure
    }
    if ($null -ne $cleanupFailure) { throw $cleanupFailure }
}

function Get-RecoveryCommand {
    param([Parameter(Mandatory)][string] $ContainerId)

    function Quote([string] $Value) { return "'" + $Value.Replace("'", "''") + "'" }
    return (@(
        'pwsh -NoProfile -ExecutionPolicy Bypass -File', (Quote $PSCommandPath),
        '-ComposeFile', (Quote ([IO.Path]::GetFullPath($ComposeFile))),
        '-EnvFile', (Quote ([IO.Path]::GetFullPath($EnvFile))),
        '-ProjectName', (Quote $ProjectName),
        '-RecoveryCodesPath', (Quote $recoveryCodesFullPath),
        '-RecoverJobId', (Quote $ContainerId),
        '-ConfirmRecovery'
    ) -join ' ')
}

function Test-ShouldPreserveRecoveryJob {
    [OutputType([bool])]
    param(
        [bool] $JobOwnedAndValidated,
        [bool] $RecoveryCodesSecured,
        [bool] $BootstrapCommitted,
        [bool] $RecoveryMode
    )
    return $JobOwnedAndValidated -and -not $RecoveryCodesSecured -and
        ($BootstrapCommitted -or $RecoveryMode)
}

try {
    if ($isRecovery) {
        Assert-RecoveryJob -ContainerId $jobId
        $jobOwnedAndValidated = $true
        if ((Get-BootstrapState -ExpectedUsername $null) -cne '1|1|10|0') {
            throw 'La base no confirma un bootstrap único, activo, con MFA, diez códigos sin usar y cero memberships.'
        }
        $bootstrapCommitted = $true
        Copy-RecoveryCodesSecurely -ContainerId $jobId
        $recoveryCodesSecured = $true
        Write-Host 'Recovery codes recuperados y protegidos; el job one-shot será eliminado.' -ForegroundColor Green
    }
    else {
        $claimCount = (Invoke-DatabaseSql `
            -Sql "SELECT count(*) FROM bootstrap_ejecuciones WHERE tipo = 'SUPERADMIN_INICIAL';").Trim()
        if ($claimCount -cne '0') {
            throw "El bootstrap ya fue reclamado o el estado es inválido (claims=$claimCount)."
        }

        $passwordText = ConvertFrom-SecureValue -Value $Password
        $totpSecretText = (ConvertFrom-SecureValue -Value $TotpSecret).Trim().ToUpperInvariant()
        $totpCodeText = (ConvertFrom-SecureValue -Value $TotpCode).Trim()
        foreach ($normalizedSecret in @($totpSecretText, $totpCodeText)) {
            if (-not $secretValues.Contains($normalizedSecret)) { $secretValues.Add($normalizedSecret) }
        }
        $passwordBytes = [Text.Encoding]::UTF8.GetByteCount($passwordText)
        if ($passwordBytes -lt 16 -or $passwordBytes -gt 72) {
            throw 'Password debe contener entre 16 y 72 bytes UTF-8.'
        }
        if ($totpSecretText -notmatch '^[A-Z2-7]{16,128}$') {
            throw 'TotpSecret debe ser Base32 canónico de 16 a 128 caracteres.'
        }
        if ($totpCodeText -notmatch '^[0-9]{6}$') {
            throw 'TotpCode debe contener exactamente 6 dígitos.'
        }

        $jobEnvironment = [ordered]@{
            APP_BOOTSTRAP_SUPERADMIN_ENABLED = 'true'
            APP_BOOTSTRAP_SUPERADMIN_USERNAME = $normalizedUsername
            APP_BOOTSTRAP_SUPERADMIN_PASSWORD = $passwordText
            APP_BOOTSTRAP_PLATFORM_TOTP_SECRET = $totpSecretText
            APP_BOOTSTRAP_PLATFORM_TOTP_CODE = $totpCodeText
            APP_BOOTSTRAP_PLATFORM_RECOVERY_CODES_FILE = '/tmp/gestudio-platform-recovery-codes.txt'
            APP_SCHEDULING_ENABLED = 'false'
            APP_EMAIL_ENABLED = 'false'
            APP_EMAIL_REAL_NETWORK_ALLOWED = 'false'
            APP_EMAIL_KILL_SWITCH = 'true'
        }
        foreach ($entry in $jobEnvironment.GetEnumerator()) {
            $environmentBackup[$entry.Key] = [Environment]::GetEnvironmentVariable($entry.Key, 'Process')
            [Environment]::SetEnvironmentVariable($entry.Key, [string]$entry.Value, 'Process')
        }
        $environmentApplied = $true

        $jobName = "$ProjectName-platform-bootstrap-$([Guid]::NewGuid().ToString('N').Substring(0, 8))"
        $runArguments = @(
            'run', '--detach', '--no-deps', '--name', $jobName,
            '-e', 'APP_BOOTSTRAP_SUPERADMIN_ENABLED',
            '-e', 'APP_BOOTSTRAP_SUPERADMIN_USERNAME',
            '-e', 'APP_BOOTSTRAP_SUPERADMIN_PASSWORD',
            '-e', 'APP_BOOTSTRAP_PLATFORM_TOTP_SECRET',
            '-e', 'APP_BOOTSTRAP_PLATFORM_TOTP_CODE',
            '-e', 'APP_BOOTSTRAP_PLATFORM_RECOVERY_CODES_FILE',
            '-e', 'APP_SCHEDULING_ENABLED',
            '-e', 'APP_EMAIL_ENABLED',
            '-e', 'APP_EMAIL_REAL_NETWORK_ALLOWED',
            '-e', 'APP_EMAIL_KILL_SWITCH',
            'backend'
        )
        $jobId = (Invoke-Compose -Arguments $runArguments -Capture).Trim()
        if ($jobId -notmatch '^[a-f0-9]{12,64}$') {
            throw 'Compose no devolvió un ID de job válido.'
        }
        $jobCreatedByInvocation = $true
        $resolvedJobId = (Invoke-Native -FilePath 'docker' -Arguments @(
            'inspect', '--format', '{{.Id}}', $jobId
        ) -Capture).Trim()
        if ($resolvedJobId -notmatch '^[a-f0-9]{64}$') {
            throw 'Docker no devolvió el ID completo del job bootstrap.'
        }
        $jobId = $resolvedJobId
        Assert-RecoveryJob -ContainerId $jobId
        $jobOwnedAndValidated = $true

        $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        do {
            $state = Invoke-Native -FilePath 'docker' -Arguments @(
                'inspect', '--format', '{{.State.Running}}|{{.State.ExitCode}}', $jobId
            ) -Capture
            if ((Get-BootstrapState -ExpectedUsername $normalizedUsername) -ceq '1|1|10|0') {
                $bootstrapCommitted = $true
                break
            }
            if ($state -notmatch '^true\|') {
                $logs = Invoke-Native -FilePath 'docker' -Arguments @('logs', '--tail', '120', $jobId) -Capture
                throw "El job terminó antes de confirmar el bootstrap ($state): $logs"
            }
            Start-Sleep -Seconds 2
        } while ([DateTime]::UtcNow -lt $deadline)

        if (-not $bootstrapCommitted) {
            $logs = Invoke-Native -FilePath 'docker' -Arguments @('logs', '--tail', '120', $jobId) -Capture
            throw "Timeout esperando el bootstrap one-shot: $logs"
        }
        Copy-RecoveryCodesSecurely -ContainerId $jobId
        $recoveryCodesSecured = $true
        Write-Host "Bootstrap de plataforma confirmado para '$normalizedUsername'; el job temporal será eliminado." -ForegroundColor Green
    }
}
catch {
    $primaryFailure = ConvertTo-SafeText $_.Exception.Message
}
finally {
    $preserveJobForRecovery = Test-ShouldPreserveRecoveryJob `
        -JobOwnedAndValidated $jobOwnedAndValidated `
        -RecoveryCodesSecured $recoveryCodesSecured `
        -BootstrapCommitted $bootstrapCommitted `
        -RecoveryMode $isRecovery
    if ($preserveJobForRecovery) {
        try {
            Invoke-Native -FilePath 'docker' -Arguments @(
                'container', 'stop', '--time', '10', $jobId
            ) -ExpectedExitCodes @(0) | Out-Null
        }
        catch { $jobRetentionError = ConvertTo-SafeText $_.Exception.Message }
    }
    $removeJob = $jobCreatedByInvocation -or
        ($isRecovery -and $jobOwnedAndValidated -and $recoveryCodesSecured)
    if (-not [string]::IsNullOrWhiteSpace($jobId) -and -not $preserveJobForRecovery -and $removeJob) {
        try {
            Invoke-Native -FilePath 'docker' -Arguments @('container', 'rm', '-f', $jobId) `
                -ExpectedExitCodes @(0) | Out-Null
        }
        catch { $jobCleanupError = ConvertTo-SafeText $_.Exception.Message }
    }
    if ($environmentApplied) {
        foreach ($entry in $environmentBackup.GetEnumerator()) {
            [Environment]::SetEnvironmentVariable([string]$entry.Key, $entry.Value, 'Process')
        }
    }
    $script:secretValues.Clear()
    foreach ($pointer in $securePointers) {
        if ($pointer -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
        }
    }
}

if ($null -ne $primaryFailure) {
    $message = $primaryFailure
    if (-not [string]::IsNullOrWhiteSpace($jobCleanupError)) {
        $message += " No se pudo eliminar el job temporal: $jobCleanupError"
    }
    if ($preserveJobForRecovery) {
        $message += " El bootstrap comprometido se conserva en el job exacto $jobId; no vuelva a ejecutar el bootstrap. Recupere los códigos con: $(Get-RecoveryCommand -ContainerId $jobId)"
        if (-not [string]::IsNullOrWhiteSpace($jobRetentionError)) {
            $message += " No se pudo detener el job retenido: $jobRetentionError"
        }
    }
    throw $message
}
if (-not [string]::IsNullOrWhiteSpace($jobCleanupError)) {
    throw "Los recovery codes quedaron protegidos, pero no se pudo eliminar el job temporal que contiene secretos: $jobCleanupError Elimine sólo ese ID exacto con: docker container rm -f '$jobId'"
}
