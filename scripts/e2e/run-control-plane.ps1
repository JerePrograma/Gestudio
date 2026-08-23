[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$frontendRoot = Join-Path $repoRoot 'frontend'
$composeFile = Join-Path $repoRoot 'docker-compose.yml'
$artifactRoot = Join-Path $repoRoot 'artifacts\e2e'
$startedAt = [DateTimeOffset]::UtcNow
$secretValues = [Collections.Generic.List[string]]::new()
$environmentBackup = @{}
$environmentApplied = $false
$primaryFailure = $null
$cleanupFailure = $null
$playwrightStatus = 'NOT_EXECUTED'
$runRoot = $null
$envFile = $null
$portsOverride = $null
$bootstrapOverride = $null
$project = $null
$suffix = $null
$backendImage = $null
$frontendImage = $null
$composeStarted = $false
$bootstrapJobId = $null
$playwrightLog = [Collections.Generic.List[string]]::new()
$playwrightOutput = $null
$backendSourceSha = $null
$frontendSourceSha = $null
$composeSha = $null
$dockerContext = $null
$dockerContextBackup = [Environment]::GetEnvironmentVariable('DOCKER_CONTEXT', 'Process')
$dockerContextApplied = $false
$protectedDemoBefore = $null
$protectedDemoSnapshotCaptured = $false
$protectedDemoInvariant = 'NOT_VERIFIED'
$projectBefore = $null
$projectSnapshotCaptured = $false
$projectInvariant = 'NOT_VERIFIED'

function New-RandomBytes {
    param([Parameter(Mandatory)][ValidateRange(1, 1024)][int] $Count)
    $bytes = [byte[]]::new($Count)
    [Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    return $bytes
}

function New-RandomHex {
    param([Parameter(Mandatory)][ValidateRange(1, 512)][int] $Bytes)
    return [Convert]::ToHexString((New-RandomBytes -Count $Bytes)).ToLowerInvariant()
}

function Get-SourceFingerprint {
    param([Parameter(Mandatory)][string] $Path)
    $resolvedRoot = [IO.Path]::GetFullPath($Path)
    $files = Get-ChildItem -LiteralPath $resolvedRoot -Recurse -File | Where-Object {
        $relative = [IO.Path]::GetRelativePath($resolvedRoot, $_.FullName).Replace('\', '/')
        $relative -notmatch '^(target|node_modules|dist|coverage|quality-reports|test-results|playwright-report|artifacts)/'
    } | Sort-Object { [IO.Path]::GetRelativePath($resolvedRoot, $_.FullName).Replace('\', '/') }
    $sha = [Security.Cryptography.IncrementalHash]::CreateHash(
        [Security.Cryptography.HashAlgorithmName]::SHA256)
    try {
        foreach ($file in $files) {
            $relative = [IO.Path]::GetRelativePath($resolvedRoot, $file.FullName).Replace('\', '/')
            $pathBytes = [Text.Encoding]::UTF8.GetBytes($relative + "`n")
            $sha.AppendData($pathBytes)
            $stream = [IO.File]::OpenRead($file.FullName)
            try {
                $buffer = [byte[]]::new(65536)
                while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    $sha.AppendData($buffer, 0, $read)
                }
            }
            finally { $stream.Dispose() }
        }
        return [Convert]::ToHexString($sha.GetHashAndReset()).ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Get-FileSha256 {
    param([Parameter(Mandatory)][string] $Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function ConvertTo-Base32 {
    param([Parameter(Mandatory)][byte[]] $Bytes)
    $alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'
    $buffer = 0
    $bits = 0
    $result = [Text.StringBuilder]::new()
    foreach ($value in $Bytes) {
        $buffer = ($buffer -shl 8) -bor $value
        $bits += 8
        while ($bits -ge 5) {
            $bits -= 5
            [void]$result.Append($alphabet[($buffer -shr $bits) -band 31])
        }
    }
    if ($bits -gt 0) {
        [void]$result.Append($alphabet[($buffer -shl (5 - $bits)) -band 31])
    }
    return $result.ToString()
}

function Get-TotpCode {
    param(
        [Parameter(Mandatory)][byte[]] $Secret,
        [Parameter(Mandatory)][long] $Counter
    )
    $counterBytes = [BitConverter]::GetBytes($Counter)
    if ([BitConverter]::IsLittleEndian) { [Array]::Reverse($counterBytes) }
    $hmac = [Security.Cryptography.HMACSHA1]::new($Secret)
    try { $digest = $hmac.ComputeHash($counterBytes) }
    finally { $hmac.Dispose() }
    $offset = $digest[$digest.Length - 1] -band 0x0f
    $binary = (($digest[$offset] -band 0x7f) -shl 24) -bor
        (($digest[$offset + 1] -band 0xff) -shl 16) -bor
        (($digest[$offset + 2] -band 0xff) -shl 8) -bor
        ($digest[$offset + 3] -band 0xff)
    return ($binary % 1000000).ToString('D6')
}

function Get-FreeLoopbackPort {
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    try {
        $listener.Start()
        return ([Net.IPEndPoint]$listener.LocalEndpoint).Port
    }
    finally { $listener.Stop() }
}

function ConvertTo-SafeText {
    param([AllowNull()][object] $Value)
    $text = if ($null -eq $Value) { '' } else { [string]$Value }
    foreach ($secret in $secretValues) {
        if (-not [string]::IsNullOrEmpty($secret)) { $text = $text.Replace($secret, '[REDACTED]') }
    }
    return $text
}

function Invoke-Native {
    param(
        [Parameter(Mandatory)][string] $FilePath,
        [Parameter(Mandatory)][string[]] $Arguments,
        [switch] $Capture,
        [switch] $AllowFailure
    )
    $output = @(& $FilePath @Arguments 2>&1 | ForEach-Object { [string]$_ })
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        $safe = ConvertTo-SafeText ($output -join [Environment]::NewLine)
        throw "$FilePath fallo con exit code $exitCode. $safe"
    }
    if ($Capture) { return ($output -join [Environment]::NewLine).Trim() }
    return $exitCode
}

function Add-CleanupFailure {
    param([Parameter(Mandatory)][string] $Message)
    $safe = ConvertTo-SafeText $Message
    if ([string]::IsNullOrWhiteSpace($script:cleanupFailure)) {
        $script:cleanupFailure = $safe
    } else {
        $script:cleanupFailure = "$($script:cleanupFailure); $safe"
    }
}

function Assert-LocalDockerTarget {
    if (-not [string]::IsNullOrWhiteSpace(
            [Environment]::GetEnvironmentVariable('DOCKER_HOST', 'Process'))) {
        throw 'DOCKER_HOST esta definido; se rechazan overrides de daemon.'
    }
    $context = Invoke-Native -FilePath 'docker' -Arguments @('context', 'show') -Capture
    if ([string]::IsNullOrWhiteSpace($context) -or
        $context -match '(?i)(prod|production|stage|staging|remote|demo)') {
        throw 'El contexto Docker activo es vacio o posee un nombre protegido.'
    }
    $endpointRaw = Invoke-Native -FilePath 'docker' -Arguments @(
        'context', 'inspect', '--format', '{{json .Endpoints.docker.Host}}', $context
    ) -Capture
    try { $endpoint = [string]($endpointRaw | ConvertFrom-Json) }
    catch { throw 'El contexto Docker no devolvio un endpoint valido.' }
    if ($endpoint -notmatch '^npipe://' -and $endpoint -cne 'unix:///var/run/docker.sock') {
        throw 'El contexto Docker no apunta a un endpoint local permitido.'
    }
    $osType = Invoke-Native -FilePath 'docker' -Arguments @(
        '--context', $context, 'info', '--format', '{{.OSType}}'
    ) -Capture
    if ($osType.Trim() -cne 'linux') {
        throw 'El daemon Docker E2E debe ser Linux.'
    }
    return $context
}

function Get-DockerProjectSnapshot {
    param([Parameter(Mandatory)][string] $ProjectName)
    if ($ProjectName -cne 'gestudio-remote-demo' -and
        $ProjectName -notmatch '^gestudio-e2e-[a-f0-9]{12}$') {
        throw 'Snapshot Docker rechazado para un proyecto fuera del scope permitido.'
    }
    $containerIds = @((Invoke-Native -FilePath 'docker' -Arguments @(
        'ps', '-aq', '--no-trunc', '--filter', "label=com.docker.compose.project=$ProjectName"
    ) -Capture) -split '[\r\n]+' | Where-Object { $_ } | Sort-Object)
    $containers = @($containerIds | ForEach-Object {
        Invoke-Native -FilePath 'docker' -Arguments @(
            'inspect', '--format',
            '{{.Id}}|{{.Image}}|{{.State.Status}}|{{.State.Running}}|{{.State.Restarting}}|{{.State.Paused}}|{{.State.Dead}}|{{.State.StartedAt}}|{{.State.FinishedAt}}|{{.RestartCount}}',
            $_
        ) -Capture
    } | Sort-Object)
    $volumeNames = @((Invoke-Native -FilePath 'docker' -Arguments @(
        'volume', 'ls', '-q', '--filter', "label=com.docker.compose.project=$ProjectName"
    ) -Capture) -split '[\r\n]+' | Where-Object { $_ } | Sort-Object)
    $volumes = @($volumeNames | ForEach-Object {
        Invoke-Native -FilePath 'docker' -Arguments @(
            'volume', 'inspect', '--format',
            '{{.Name}}|{{.CreatedAt}}|{{.Driver}}|{{.Mountpoint}}|{{.Scope}}',
            $_
        ) -Capture
    } | Sort-Object)
    $networkIds = @((Invoke-Native -FilePath 'docker' -Arguments @(
        'network', 'ls', '-q', '--no-trunc', '--filter', "label=com.docker.compose.project=$ProjectName"
    ) -Capture) -split '[\r\n]+' | Where-Object { $_ } | Sort-Object)
    $networks = @($networkIds | ForEach-Object {
        Invoke-Native -FilePath 'docker' -Arguments @(
            'network', 'inspect', '--format',
            '{{.Id}}|{{.Created}}|{{.Driver}}|{{.Scope}}|{{.Internal}}|{{.Attachable}}|{{.Ingress}}|{{json .Containers}}',
            $_
        ) -Capture
    } | Sort-Object)
    return [pscustomobject]@{
        Containers = $containers
        Volumes = $volumes
        Networks = $networks
    }
}

function Test-DockerProjectSnapshotInvariant {
    param(
        [Parameter(Mandatory)][object] $Before,
        [Parameter(Mandatory)][object] $After
    )
    return (($Before | ConvertTo-Json -Compress -Depth 5) -ceq
        ($After | ConvertTo-Json -Compress -Depth 5))
}

function Set-PrivatePath {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][bool] $Directory
    )
    if ($IsWindows) {
        $item = if ($Directory) { [IO.DirectoryInfo]::new($Path) } else { [IO.FileInfo]::new($Path) }
        $sections = [Security.AccessControl.AccessControlSections]::Access
        $acl = [IO.FileSystemAclExtensions]::GetAccessControl($item, $sections)
        $existingRules = @($acl.GetAccessRules(
            $true, $true, [Security.Principal.SecurityIdentifier]))
        $acl.SetAccessRuleProtection($true, $false)
        foreach ($existingRule in $existingRules) {
            [void]$acl.RemoveAccessRuleAll($existingRule)
        }
        $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent().User
        if ($Directory) {
            $ownerRule = [Security.AccessControl.FileSystemAccessRule]::new(
                $currentIdentity,
                [Security.AccessControl.FileSystemRights]::FullControl,
                ([Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
                    [Security.AccessControl.InheritanceFlags]::ObjectInherit),
                [Security.AccessControl.PropagationFlags]::None,
                [Security.AccessControl.AccessControlType]::Allow)
        } else {
            $ownerRule = [Security.AccessControl.FileSystemAccessRule]::new(
                $currentIdentity,
                [Security.AccessControl.FileSystemRights]::FullControl,
                [Security.AccessControl.AccessControlType]::Allow)
        }
        $acl.AddAccessRule($ownerRule)
        [IO.FileSystemAclExtensions]::SetAccessControl($item, $acl)
        $effectiveAcl = [IO.FileSystemAclExtensions]::GetAccessControl($item, $sections)
        $effectiveRules = @($effectiveAcl.GetAccessRules(
            $true, $true, [Security.Principal.SecurityIdentifier]))
        $unexpectedRules = @($effectiveRules | Where-Object {
            $_.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow -and
            $_.IdentityReference.Value -cne $currentIdentity.Value
        })
        if (-not $effectiveAcl.AreAccessRulesProtected -or $unexpectedRules.Count -gt 0) {
            throw 'No se pudo restringir el recurso E2E al usuario Windows actual.'
        }
    }
    else {
        $mode = if ($Directory) { '700' } else { '600' }
        [void](Invoke-Native -FilePath 'chmod' -Arguments @($mode, '--', $Path))
    }
}

function Write-PrivateFile {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Content
    )
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
    Set-PrivatePath -Path $Path -Directory $false
}

function Get-ComposeArguments {
    param([switch] $Bootstrap)
    $arguments = @(
        'compose', '--env-file', $envFile,
        '-f', $composeFile, '-f', $portsOverride
    )
    if ($Bootstrap) { $arguments += @('-f', $bootstrapOverride) }
    return $arguments + @('-p', $project)
}

function Invoke-Compose {
    param(
        [Parameter(Mandatory)][string[]] $Arguments,
        [switch] $Bootstrap,
        [switch] $Capture,
        [switch] $AllowFailure
    )
    $prefix = Get-ComposeArguments -Bootstrap:$Bootstrap
    return Invoke-Native -FilePath 'docker' -Arguments ($prefix + $Arguments) `
        -Capture:$Capture -AllowFailure:$AllowFailure
}

function Invoke-DatabaseSql {
    param([Parameter(Mandatory)][string] $Sql)
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Sql))
    return Invoke-Compose -Arguments @(
        'exec', '-T', 'db', 'sh', '-ec',
        'printf "%s" "$1" | base64 -d | psql --no-psqlrc --tuples-only --no-align --set ON_ERROR_STOP=1 --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" --file=-',
        'sh', $encoded
    ) -Capture
}

function Assert-ExactContainer {
    param(
        [Parameter(Mandatory)][string] $ContainerId,
        [Parameter(Mandatory)][string] $Service,
        [Parameter(Mandatory)][string] $ExpectedName,
        [Parameter(Mandatory)][bool] $OneOff
    )
    $metadata = Invoke-Native -FilePath 'docker' -Arguments @(
        'inspect', '--format',
        '{{.Id}}|{{index .Config.Labels "com.docker.compose.project"}}|{{index .Config.Labels "com.docker.compose.service"}}|{{index .Config.Labels "com.docker.compose.oneoff"}}|{{.Name}}',
        $ContainerId
    ) -Capture
    $parts = @($metadata -split '\|', 5)
    $expectedOneOff = if ($OneOff) { 'True' } else { 'False' }
    if ($parts.Count -ne 5 -or $parts[0] -cne $ContainerId -or
        $parts[1] -cne $project -or $parts[2] -cne $Service -or
        $parts[3] -ine $expectedOneOff -or $parts[4] -cne "/$ExpectedName") {
        throw "El contenedor no pertenece exactamente al proyecto/servicio E2E esperado."
    }
}

function Get-BootstrapState {
    param([Parameter(Mandatory)][string] $Username)
    $quoted = $Username.Replace("'", "''")
    return (Invoke-DatabaseSql -Sql @"
SELECT
  (SELECT count(*) FROM bootstrap_ejecuciones WHERE tipo='SUPERADMIN_INICIAL')::text || '|' ||
  (SELECT count(*) FROM bootstrap_ejecuciones b
   JOIN usuarios u ON u.id=b.usuario_id AND u.activo AND u.nombre_usuario='$quoted'
   JOIN platform_admins pa ON pa.usuario_id=u.id AND pa.active
   JOIN platform_mfa_credentials mc ON mc.usuario_id=u.id AND mc.method='TOTP'
     AND mc.verified_at IS NOT NULL AND mc.revoked_at IS NULL
   WHERE b.tipo='SUPERADMIN_INICIAL')::text || '|' ||
  (SELECT count(*) FROM bootstrap_ejecuciones b
   JOIN platform_mfa_credentials mc ON mc.usuario_id=b.usuario_id AND mc.method='TOTP'
     AND mc.verified_at IS NOT NULL AND mc.revoked_at IS NULL
   JOIN platform_recovery_codes rc ON rc.credential_id=mc.id AND rc.used_at IS NULL
   WHERE b.tipo='SUPERADMIN_INICIAL')::text || '|' ||
  (SELECT count(*) FROM bootstrap_ejecuciones b
   JOIN tenant_memberships tm ON tm.usuario_id=b.usuario_id
   WHERE b.tipo='SUPERADMIN_INICIAL')::text || '|' ||
  (SELECT coalesce(max(mc.last_counter), -1) FROM bootstrap_ejecuciones b
   JOIN platform_mfa_credentials mc ON mc.usuario_id=b.usuario_id AND mc.method='TOTP'
   WHERE b.tipo='SUPERADMIN_INICIAL')::text;
"@).Trim()
}

function Wait-BootstrapCommitted {
    param([Parameter(Mandatory)][string] $Username)
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    while ($stopwatch.Elapsed -lt [TimeSpan]::FromMinutes(3)) {
        $state = Get-BootstrapState -Username $Username
        if ($state -match '^1\|1\|10\|0\|(?<counter>[0-9]+)$') {
            return [long]$Matches.counter
        }
        $running = Invoke-Native -FilePath 'docker' -Arguments @(
            'inspect', '--format', '{{.State.Running}}|{{.State.ExitCode}}', $bootstrapJobId
        ) -Capture
        if ($running -notmatch '^true\|') {
            throw "El bootstrap one-shot termino antes de confirmar su estado transaccional."
        }
        Start-Sleep -Milliseconds 750
    }
    throw 'El bootstrap one-shot no confirmo el estado esperado dentro del limite.'
}

function Remove-ExactBootstrapJob {
    if ([string]::IsNullOrWhiteSpace($bootstrapJobId)) { return }
    Assert-ExactContainer -ContainerId $bootstrapJobId -Service 'backend' `
        -ExpectedName "$project-platform-bootstrap-$suffix" -OneOff $true
    [void](Invoke-Native -FilePath 'docker' -Arguments @('container', 'rm', '-f', $bootstrapJobId))
    $remaining = Invoke-Native -FilePath 'docker' -Arguments @(
        'ps', '-aq', '--filter', "label=com.docker.compose.project=$project",
        '--filter', 'label=com.docker.compose.service=backend',
        '--filter', 'label=com.docker.compose.oneoff=True'
    ) -Capture
    if (-not [string]::IsNullOrWhiteSpace($remaining)) {
        throw 'Persisten jobs one-shot del backend tras eliminar el ID exacto.'
    }
    $script:bootstrapJobId = $null
}

function Assert-OwnedResource {
    param(
        [Parameter(Mandatory)][ValidateSet('container', 'volume', 'network', 'image')][string] $Kind,
        [Parameter(Mandatory)][string] $Id
    )
    if ($Kind -eq 'image') {
        if ($Id -notin @($backendImage, $frontendImage) -or
            $Id -notmatch '^gestudio-(backend|frontend):e2e-[a-f0-9]{12}$' -or
            $Id -notlike "*:e2e-$suffix") {
            throw "Cleanup fail-closed: tag de imagen fuera del scope E2E exacto."
        }
        $metadata = Invoke-Native -FilePath 'docker' -Arguments @(
            'image', 'inspect', '--format', '{{json .RepoTags}}', $Id
        ) -Capture
        $tags = @($metadata | ConvertFrom-Json)
        if ($tags -notcontains $Id) {
            throw "Cleanup fail-closed: la imagen no posee el tag E2E exacto."
        }
        return
    }
    if ($Kind -in @('volume', 'network')) {
        $metadata = Invoke-Native -FilePath 'docker' -Arguments @(
            $Kind, 'inspect', '--format',
            '{{index .Labels "com.docker.compose.project"}}|{{index .Labels "com.docker.compose.service"}}',
            $Id
        ) -Capture
    } else {
        $metadata = Invoke-Native -FilePath 'docker' -Arguments @(
            $Kind, 'inspect', '--format',
            '{{index .Config.Labels "com.docker.compose.project"}}|{{index .Config.Labels "com.docker.compose.service"}}',
            $Id
        ) -Capture
    }
    $parts = @($metadata -split '\|', 2)
    if ($parts.Count -ne 2 -or $parts[0] -cne $project) {
        throw "Cleanup fail-closed: $Kind $Id no posee ownership exacto del proyecto."
    }
}

function Remove-LabeledResources {
    $containers = @(Invoke-Native -FilePath 'docker' -Arguments @(
        'ps', '-aq', '--filter', "label=com.docker.compose.project=$project"
    ) -Capture) -split '[\r\n]+' | Where-Object { $_ }
    foreach ($id in $containers) {
        Assert-OwnedResource -Kind container -Id $id
        [void](Invoke-Native -FilePath 'docker' -Arguments @('container', 'rm', '-f', $id))
    }

    $volumes = @(Invoke-Native -FilePath 'docker' -Arguments @(
        'volume', 'ls', '-q', '--filter', "label=com.docker.compose.project=$project"
    ) -Capture) -split '[\r\n]+' | Where-Object { $_ }
    foreach ($name in $volumes) {
        Assert-OwnedResource -Kind volume -Id $name
        [void](Invoke-Native -FilePath 'docker' -Arguments @('volume', 'rm', $name))
    }

    $networks = @(Invoke-Native -FilePath 'docker' -Arguments @(
        'network', 'ls', '-q', '--filter', "label=com.docker.compose.project=$project"
    ) -Capture) -split '[\r\n]+' | Where-Object { $_ }
    foreach ($id in $networks) {
        Assert-OwnedResource -Kind network -Id $id
        [void](Invoke-Native -FilePath 'docker' -Arguments @('network', 'rm', $id))
    }

    foreach ($tag in @($backendImage, $frontendImage)) {
        if ([string]::IsNullOrWhiteSpace($tag)) { continue }
        $id = Invoke-Native -FilePath 'docker' -Arguments @(
            'image', 'ls', '-q', '--no-trunc', $tag
        ) -Capture
        if (-not [string]::IsNullOrWhiteSpace($id)) {
            Assert-OwnedResource -Kind image -Id $tag
            [void](Invoke-Native -FilePath 'docker' -Arguments @('image', 'rm', '-f', $tag))
            $remainingTag = Invoke-Native -FilePath 'docker' -Arguments @(
                'image', 'ls', '-q', '--no-trunc', $tag
            ) -Capture
            if (-not [string]::IsNullOrWhiteSpace($remainingTag)) {
                throw 'Cleanup E2E incompleto: persiste el tag de imagen exacto.'
            }
        }
    }

    $residual = @(
        @(
            Invoke-Native -FilePath 'docker' -Arguments @('ps', '-aq', '--filter', "label=com.docker.compose.project=$project") -Capture
            Invoke-Native -FilePath 'docker' -Arguments @('volume', 'ls', '-q', '--filter', "label=com.docker.compose.project=$project") -Capture
            Invoke-Native -FilePath 'docker' -Arguments @('network', 'ls', '-q', '--filter', "label=com.docker.compose.project=$project") -Capture
            Invoke-Native -FilePath 'docker' -Arguments @('image', 'ls', '-q', $backendImage) -Capture
            Invoke-Native -FilePath 'docker' -Arguments @('image', 'ls', '-q', $frontendImage) -Capture
        ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    if ($residual.Count -gt 0) { throw 'Cleanup E2E incompleto: persisten recursos con el label del proyecto.' }
}

function Remove-PrivateRunRoot {
    if ([string]::IsNullOrWhiteSpace($runRoot) -or -not (Test-Path -LiteralPath $runRoot)) { return }
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd(
        [IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $resolved = [IO.Path]::GetFullPath($runRoot)
    if (-not $resolved.StartsWith($tempRoot + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path $resolved -Leaf) -cne $project) {
        throw 'Se rechazo borrar un directorio temporal fuera del scope E2E exacto.'
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}

function Write-SanitizedArtifacts {
    param([Parameter(Mandatory)][string] $Status)
    [IO.Directory]::CreateDirectory($artifactRoot) | Out-Null
    $logPath = Join-Path $artifactRoot 'playwright.log'
    $safeLines = @($playwrightLog | ForEach-Object { ConvertTo-SafeText $_ })
    [IO.File]::WriteAllLines($logPath, $safeLines, [Text.UTF8Encoding]::new($false))
    $result = [ordered]@{
        schemaVersion = 1
        status = $Status
        phase = 'control-plane-e2e'
        runId = $suffix
        composeProject = $project
        dockerContext = if ($dockerContext) { ConvertTo-SafeText $dockerContext } else { $null }
        protectedDemoInvariant = $protectedDemoInvariant
        composeProjectInvariant = $projectInvariant
        gitSha = (Invoke-Native -FilePath 'git' -Arguments @('-C', $repoRoot, 'rev-parse', 'HEAD') -Capture)
        worktreeClean = [string]::IsNullOrWhiteSpace((Invoke-Native -FilePath 'git' -Arguments @('-C', $repoRoot, 'status', '--porcelain') -Capture))
        backendSourceFingerprint = if ($backendSourceSha) { $backendSourceSha } else { $null }
        frontendSourceFingerprint = if ($frontendSourceSha) { $frontendSourceSha } else { $null }
        composeFingerprint = if (Test-Path -LiteralPath $composeFile) { Get-FileSha256 -Path $composeFile } else { $null }
        startedAt = $startedAt.ToString('O')
        completedAt = [DateTimeOffset]::UtcNow.ToString('O')
        framework = '@playwright/test 1.62.1'
        browser = 'chromium'
        axe = '@axe-core/playwright 4.13.0; wcag2a,wcag2aa,wcag21a,wcag21aa,wcag22aa; no exclusions'
        sensitiveArtifacts = 'trace=off; video=off; screenshot=off; html=off'
        evidenceProfile = 'dev localhost; ProductionConfigurationGuardTest remains a separate gate'
        runtime = $playwrightStatus
        cleanup = if ($cleanupFailure) { 'FAIL' } else { 'PASS' }
        failure = if ($primaryFailure) { ConvertTo-SafeText $primaryFailure } else { $null }
    }
    [IO.File]::WriteAllText(
        (Join-Path $artifactRoot 'result.json'),
        ($result | ConvertTo-Json -Depth 4),
        [Text.UTF8Encoding]::new($false))
}

try {
    if (-not (Test-Path -LiteralPath $composeFile -PathType Leaf)) { throw 'Falta docker-compose.yml.' }
    if (-not (Test-Path -LiteralPath (Join-Path $frontendRoot 'package-lock.json') -PathType Leaf)) {
        throw 'Falta frontend/package-lock.json.'
    }
    $dockerContext = Assert-LocalDockerTarget
    [Environment]::SetEnvironmentVariable('DOCKER_CONTEXT', $dockerContext, 'Process')
    $dockerContextApplied = $true
    [void](Invoke-Native -FilePath 'docker' -Arguments @('version', '--format', '{{.Server.Version}}') -Capture)
    [void](Invoke-Native -FilePath 'docker' -Arguments @('compose', 'version', '--short') -Capture)
    $protectedDemoBefore = Get-DockerProjectSnapshot -ProjectName 'gestudio-remote-demo'
    $protectedDemoSnapshotCaptured = $true

    $suffix = New-RandomHex -Bytes 6
    $project = "gestudio-e2e-$suffix"
    if ($project -ceq 'gestudio-remote-demo' -or $project -notmatch '^gestudio-e2e-[a-f0-9]{12}$') {
        throw 'Nombre de proyecto E2E invalido o protegido.'
    }
    $projectBefore = Get-DockerProjectSnapshot -ProjectName $project
    $projectSnapshotCaptured = $true
    if ($projectBefore.Containers.Count -ne 0 -or
        $projectBefore.Volumes.Count -ne 0 -or
        $projectBefore.Networks.Count -ne 0) {
        throw 'Preflight E2E rechazo un proyecto Compose con recursos preexistentes.'
    }
    $backendImage = "gestudio-backend:e2e-$suffix"
    $frontendImage = "gestudio-frontend:e2e-$suffix"
    foreach ($tag in @($backendImage, $frontendImage)) {
        $existing = Invoke-Native -FilePath 'docker' -Arguments @(
            'image', 'ls', '-q', '--no-trunc', $tag
        ) -Capture
        if (-not [string]::IsNullOrWhiteSpace($existing)) {
            throw 'Preflight E2E rechazo un tag de imagen preexistente.'
        }
    }
    $runRoot = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) $project))
    if (Test-Path -LiteralPath $runRoot) { throw 'El directorio temporal E2E ya existe.' }
    [IO.Directory]::CreateDirectory($runRoot) | Out-Null
    Set-PrivatePath -Path $runRoot -Directory $true
    $envFile = Join-Path $runRoot 'e2e.env'
    $portsOverride = Join-Path $runRoot 'ports.compose.yml'
    $bootstrapOverride = Join-Path $runRoot 'bootstrap.compose.yml'
    $playwrightOutput = Join-Path $runRoot 'playwright-output'

    $backendPort = Get-FreeLoopbackPort
    do { $frontendPort = Get-FreeLoopbackPort } while ($frontendPort -eq $backendPort)
    $platformTotpBytes = New-RandomBytes -Count 20
    $platformTotpSecret = ConvertTo-Base32 -Bytes $platformTotpBytes
    $bootstrapTotpCode = '000000'
    $platformPassword = "Aa9!$(New-RandomHex -Bytes 18)"
    $alphaPassword = "Aa9!$(New-RandomHex -Bytes 16)"
    $betaPassword = "Aa9!$(New-RandomHex -Bytes 16)"
    $postgresPassword = New-RandomHex -Bytes 24
    $appPassword = New-RandomHex -Bytes 24
    $controlPassword = New-RandomHex -Bytes 24
    $jwtSecret = New-RandomHex -Bytes 48
    $mfaKey = [Convert]::ToBase64String((New-RandomBytes -Count 32))
    $metricsToken = New-RandomHex -Bytes 32
    $platformUsername = "platform.e2e.$suffix"
    $alphaUsername = "alpha.admin.$suffix"
    $betaUsername = "beta.admin.$suffix"
    $alphaCode = "danza-marcos-paz-$suffix"
    $betaCode = "beta-e2e-$suffix"
    foreach ($secret in @(
        $platformTotpSecret, $platformPassword, $alphaPassword,
        $betaPassword, $postgresPassword, $appPassword, $controlPassword,
        $jwtSecret, $mfaKey, $metricsToken
    )) { $secretValues.Add($secret) }

    $sourceSha = Invoke-Native -FilePath 'git' -Arguments @('-C', $repoRoot, 'rev-parse', 'HEAD') -Capture
    $backendSourceSha = Get-SourceFingerprint -Path (Join-Path $repoRoot 'backend')
    $frontendSourceSha = Get-SourceFingerprint -Path (Join-Path $repoRoot 'frontend')
    $composeSha = Get-FileSha256 -Path $composeFile
    $envValues = [ordered]@{
        COMPOSE_PROJECT_NAME = $project
        POSTGRES_DB = "gestudio_e2e_$suffix"
        POSTGRES_USER = "ge2e_$suffix"
        POSTGRES_PASSWORD = $postgresPassword
        POSTGRES_APP_USER = "ge2e_${suffix}_app"
        POSTGRES_APP_PASSWORD = $appPassword
        POSTGRES_CONTROL_USER = "ge2e_${suffix}_ctl"
        POSTGRES_CONTROL_PASSWORD = $controlPassword
        SPRING_PROFILES_ACTIVE = 'dev'
        SPRING_FLYWAY_ENABLED = 'true'
        SPRING_FLYWAY_BASELINE_ON_MIGRATE = 'false'
        SPRING_JPA_HIBERNATE_DDL_AUTO = 'validate'
        APP_MULTITENANCY_REQUIRED = 'true'
        JWT_SECRET = $jwtSecret
        JWT_ISSUER = "gestudio-e2e-$suffix"
        JWT_ACCESS_TOKEN_TTL = 'PT15M'
        JWT_REFRESH_TOKEN_TTL = 'PT2H'
        JWT_PLATFORM_AUDIENCE = "gestudio-e2e-platform-$suffix"
        APP_PLATFORM_ACCESS_TOKEN_TTL = 'PT10M'
        APP_PLATFORM_REFRESH_TOKEN_TTL = 'PT2H'
        APP_PLATFORM_STEP_UP_TTL = 'PT5M'
        APP_PLATFORM_MFA_ENCRYPTION_KEY = $mfaKey
        APP_PLATFORM_MFA_KEY_VERSION = '1'
        APP_PLATFORM_REFRESH_COOKIE_NAME = "gestudio_e2e_platform_$suffix"
        APP_PLATFORM_REFRESH_COOKIE_SECURE = 'false'
        APP_PLATFORM_REFRESH_COOKIE_SAME_SITE = 'Strict'
        APP_PLATFORM_REFRESH_COOKIE_PATH = '/api/platform/auth'
        APP_SECURITY_REFRESH_COOKIE_NAME = "gestudio_e2e_tenant_$suffix"
        APP_SECURITY_REFRESH_COOKIE_SECURE = 'false'
        APP_SECURITY_REFRESH_COOKIE_SAME_SITE = 'Strict'
        APP_SECURITY_REFRESH_COOKIE_PATH = '/api/login'
        APP_CORS_ALLOWED_ORIGINS = "http://127.0.0.1:$frontendPort"
        APP_SCHEDULING_ENABLED = 'false'
        APP_EMAIL_ENABLED = 'false'
        APP_EMAIL_PROVIDER = 'NOOP'
        APP_EMAIL_DRY_RUN = 'true'
        APP_EMAIL_REAL_NETWORK_ALLOWED = 'false'
        APP_EMAIL_KILL_SWITCH = 'true'
        APP_EMAIL_SENT_COPY_MODE = 'DISABLED'
        APP_OBSERVABILITY_METRICS_TOKEN = $metricsToken
        APP_BOOTSTRAP_SUPERADMIN_ENABLED = 'true'
        APP_BOOTSTRAP_SUPERADMIN_USERNAME = $platformUsername
        APP_BOOTSTRAP_SUPERADMIN_PASSWORD = $platformPassword
        APP_BOOTSTRAP_PLATFORM_TOTP_SECRET = $platformTotpSecret
        APP_BOOTSTRAP_PLATFORM_TOTP_CODE = $bootstrapTotpCode
        APP_BOOTSTRAP_PLATFORM_RECOVERY_CODES_FILE = '/tmp/gestudio-platform-recovery-codes.txt'
        APP_LOCAL_ADMIN_PASSWORD_RESET_ENABLED = 'false'
        BACKEND_IMAGE = $backendImage
        FRONTEND_IMAGE = $frontendImage
        BACKEND_PORT = [string]$backendPort
        FRONTEND_PORT = [string]$frontendPort
        SERVER_PORT = '8080'
        VITE_API_BASE_URL = "http://127.0.0.1:$backendPort/api"
        VITE_APP_TIME_ZONE = 'America/Argentina/Buenos_Aires'
        APP_TIME_ZONE = 'America/Argentina/Buenos_Aires'
        VCS_REF = $sourceSha
        COMPOSE_SHA = $composeSha
        BACKEND_SOURCE_SHA = $backendSourceSha
        FRONTEND_SOURCE_SHA = $frontendSourceSha
    }
    foreach ($entry in $envValues.GetEnumerator()) {
        if ([string]$entry.Value -match '[\r\n]') { throw "Valor multilinea rechazado: $($entry.Key)" }
    }
    $envContent = ($envValues.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "`n"
    Write-PrivateFile -Path $envFile -Content ($envContent + "`n")
    Write-PrivateFile -Path $portsOverride -Content @"
services:
  db:
    ports: !reset []
  backend:
    ports: !override
      - "127.0.0.1:${backendPort}:8080"
  frontend:
    ports: !override
      - "127.0.0.1:${frontendPort}:8080"
"@
    Write-PrivateFile -Path $bootstrapOverride -Content @'
services:
  backend:
    restart: "no"
    environment:
      APP_BOOTSTRAP_SUPERADMIN_ENABLED: ${APP_BOOTSTRAP_SUPERADMIN_ENABLED:?required}
      APP_BOOTSTRAP_SUPERADMIN_USERNAME: ${APP_BOOTSTRAP_SUPERADMIN_USERNAME:?required}
      APP_BOOTSTRAP_SUPERADMIN_PASSWORD: ${APP_BOOTSTRAP_SUPERADMIN_PASSWORD:?required}
      APP_BOOTSTRAP_PLATFORM_TOTP_SECRET: ${APP_BOOTSTRAP_PLATFORM_TOTP_SECRET:?required}
      APP_BOOTSTRAP_PLATFORM_TOTP_CODE: ${APP_BOOTSTRAP_PLATFORM_TOTP_CODE:?required}
      APP_BOOTSTRAP_PLATFORM_RECOVERY_CODES_FILE: ${APP_BOOTSTRAP_PLATFORM_RECOVERY_CODES_FILE:?required}
'@

    $configJson = Invoke-Compose -Arguments @('config', '--format', 'json') -Capture
    $config = $configJson | ConvertFrom-Json -Depth 30
    if ($config.name -cne $project -or
        $null -ne $config.services.db.PSObject.Properties['ports'] -or
        $config.services.backend.ports.Count -ne 1 -or
        $config.services.backend.ports[0].host_ip -cne '127.0.0.1' -or
        [int]$config.services.backend.ports[0].published -ne $backendPort -or
        $config.services.frontend.ports.Count -ne 1 -or
        $config.services.frontend.ports[0].host_ip -cne '127.0.0.1' -or
        [int]$config.services.frontend.ports[0].published -ne $frontendPort -or
        $config.services.backend.environment.APP_BOOTSTRAP_SUPERADMIN_ENABLED -cne 'false' -or
        $config.services.backend.image -cne $backendImage -or
        $config.services.frontend.image -cne $frontendImage) {
        throw 'Compose E2E efectivo no cumple aislamiento, loopback o bootstrap-off ordinario.'
    }
    $configJson = $null
    $config = $null

    [void](Invoke-Compose -Arguments @('up', '-d', '--build', '--wait', '--wait-timeout', '420'))
    $composeStarted = $true

    $migrationRoot = Join-Path $repoRoot 'backend\src\main\resources\db\migration'
    $versioned = @(Get-ChildItem -LiteralPath $migrationRoot -File -Filter 'V*__*.sql' | ForEach-Object {
        if ($_.Name -match '^V(?<version>[0-9]+)__') {
            [pscustomobject]@{ Version = [int]$Matches.version; Script = $_.Name }
        }
    })
    $latestMigration = ($versioned | Measure-Object -Property Version -Maximum).Maximum
    $baselineScripts = @(Get-ChildItem -LiteralPath $migrationRoot -File -Filter "B${latestMigration}__*.sql")
    if ($baselineScripts.Count -ne 1) { throw 'No existe un baseline fresh unico para la ultima version.' }
    $baselineScript = $baselineScripts[0].Name
    $freshOutput = Invoke-DatabaseSql -Sql @"
DO `$fresh`$
DECLARE item record; has_rows boolean;
BEGIN
  FOR item IN
    SELECT table_schema, table_name
    FROM information_schema.tables
    WHERE table_schema='public'
      AND table_type='BASE TABLE'
      AND table_name NOT IN ('permisos', 'flyway_schema_history')
  LOOP
    EXECUTE format('SELECT EXISTS (SELECT 1 FROM %I.%I)', item.table_schema, item.table_name)
      INTO has_rows;
    IF has_rows THEN
      RAISE EXCEPTION 'fresh functional table is not empty: %.%', item.table_schema, item.table_name;
    END IF;
  END LOOP;
END
`$fresh`$;
SELECT
  (SELECT count(*) FROM tenants)::text || '|' ||
  (SELECT count(*) FROM usuarios)::text || '|' ||
  (SELECT count(*) FROM tenant_memberships)::text || '|' ||
  (SELECT count(*) FROM platform_admins)::text || '|' ||
  (SELECT count(*) FROM platform_audit_events)::text || '|' ||
  (SELECT count(*) FROM bootstrap_ejecuciones)::text || '|' ||
  (SELECT count(*) FROM flyway_schema_history WHERE success)::text || '|' ||
  (SELECT version || ':' || type || ':' || script FROM flyway_schema_history WHERE success)::text || '|' ||
  (SELECT count(*) FROM flyway_schema_history WHERE NOT success)::text || '|' ||
  (SELECT count(*) FROM permisos)::text || '|' ||
  (SELECT count(*) FROM permisos WHERE activo AND sistema)::text || '|' ||
  (SELECT count(*) FROM roles)::text || '|' ||
  public.gestudio_multitenancy_health() || '|' ||
  (SELECT count(*) FROM pg_constraint c
   JOIN pg_class t ON t.oid=c.conrelid
   JOIN pg_namespace n ON n.oid=t.relnamespace
   WHERE n.nspname='public' AND c.contype='f' AND NOT EXISTS (
     SELECT 1 FROM pg_index i
     WHERE i.indrelid=c.conrelid AND i.indisvalid AND i.indisready
       AND i.indpred IS NULL AND i.indnkeyatts >= cardinality(c.conkey)
       AND NOT EXISTS (
         SELECT 1 FROM unnest(c.conkey) WITH ORDINALITY fk(attnum, pos)
         LEFT JOIN unnest(i.indkey::smallint[]) WITH ORDINALITY ix(attnum, pos)
           ON ix.pos=fk.pos
         WHERE ix.attnum IS DISTINCT FROM fk.attnum
       )
   ))::text;
"@
    $freshRows = @($freshOutput -split '[\r\n]+' |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -cne 'DO' })
    if ($freshRows.Count -ne 1) {
        throw 'La consulta fresh no produjo una unica fila de estado.'
    }
    $freshState = $freshRows[0].Trim()
    $expectedFresh = "0|0|0|0|0|0|1|${latestMigration}:SQL_BASELINE:${baselineScript}|0|32|32|0|GREEN|0"
    if ($freshState -cne $expectedFresh) {
        throw "La base fresh no quedo sin seed funcional o Flyway no quedo sano. Estado actual: $freshState"
    }

    $bootstrapCounter = [long][Math]::Floor([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() / 30)
    $bootstrapTotpCode = Get-TotpCode -Secret $platformTotpBytes -Counter $bootstrapCounter
    $secretValues.Add($bootstrapTotpCode)
    $envValues.APP_BOOTSTRAP_PLATFORM_TOTP_CODE = $bootstrapTotpCode
    $envContent = ($envValues.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "`n"
    Write-PrivateFile -Path $envFile -Content ($envContent + "`n")

    $jobName = "$project-platform-bootstrap-$suffix"
    [void](Invoke-Compose -Bootstrap -Arguments @(
        'run', '--detach', '--no-deps', '--name', $jobName, 'backend'
    ) -Capture)
    $bootstrapJobId = Invoke-Native -FilePath 'docker' -Arguments @(
        'ps', '-aq', '--no-trunc', '--filter', "name=^/$jobName`$"
    ) -Capture
    if ($bootstrapJobId -notmatch '^[a-f0-9]{64}$') { throw 'No se resolvio un unico ID bootstrap exacto.' }
    Assert-ExactContainer -ContainerId $bootstrapJobId -Service 'backend' -ExpectedName $jobName -OneOff $true
    $consumedCounter = Wait-BootstrapCommitted -Username $platformUsername
    [void](Invoke-Native -FilePath 'docker' -Arguments @(
        'exec', $bootstrapJobId, 'sh', '-ec',
        'test -f /tmp/gestudio-platform-recovery-codes.txt && test "$(stat -c %a /tmp/gestudio-platform-recovery-codes.txt)" = 600 && test "$(wc -l < /tmp/gestudio-platform-recovery-codes.txt)" -eq 10 && awk ''BEGIN{ok=1} !/^[A-Z2-7]{8}-[A-Z2-7]{8}-[A-Z2-7]{8}-[A-Z2-7]{2}$/{ok=0} END{exit ok?0:1}'' /tmp/gestudio-platform-recovery-codes.txt'
    ))
    Remove-ExactBootstrapJob

    $testEnvironment = [ordered]@{
        GESTUDIO_E2E_BASE_URL = "http://127.0.0.1:$frontendPort"
        GESTUDIO_E2E_API_URL = "http://127.0.0.1:$backendPort/api"
        GESTUDIO_E2E_OUTPUT_DIR = $playwrightOutput
        GESTUDIO_E2E_COMPOSE_PROJECT = $project
        GESTUDIO_E2E_RUN_ID = $suffix
        GESTUDIO_E2E_BOOTSTRAP_COUNTER = [string]$consumedCounter
        GESTUDIO_E2E_PLATFORM_USERNAME = $platformUsername
        GESTUDIO_E2E_PLATFORM_PASSWORD = $platformPassword
        GESTUDIO_E2E_PLATFORM_TOTP_SECRET = $platformTotpSecret
        GESTUDIO_E2E_ALPHA_CODE = $alphaCode
        GESTUDIO_E2E_ALPHA_NAME = 'Escuela Danza Marcos Paz'
        GESTUDIO_E2E_ALPHA_USERNAME = $alphaUsername
        GESTUDIO_E2E_ALPHA_PASSWORD = $alphaPassword
        GESTUDIO_E2E_BETA_CODE = $betaCode
        GESTUDIO_E2E_BETA_NAME = 'Escuela Beta E2E'
        GESTUDIO_E2E_BETA_USERNAME = $betaUsername
        GESTUDIO_E2E_BETA_PASSWORD = $betaPassword
    }
    foreach ($entry in $testEnvironment.GetEnumerator()) {
        $environmentBackup[$entry.Key] = [Environment]::GetEnvironmentVariable($entry.Key, 'Process')
        [Environment]::SetEnvironmentVariable($entry.Key, [string]$entry.Value, 'Process')
    }
    $environmentApplied = $true
    Push-Location $frontendRoot
    try {
        $rawTestOutput = @(& npm exec -- playwright test --config playwright.config.ts 2>&1 |
            ForEach-Object { [string]$_ })
        $testExit = $LASTEXITCODE
    }
    finally { Pop-Location }
    foreach ($line in $rawTestOutput) { $playwrightLog.Add((ConvertTo-SafeText $line)) }
    if ($testExit -ne 0) {
        $playwrightStatus = 'EXECUTED_FAIL'
        throw "Playwright E2E fallo con exit code $testExit. Consulte el log sanitizado."
    }
    $playwrightStatus = 'EXECUTED_PASS'

    $finalState = (Invoke-DatabaseSql -Sql @"
SELECT
  (SELECT count(*) FROM tenants)::text || '|' ||
  (SELECT count(*) FROM tenants WHERE status='ACTIVE')::text || '|' ||
  (SELECT count(*) FROM usuarios)::text || '|' ||
  (SELECT count(*) FROM tenant_memberships WHERE status='ACTIVE')::text || '|' ||
  (SELECT count(*) FROM alumnos a JOIN tenants t ON t.id=a.tenant_id
    WHERE t.code='$alphaCode' AND a.apellido='Alpha E2E $suffix')::text || '|' ||
  (SELECT count(*) FROM alumnos a JOIN tenants t ON t.id=a.tenant_id
    WHERE t.code='$betaCode' AND a.apellido='Beta E2E $suffix')::text || '|' ||
  (SELECT count(*) FROM alumnos)::text || '|' ||
  (SELECT count(*) FROM platform_audit_events WHERE action='PLATFORM_SUPERADMIN_BOOTSTRAP' AND result='SUCCESS')::text || '|' ||
  (SELECT count(*) FROM platform_audit_events WHERE action='TENANT_CREATE' AND result='SUCCESS')::text || '|' ||
  (SELECT count(*) FROM platform_audit_events WHERE action='TENANT_CREATE' AND result='DENIED')::text || '|' ||
  (SELECT count(*) FROM platform_audit_events WHERE action='TENANT_STATUS' AND result='SUCCESS')::text || '|' ||
  (SELECT count(*) FROM platform_audit_events WHERE action='TENANT_STATUS' AND result='DENIED')::text || '|' ||
  (SELECT count(*) FROM platform_audit_events WHERE action='PLATFORM_IDENTITY_ACTIVATED' AND result='SUCCESS')::text || '|' ||
  (SELECT count(*) FROM platform_audit_events)::text;
"@).Trim()
    if ($finalState -cne '2|2|3|2|1|1|2|1|2|2|2|2|2|11') {
        throw 'La reconciliacion SQL final no coincide con el flujo E2E completo.'
    }
}
catch {
    $primaryFailure = ConvertTo-SafeText $_.Exception.Message
}
finally {
    if ($environmentApplied) {
        foreach ($entry in $environmentBackup.GetEnumerator()) {
            [Environment]::SetEnvironmentVariable([string]$entry.Key, $entry.Value, 'Process')
        }
    }
    try {
        if ($bootstrapJobId) { Remove-ExactBootstrapJob }
        if ($project -and $envFile -and $portsOverride -and (Test-Path -LiteralPath $envFile)) {
            [void](Invoke-Compose -Arguments @('down', '--volumes', '--remove-orphans') -AllowFailure)
            Remove-LabeledResources
        }
    }
    catch { Add-CleanupFailure -Message $_.Exception.Message }
    if ($projectSnapshotCaptured) {
        try {
            $projectAfter = Get-DockerProjectSnapshot -ProjectName $project
            if (Test-DockerProjectSnapshotInvariant -Before $projectBefore -After $projectAfter) {
                $projectInvariant = if ($projectBefore.Containers.Count -eq 0 -and
                    $projectBefore.Volumes.Count -eq 0 -and
                    $projectBefore.Networks.Count -eq 0) { 'ABSENT_UNCHANGED' } else { 'PRESENT_UNCHANGED' }
            } else {
                $projectInvariant = 'CHANGED'
                Add-CleanupFailure -Message 'El proyecto Compose E2E no volvio al snapshot previo exacto.'
            }
        }
        catch {
            $projectInvariant = 'NOT_VERIFIED'
            Add-CleanupFailure -Message $_.Exception.Message
        }
    }
    if ($protectedDemoSnapshotCaptured) {
        try {
            $protectedDemoAfter = Get-DockerProjectSnapshot -ProjectName 'gestudio-remote-demo'
            if (Test-DockerProjectSnapshotInvariant -Before $protectedDemoBefore -After $protectedDemoAfter) {
                $protectedDemoInvariant = if ($protectedDemoBefore.Containers.Count -eq 0 -and
                    $protectedDemoBefore.Volumes.Count -eq 0 -and
                    $protectedDemoBefore.Networks.Count -eq 0) { 'ABSENT_UNCHANGED' } else { 'PRESENT_UNCHANGED' }
            } else {
                $protectedDemoInvariant = 'CHANGED'
                Add-CleanupFailure -Message 'El proyecto protegido gestudio-remote-demo cambio durante el E2E.'
            }
        }
        catch {
            $protectedDemoInvariant = 'NOT_VERIFIED'
            Add-CleanupFailure -Message $_.Exception.Message
        }
    }
    if ($dockerContextApplied) {
        try { [Environment]::SetEnvironmentVariable('DOCKER_CONTEXT', $dockerContextBackup, 'Process') }
        catch { Add-CleanupFailure -Message 'No se pudo restaurar DOCKER_CONTEXT.' }
        $dockerContextApplied = $false
    }
    try { Remove-PrivateRunRoot }
    catch {
        Add-CleanupFailure -Message $_.Exception.Message
    }
    $status = if (-not $primaryFailure -and -not $cleanupFailure -and $playwrightStatus -eq 'EXECUTED_PASS') {
        'PASS'
    } else { 'FAIL' }
    try { Write-SanitizedArtifacts -Status $status }
    catch {
        if (-not $primaryFailure) { $primaryFailure = 'No se pudieron escribir artefactos sanitizados.' }
    }
    $secretValues.Clear()
}

if ($cleanupFailure) {
    if ($primaryFailure) { throw "$primaryFailure Cleanup: $cleanupFailure" }
    throw "Cleanup E2E fallo: $cleanupFailure"
}
if ($primaryFailure) { throw $primaryFailure }
Write-Host "Control-plane E2E: PASS. Resultado sanitizado en artifacts/e2e/result.json"
