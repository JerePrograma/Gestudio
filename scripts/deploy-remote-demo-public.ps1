[CmdletBinding()]
param(
    [ValidateSet('Start', 'Status', 'Stop')]
    [string] $Action = 'Start',
    [switch] $RotatePublicCredential,
    [string] $RepoPath = 'C:\laburo\Gestudio',
    [string] $PagesProject = 'gestudio-demo-jere-287b8c90',
    [string] $PagesOrigin = 'https://gestudio-demo-jere-287b8c90.pages.dev',
    [int] $BackendPort = 18080
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http

$expectedPagesProject = 'gestudio-demo-jere-287b8c90'
$expectedPagesOrigin = 'https://gestudio-demo-jere-287b8c90.pages.dev'
$publicUsername = 'alpha.demo.presentacion'
$publicRoleCode = 'DEMO_COMERCIAL'
$publicPermissions = @(
    'PERM_APP_ACCESO',
    'PERM_ALUMNOS_LEER',
    'PERM_INSCRIPCIONES_LEER',
    'PERM_DISCIPLINAS_LEER',
    'PERM_PROFESORES_LEER',
    'PERM_ASISTENCIAS_LEER',
    'PERM_PAGOS_LEER',
    'PERM_CAJA_LEER',
    'PERM_STOCK_LEER',
    'PERM_REPORTES_LEER',
    'PERM_CONFIG_LEER'
)

$repoRoot = [IO.Path]::GetFullPath($RepoPath)
$frontendRoot = Join-Path $repoRoot 'frontend'
$launcherPath = Join-Path $repoRoot 'scripts\demo-local-multitenant.ps1'
$backendOrigin = "http://127.0.0.1:$BackendPort"
$pagesOriginNormalized = $PagesOrigin.TrimEnd('/')
$localData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
if ([string]::IsNullOrWhiteSpace($localData)) { throw 'No se pudo resolver LOCALAPPDATA.' }
$demoStateRoot = [IO.Path]::GetFullPath((Join-Path $localData 'Gestudio\gestudio-demo-local'))
$credentialManifest = Join-Path $demoStateRoot 'credentials.json'
$demoEnvironment = Join-Path $demoStateRoot 'e2e.env'
$publicStateRoot = [IO.Path]::GetFullPath((Join-Path $localData 'Gestudio\gestudio-demo-public'))
$publicStatePath = Join-Path $publicStateRoot 'public-deployment.json'
$tunnelLogRoot = Join-Path $publicStateRoot 'logs'
$documentsRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
$legacyStateRoot = Join-Path $documentsRoot 'Gestudio-RemoteDemo'
$legacyStatePaths = @(
    (Join-Path $legacyStateRoot 'public-deployment.json'),
    (Join-Path $legacyStateRoot 'quick-tunnel.json')
)
$secretValues = [Collections.Generic.List[string]]::new()
$temporarySecretFile = $null
$newTunnelProcess = $null

function Add-Secret {
    param([AllowNull()][string] $Value)
    if (-not [string]::IsNullOrEmpty($Value) -and -not $script:secretValues.Contains($Value)) {
        $script:secretValues.Add($Value)
    }
}

function ConvertTo-SafeText {
    param([AllowNull()][object] $Value)
    $safe = if ($null -eq $Value) { '' } else { [string]$Value }
    $safe = [regex]::Replace(
        $safe,
        '(?i)https://[a-z0-9-]+[.]trycloudflare[.]com',
        '[QUICK_TUNNEL_REDACTED]'
    )
    $safe = [regex]::Replace(
        $safe,
        '(?i)[a-z0-9-]+[.]trycloudflare[.]com',
        '[QUICK_TUNNEL_REDACTED]'
    )
    foreach ($secret in $script:secretValues) {
        if (-not [string]::IsNullOrEmpty($secret)) {
            $safe = $safe.Replace($secret, '[REDACTED]')
        }
    }
    return $safe
}

function Write-Pass {
    param([Parameter(Mandatory)][string] $Message)
    Write-Host "[PASS] $Message" -ForegroundColor Green
}

function Write-Info {
    param([Parameter(Mandatory)][string] $Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Resolve-NativeCommand {
    param([Parameter(Mandatory)][string[]] $Names)
    foreach ($name in $Names) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($null -ne $command) { return $command.Source }
    }
    throw "No se encontró una herramienta requerida: $($Names -join ', ')."
}

function Invoke-Native {
    param(
        [Parameter(Mandatory)][string] $FilePath,
        [Parameter(Mandatory)][string[]] $Arguments,
        [switch] $Capture,
        [switch] $AllowFailure
    )
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $FilePath @Arguments 2>&1 | ForEach-Object { [string]$_ })
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    $text = ($output -join [Environment]::NewLine).Trim()
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        $tail = ($output | Select-Object -Last 80) -join [Environment]::NewLine
        throw "$(Split-Path $FilePath -Leaf) falló con exit code ${exitCode}: $(ConvertTo-SafeText $tail)"
    }
    if ($Capture) {
        return [pscustomobject]@{ ExitCode = $exitCode; Text = $text }
    }
    foreach ($line in $output) { Write-Host (ConvertTo-SafeText $line) }
    return $exitCode
}

function Set-PrivateAcl {
    param([Parameter(Mandatory)][string] $Path, [Parameter(Mandatory)][bool] $Directory)
    if (-not (Test-Path -LiteralPath $Path)) { throw 'Falta un recurso privado esperado.' }
    if (-not $IsWindows) { throw 'La publicación operativa exige Windows PowerShell 7.' }
    $item = if ($Directory) { [IO.DirectoryInfo]::new($Path) } else { [IO.FileInfo]::new($Path) }
    $sections = [Security.AccessControl.AccessControlSections]::Access
    $acl = [IO.FileSystemAclExtensions]::GetAccessControl($item, $sections)
    $rules = @($acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]))
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($rule in $rules) { [void]$acl.RemoveAccessRuleAll($rule) }
    $owner = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $rights = [Security.AccessControl.FileSystemRights]::FullControl
    if ($Directory) {
        $inheritance = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
        $propagation = [Security.AccessControl.PropagationFlags]::None
        $accessRule = [Security.AccessControl.FileSystemAccessRule]::new(
            $owner, $rights, $inheritance, $propagation,
            [Security.AccessControl.AccessControlType]::Allow)
    }
    else {
        $accessRule = [Security.AccessControl.FileSystemAccessRule]::new(
            $owner, $rights, [Security.AccessControl.AccessControlType]::Allow)
    }
    $acl.AddAccessRule($accessRule)
    [IO.FileSystemAclExtensions]::SetAccessControl($item, $acl)
}

function Assert-PrivateAcl {
    param([Parameter(Mandatory)][string] $Path, [Parameter(Mandatory)][bool] $Directory)
    if (-not (Test-Path -LiteralPath $Path)) { throw 'Falta un recurso privado esperado.' }
    $item = if ($Directory) { [IO.DirectoryInfo]::new($Path) } else { [IO.FileInfo]::new($Path) }
    $sections = [Security.AccessControl.AccessControlSections]::Access
    $acl = [IO.FileSystemAclExtensions]::GetAccessControl($item, $sections)
    $current = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $allows = @($acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]) |
        Where-Object { $_.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow })
    if (-not $acl.AreAccessRulesProtected -or @($allows | Where-Object {
            $_.IdentityReference.Value -cne $current
        }).Count -ne 0) {
        throw "ACL privada inválida en $(Split-Path $Path -Leaf)."
    }
}

function Initialize-PublicStateRoot {
    if (-not (Test-Path -LiteralPath $publicStateRoot)) {
        New-Item -ItemType Directory -Path $publicStateRoot | Out-Null
    }
    Set-PrivateAcl -Path $publicStateRoot -Directory $true
    if (-not (Test-Path -LiteralPath $tunnelLogRoot)) {
        New-Item -ItemType Directory -Path $tunnelLogRoot | Out-Null
    }
    Set-PrivateAcl -Path $tunnelLogRoot -Directory $true
}

function Write-PrivateJson {
    param([Parameter(Mandatory)][string] $Path, [Parameter(Mandatory)][object] $Value)
    [IO.File]::WriteAllText(
        $Path,
        (($Value | ConvertTo-Json -Depth 8) + "`n"),
        [Text.UTF8Encoding]::new($false)
    )
    Set-PrivateAcl -Path $Path -Directory $false
}

function Normalize-PagesOrigin {
    param([Parameter(Mandatory)][string] $Origin)
    try { $uri = [Uri]::new($Origin.Trim(), [UriKind]::Absolute) }
    catch { throw 'PagesOrigin no es un origen HTTPS válido.' }
    if ($uri.Scheme -cne 'https' -or -not [string]::IsNullOrEmpty($uri.UserInfo) -or
        -not [string]::IsNullOrEmpty($uri.Query) -or -not [string]::IsNullOrEmpty($uri.Fragment) -or
        $uri.AbsolutePath -cne '/') {
        throw 'PagesOrigin debe ser un origen HTTPS sin path, query, fragment ni credenciales.'
    }
    return $uri.GetLeftPart([UriPartial]::Authority)
}

function Assert-StaticContract {
    if (-not $IsWindows -or $PSVersionTable.PSVersion.Major -lt 7) {
        throw 'Este launcher exige Windows PowerShell 7.'
    }
    if ($PagesProject -cne $expectedPagesProject) {
        throw "El proyecto Pages permitido es $expectedPagesProject."
    }
    $normalized = Normalize-PagesOrigin -Origin $PagesOrigin
    if ($normalized -cne $expectedPagesOrigin) {
        throw "El origin Pages permitido es $expectedPagesOrigin."
    }
    if ($BackendPort -ne 18080 -or $backendOrigin -cne 'http://127.0.0.1:18080') {
        throw 'El backend público debe permanecer exclusivamente en 127.0.0.1:18080.'
    }
    $rootWithSeparator = $repoRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    foreach ($statePath in @($demoStateRoot, $publicStateRoot)) {
        if ($statePath.StartsWith($rootWithSeparator, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'El estado privado no puede almacenarse dentro del repositorio.'
        }
    }
    foreach ($required in @($repoRoot, $frontendRoot, $launcherPath)) {
        if (-not (Test-Path -LiteralPath $required)) { throw "Falta $(Split-Path $required -Leaf)." }
    }
}

function Assert-GitContract {
    $git = Resolve-NativeCommand -Names @('git.exe', 'git')
    $top = (Invoke-Native -FilePath $git -Arguments @(
        '-C', $repoRoot, 'rev-parse', '--show-toplevel') -Capture).Text
    $actual = [IO.Path]::GetFullPath($top).TrimEnd('\', '/')
    if ($actual -cne $repoRoot.TrimEnd('\', '/')) { throw 'El repositorio resuelto no coincide con RepoPath.' }
    $branch = (Invoke-Native -FilePath $git -Arguments @(
        '-C', $repoRoot, 'branch', '--show-current') -Capture).Text
    if ($branch -cne 'main') { throw "La rama actual debe ser main; actual=$branch." }
    [void](Invoke-Native -FilePath $git -Arguments @(
        '-C', $repoRoot, 'fetch', 'origin', 'main', '--prune') -Capture)
    $head = (Invoke-Native -FilePath $git -Arguments @(
        '-C', $repoRoot, 'rev-parse', 'HEAD') -Capture).Text
    $originMain = (Invoke-Native -FilePath $git -Arguments @(
        '-C', $repoRoot, 'rev-parse', 'origin/main') -Capture).Text
    if ($head -cne $originMain) { throw 'main local no coincide con origin/main.' }
    [void](Invoke-Native -FilePath $git -Arguments @(
        '-C', $repoRoot, 'diff', '--check') -Capture)
    $status = (Invoke-Native -FilePath $git -Arguments @(
        '-C', $repoRoot, 'status', '--porcelain=v1') -Capture).Text
    $script:gitDirty = -not [string]::IsNullOrWhiteSpace($status)
    Write-Pass 'Git main coincide con origin/main y git diff --check pasó; el worktree actual se conserva.'
    return $head
}

function Read-EnvironmentValues {
    if (-not (Test-Path -LiteralPath $demoEnvironment -PathType Leaf)) {
        throw 'Falta la configuración privada de la demo multitenant.'
    }
    $values = @{}
    foreach ($line in [IO.File]::ReadAllLines($demoEnvironment)) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { continue }
        $separator = $line.IndexOf('=')
        if ($separator -lt 1) { throw 'La configuración privada contiene una línea inválida.' }
        $values[$line.Substring(0, $separator)] = $line.Substring($separator + 1)
    }
    return $values
}

function Register-PrivateSecrets {
    param([Parameter(Mandatory)][object] $Manifest)
    foreach ($value in @(
        $Manifest.platform.password,
        $Manifest.platform.totpSecret,
        $Manifest.alpha.password,
        $Manifest.beta.password,
        $Manifest.publicDemo.password,
        $Manifest.publicDemo.proxyToken
    )) { Add-Secret ([string]$value) }
    foreach ($actorPassword in @($Manifest.actors.PSObject.Properties | ForEach-Object { $_.Value })) {
        Add-Secret ([string]$actorPassword)
    }
    $environment = Read-EnvironmentValues
    foreach ($entry in $environment.GetEnumerator()) {
        if ([string]$entry.Key -match '(?i)(PASSWORD|SECRET|TOKEN)$') { Add-Secret ([string]$entry.Value) }
    }
    $recoveryPath = Join-Path $demoStateRoot 'platform-recovery-codes.txt'
    if (Test-Path -LiteralPath $recoveryPath -PathType Leaf) {
        foreach ($line in [IO.File]::ReadAllLines($recoveryPath)) { Add-Secret $line.Trim() }
    }
}

function Read-PublicDemoManifest {
    if (-not (Test-Path -LiteralPath $credentialManifest -PathType Leaf)) {
        throw 'Falta el manifiesto privado de la demo multitenant.'
    }
    Assert-PrivateAcl -Path $demoStateRoot -Directory $true
    Assert-PrivateAcl -Path $credentialManifest -Directory $false
    Assert-PrivateAcl -Path $demoEnvironment -Directory $false
    try { $manifest = Get-Content -LiteralPath $credentialManifest -Raw | ConvertFrom-Json -Depth 10 }
    catch { throw 'El manifiesto privado no contiene JSON válido.' }
    if ($null -eq $manifest.PSObject.Properties['publicDemo']) {
        throw 'La demo local todavía no posee configuración publicDemo.'
    }
    Register-PrivateSecrets -Manifest $manifest
    $public = $manifest.publicDemo
    if ([string]$public.username -cne $publicUsername -or
        [string]$public.pagesOrigin -cne $pagesOriginNormalized -or
        [string]::IsNullOrWhiteSpace([string]$public.password) -or
        [Text.Encoding]::UTF8.GetByteCount([string]$public.password) -lt 12 -or
        [Text.Encoding]::UTF8.GetByteCount([string]$public.proxyToken) -lt 32) {
        throw 'La identidad o los secretos promocionales privados no cumplen el contrato.'
    }
    if ([string]$manifest.alpha.name -cne 'Escuela Danza Marcos Paz' -or
        [string]$manifest.beta.name -cne 'Escuela Beta Demo') {
        throw 'Los tenants persistidos no coinciden con Alpha y Beta esperados.'
    }
    $alphaId = [Guid]::Empty
    $betaId = [Guid]::Empty
    if (-not [Guid]::TryParse([string]$manifest.alpha.id, [ref]$alphaId) -or
        -not [Guid]::TryParse([string]$manifest.beta.id, [ref]$betaId) -or $alphaId -eq $betaId) {
        throw 'Los IDs privados de Alpha y Beta son inválidos.'
    }
    return $manifest
}

function Assert-SecretsOutsideGit {
    $git = Resolve-NativeCommand -Names @('git.exe', 'git')
    $listed = (Invoke-Native -FilePath $git -Arguments @(
        '-C', $repoRoot, 'ls-files', '--cached', '--others', '--exclude-standard') -Capture).Text
    $rootPrefix = $repoRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    foreach ($relative in @($listed -split '[\r\n]+' | Where-Object { $_ })) {
        $candidate = [IO.Path]::GetFullPath((Join-Path $repoRoot $relative))
        if (-not $candidate.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase) -or
            -not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        $item = Get-Item -LiteralPath $candidate
        if ($item.Length -gt 10MB) { continue }
        try { $content = [IO.File]::ReadAllText($candidate) }
        catch { continue }
        foreach ($secret in $script:secretValues) {
            if (-not [string]::IsNullOrEmpty($secret) -and
                $content.Contains($secret, [StringComparison]::Ordinal)) {
                throw "Se detectó material secreto conocido en un archivo del worktree: $relative."
            }
        }
    }
    $staged = (Invoke-Native -FilePath $git -Arguments @(
        '-C', $repoRoot, 'diff', '--cached', '--name-only', '--diff-filter=ACMR') -Capture).Text
    foreach ($relative in @($staged -split '[\r\n]+' | Where-Object { $_ })) {
        $indexed = Invoke-Native -FilePath $git -Arguments @(
            '-C', $repoRoot, 'show', (':' + $relative)) -Capture -AllowFailure
        if ($indexed.ExitCode -ne 0 -or $indexed.Text.Length -gt 10MB) { continue }
        foreach ($secret in $script:secretValues) {
            if (-not [string]::IsNullOrEmpty($secret) -and
                $indexed.Text.Contains($secret, [StringComparison]::Ordinal)) {
                throw "Se detectó material secreto conocido en el índice de Git: $relative."
            }
        }
    }
    Write-Pass 'Los secretos conocidos permanecen fuera de Git.'
}

function Invoke-LocalDemoAction {
    param(
        [Parameter(Mandatory)][ValidateSet('Start', 'Status', 'Stop')][string] $LocalAction,
        [switch] $Rotate,
        [switch] $RequirePass
    )
    $pwsh = Resolve-NativeCommand -Names @('pwsh.exe', 'pwsh')
    $arguments = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $launcherPath,
        '-Action', $LocalAction)
    if ($LocalAction -eq 'Start') {
        $arguments += @('-PublicOrigin', $pagesOriginNormalized)
        if ($Rotate) { $arguments += '-RotatePublicCredential' }
    }
    $output = [Collections.Generic.List[string]]::new()
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $pwsh @arguments 2>&1 | ForEach-Object {
            $line = [string]$_
            $output.Add($line)
            Write-Host (ConvertTo-SafeText $line)
        }
        $exitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousPreference }
    if ($exitCode -ne 0) {
        throw "La acción local $LocalAction falló con exit code $exitCode."
    }
    if ($RequirePass -and
        (-not $output.Contains('STATUS: PASS') -or $output.Contains('STATUS: FAIL'))) {
        throw "La acción local $LocalAction no terminó con STATUS: PASS."
    }
}

function Assert-LocalBindings {
    foreach ($contract in @(
        [pscustomobject]@{ Port = $BackendPort; Name = 'backend' },
        [pscustomobject]@{ Port = 15432; Name = 'PostgreSQL' }
    )) {
        $listeners = @(Get-NetTCPConnection -State Listen -LocalPort $contract.Port -ErrorAction SilentlyContinue)
        if ($listeners.Count -eq 0 -or @($listeners | Where-Object {
                $_.LocalAddress -cne '127.0.0.1'
            }).Count -ne 0) {
            throw "$($contract.Name) no permanece enlazado exclusivamente a 127.0.0.1:$($contract.Port)."
        }
    }
    Write-Pass 'Backend y PostgreSQL permanecen en loopback; el túnel sólo apunta al backend.'
}

function Read-DeploymentState {
    param([Parameter(Mandatory)][string] $Path, [switch] $AllowMissing)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        if ($AllowMissing) { return $null }
        throw 'No existe estado privado del Quick Tunnel.'
    }
    try { $state = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 8 -DateKind String }
    catch { throw 'El estado privado del Quick Tunnel no contiene JSON válido.' }
    if ($null -ne $state.PSObject.Properties['Origin']) { Add-Secret ([string]$state.Origin) }
    return $state
}

function Get-OwnedTunnelProcess {
    param(
        [Parameter(Mandatory)][object] $State,
        [Parameter(Mandatory)][string] $CloudflaredPath
    )
    $trackedId = 0
    if (-not [int]::TryParse([string]$State.ProcessId, [ref]$trackedId) -or $trackedId -le 0) {
        return $null
    }
    $process = Get-Process -Id $trackedId -ErrorAction SilentlyContinue
    if ($null -eq $process -or $process.ProcessName -notlike 'cloudflared*') { return $null }
    try { $cim = Get-CimInstance Win32_Process -Filter "ProcessId = $trackedId" }
    catch { return $null }
    if ($null -eq $cim) { return $null }
    $commandLine = [string]$cim.CommandLine
    $executable = [string]$cim.ExecutablePath
    $expectedExecutable = [IO.Path]::GetFullPath($CloudflaredPath)
    if ([string]::IsNullOrWhiteSpace($executable) -or
        [IO.Path]::GetFullPath($executable) -cne $expectedExecutable -or
        $commandLine -notmatch '(?i)(?:^|\s)tunnel(?:\s|$)' -or
        -not $commandLine.Contains($backendOrigin, [StringComparison]::OrdinalIgnoreCase)) {
        return $null
    }
    if ($null -ne $State.PSObject.Properties['ProcessStartedAt'] -and
        -not [string]::IsNullOrWhiteSpace([string]$State.ProcessStartedAt)) {
        try {
            $expectedStart = [DateTimeOffset]::Parse([string]$State.ProcessStartedAt).UtcDateTime
            if ([Math]::Abs(($process.StartTime.ToUniversalTime() - $expectedStart).TotalSeconds) -gt 2) {
                return $null
            }
        }
        catch { return $null }
    }
    return $process
}

function Stop-TrackedQuickTunnels {
    $cloudflared = Resolve-NativeCommand -Names @('cloudflared.exe', 'cloudflared')
    foreach ($candidate in @($publicStatePath) + $legacyStatePaths) {
        $state = Read-DeploymentState -Path $candidate -AllowMissing
        if ($null -eq $state) { continue }
        $process = Get-OwnedTunnelProcess -State $state -CloudflaredPath $cloudflared
        if ($null -eq $process) {
            Write-Host '[WARN] Un estado previo no identifica con seguridad un proceso cloudflared propio; no se detuvo.' -ForegroundColor Yellow
            continue
        }
        Stop-Process -Id $process.Id -ErrorAction Stop
        try { $process.WaitForExit(15000) } catch { }
        Remove-Item -LiteralPath $candidate -Force -ErrorAction SilentlyContinue
        Write-Pass 'Quick Tunnel anterior detenido sin afectar otros procesos.'
    }
}

function Write-TunnelState {
    param(
        [Parameter(Mandatory)][string] $Origin,
        [Parameter(Mandatory)][Diagnostics.Process] $Process,
        [Parameter(Mandatory)][string] $ExecutablePath,
        [AllowNull()][string] $Commit,
        [AllowNull()][string] $PublishedAt
    )
    Add-Secret $Origin
    Write-PrivateJson -Path $publicStatePath -Value ([ordered]@{
        Origin = $Origin
        ProcessId = $Process.Id
        ProcessStartedAt = $Process.StartTime.ToUniversalTime().ToString('o')
        ExecutablePath = [IO.Path]::GetFullPath($ExecutablePath)
        BackendOrigin = $backendOrigin
        PagesProject = $PagesProject
        PagesOrigin = $pagesOriginNormalized
        Commit = $Commit
        PublishedAt = $PublishedAt
    })
}

function Get-TunnelLogText {
    param([Parameter(Mandatory)][string] $Stdout, [Parameter(Mandatory)][string] $Stderr)
    $parts = [Collections.Generic.List[string]]::new()
    foreach ($path in @($Stdout, $Stderr)) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $parts.Add((Get-Content -LiteralPath $path -Raw -ErrorAction SilentlyContinue))
        }
    }
    return ($parts -join "`n")
}

function Send-StandaloneRequest {
    param(
        [Parameter(Mandatory)][string] $Uri,
        [ValidateSet('GET', 'POST', 'OPTIONS')][string] $Method = 'GET',
        [hashtable] $Headers = @{},
        [AllowNull()][string] $Body = $null,
        [int] $TimeoutSeconds = 30
    )
    $handler = [Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $false
    $client = [Net.Http.HttpClient]::new($handler, $true)
    $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
    try { return Send-SessionRequest -Client $client -Method $Method -Uri $Uri -Headers $Headers -Body $Body }
    finally { $client.Dispose() }
}

function Get-ResponseHeaders {
    param([Parameter(Mandatory)][Net.Http.HttpResponseMessage] $Response)
    $headers = @{}
    foreach ($header in $Response.Headers) { $headers[$header.Key.ToLowerInvariant()] = @($header.Value) }
    foreach ($header in $Response.Content.Headers) { $headers[$header.Key.ToLowerInvariant()] = @($header.Value) }
    return $headers
}

function Send-SessionRequest {
    param(
        [Parameter(Mandatory)][Net.Http.HttpClient] $Client,
        [Parameter(Mandatory)][ValidateSet('GET', 'POST', 'OPTIONS')][string] $Method,
        [Parameter(Mandatory)][string] $Uri,
        [hashtable] $Headers = @{},
        [AllowNull()][string] $Body = $null
    )
    $request = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::new($Method), $Uri)
    try {
        [void]$request.Headers.TryAddWithoutValidation('User-Agent', 'Gestudio-Public-Demo-Validator/1.0')
        foreach ($entry in $Headers.GetEnumerator()) {
            [void]$request.Headers.TryAddWithoutValidation([string]$entry.Key, [string]$entry.Value)
        }
        if ($null -ne $Body) {
            $request.Content = [Net.Http.StringContent]::new(
                $Body, [Text.Encoding]::UTF8, 'application/json')
        }
        $response = $Client.SendAsync($request).GetAwaiter().GetResult()
        try {
            $content = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            return [pscustomobject]@{
                Status = [int]$response.StatusCode
                Body = $content
                ContentType = if ($null -eq $response.Content.Headers.ContentType) {
                    ''
                } else { [string]$response.Content.Headers.ContentType.MediaType }
                Headers = Get-ResponseHeaders -Response $response
            }
        }
        finally { $response.Dispose() }
    }
    finally { $request.Dispose() }
}

function Get-HeaderValues {
    param([Parameter(Mandatory)][object] $Response, [Parameter(Mandatory)][string] $Name)
    $key = $Name.ToLowerInvariant()
    if (-not $Response.Headers.ContainsKey($key)) { return @() }
    return @($Response.Headers[$key])
}

function Assert-HttpStatus {
    param([Parameter(Mandatory)][object] $Response, [Parameter(Mandatory)][int[]] $Expected,
          [Parameter(Mandatory)][string] $Label)
    if ([int]$Response.Status -notin $Expected) {
        throw "$Label devolvió HTTP $([int]$Response.Status)."
    }
}

function Assert-NoStore {
    param([Parameter(Mandatory)][object] $Response, [Parameter(Mandatory)][string] $Label)
    $cacheControl = (Get-HeaderValues -Response $Response -Name 'Cache-Control') -join ','
    if ($cacheControl -notmatch '(?i)(?:^|,)\s*no-store(?:,|$)') {
        throw "$Label no devolvió Cache-Control: no-store."
    }
}

function Wait-DnsResolution {
    param([Parameter(Mandatory)][Uri] $Uri, [int] $TimeoutSeconds = 300)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            if (@([Net.Dns]::GetHostAddresses($Uri.DnsSafeHost)).Count -gt 0) { return }
        }
        catch { }
        Start-Sleep -Seconds 2
    }
    throw 'El Quick Tunnel no resolvió por DNS dentro del plazo.'
}

function Wait-TunnelHttp {
    param(
        [Parameter(Mandatory)][string] $Origin,
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][int] $Expected,
        [hashtable] $Headers = @{},
        [int] $TimeoutSeconds = 300
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $result = Send-StandaloneRequest -Uri "$Origin$Path" -Headers $Headers -TimeoutSeconds 15
            if ($result.Status -eq $Expected) { return }
        }
        catch { }
        Start-Sleep -Seconds 2
    }
    throw "El control negativo del Quick Tunnel no terminó en HTTP $Expected."
}

function Start-QuickTunnel {
    param([Parameter(Mandatory)][string] $ProxyToken)
    $cloudflared = Resolve-NativeCommand -Names @('cloudflared.exe', 'cloudflared')
    $userProfile = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
    foreach ($config in @(
        (Join-Path $userProfile '.cloudflared\config.yml'),
        (Join-Path $userProfile '.cloudflared\config.yaml')
    )) {
        if (Test-Path -LiteralPath $config -PathType Leaf) {
            throw 'Quick Tunnel no puede iniciarse mientras exista una configuración cloudflared por defecto.'
        }
    }
    Initialize-PublicStateRoot
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $stdout = Join-Path $tunnelLogRoot "cloudflared-$stamp.stdout.log"
    $stderr = Join-Path $tunnelLogRoot "cloudflared-$stamp.stderr.log"
    $process = Start-Process -FilePath $cloudflared -ArgumentList @(
        'tunnel', '--url', $backendOrigin, '--protocol', 'http2', '--no-autoupdate'
    ) -RedirectStandardOutput $stdout -RedirectStandardError $stderr -WindowStyle Hidden -PassThru
    $script:newTunnelProcess = $process
    $origin = $null
    $deadline = (Get-Date).AddSeconds(120)
    while ((Get-Date) -lt $deadline) {
        if ($process.HasExited) { throw 'cloudflared terminó antes de publicar el Quick Tunnel.' }
        $logs = Get-TunnelLogText -Stdout $stdout -Stderr $stderr
        $match = [regex]::Match($logs, 'https://[a-z0-9-]+[.]trycloudflare[.]com',
            [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($match.Success) { $origin = $match.Value.TrimEnd('/'); break }
        Start-Sleep -Seconds 2
    }
    if ([string]::IsNullOrWhiteSpace($origin)) { throw 'cloudflared no informó un hostname Quick Tunnel.' }
    Add-Secret $origin
    $registeredDeadline = (Get-Date).AddSeconds(180)
    $registered = $false
    while ((Get-Date) -lt $registeredDeadline) {
        if ($process.HasExited) { throw 'cloudflared terminó antes de registrar la conexión.' }
        if ((Get-TunnelLogText -Stdout $stdout -Stderr $stderr) -match '(?i)Registered tunnel connection') {
            $registered = $true
            break
        }
        Start-Sleep -Seconds 2
    }
    if (-not $registered) { throw 'cloudflared no registró la conexión dentro del plazo.' }
    Wait-DnsResolution -Uri ([Uri]$origin)
    Write-TunnelState -Origin $origin -Process $process -ExecutablePath $cloudflared -Commit $null -PublishedAt $null
    Wait-TunnelHttp -Origin $origin -Path '/api/usuarios/perfil' -Expected 404
    Wait-TunnelHttp -Origin $origin -Path '/actuator/health/readiness' -Expected 404
    Wait-TunnelHttp -Origin $origin -Path '/api/usuarios/perfil' -Expected 401 -Headers @{
        'X-Gestudio-Proxy-Token' = $ProxyToken
        Origin = $pagesOriginNormalized
    }
    Write-Pass 'Quick Tunnel registrado; acceso directo sin proxy token queda oculto con 404.'
    return [pscustomobject]@{
        Origin = $origin
        Process = $process
        ExecutablePath = $cloudflared
    }
}

function Assert-TrackedTunnel {
    $state = Read-DeploymentState -Path $publicStatePath
    if ([string]$state.BackendOrigin -cne $backendOrigin -or
        [string]$state.PagesProject -cne $PagesProject -or
        [string]$state.PagesOrigin -cne $pagesOriginNormalized -or
        [string]$state.Origin -notmatch '^https://[a-z0-9-]+[.]trycloudflare[.]com$') {
        throw 'El estado registrado no corresponde al despliegue público esperado.'
    }
    $cloudflared = Resolve-NativeCommand -Names @('cloudflared.exe', 'cloudflared')
    $process = Get-OwnedTunnelProcess -State $state -CloudflaredPath $cloudflared
    if ($null -eq $process) { throw 'El proceso cloudflared registrado no está activo o no conserva ownership verificable.' }
    return [pscustomobject]@{ State = $state; Process = $process; ExecutablePath = $cloudflared }
}

function Publish-Pages {
    param(
        [Parameter(Mandatory)][object] $Tunnel,
        [Parameter(Mandatory)][string] $ProxyToken,
        [Parameter(Mandatory)][string] $Commit
    )
    $npm = Resolve-NativeCommand -Names @('npm.cmd', 'npm')
    $npx = Resolve-NativeCommand -Names @('npx.cmd', 'npx')
    Initialize-PublicStateRoot
    $script:temporarySecretFile = Join-Path $publicStateRoot "pages-secrets-$([Guid]::NewGuid().ToString('N')).json"
    Write-PrivateJson -Path $script:temporarySecretFile -Value ([ordered]@{
        GESTUDIO_BACKEND_ORIGIN = [string]$Tunnel.Origin
        GESTUDIO_PROXY_TOKEN = $ProxyToken
    })
    $previousApi = [Environment]::GetEnvironmentVariable('VITE_API_BASE_URL', 'Process')
    $previousZone = [Environment]::GetEnvironmentVariable('VITE_APP_TIME_ZONE', 'Process')
    Push-Location $frontendRoot
    try {
        [void](Invoke-Native -FilePath $npx -Arguments @('--yes', 'wrangler', 'whoami') -Capture)
        [void](Invoke-Native -FilePath $npx -Arguments @(
            '--yes', 'wrangler', 'pages', 'secret', 'bulk', $script:temporarySecretFile,
            '--project-name', $PagesProject) -Capture)
        Write-Pass 'Bindings GESTUDIO_BACKEND_ORIGIN y GESTUDIO_PROXY_TOKEN actualizados en Pages.'
        [Environment]::SetEnvironmentVariable('VITE_API_BASE_URL', "$pagesOriginNormalized/api", 'Process')
        [Environment]::SetEnvironmentVariable('VITE_APP_TIME_ZONE', 'America/Argentina/Buenos_Aires', 'Process')
        [void](Invoke-Native -FilePath $npm -Arguments @('ci') -Capture)
        [void](Invoke-Native -FilePath $npm -Arguments @('run', 'lint') -Capture)
        [void](Invoke-Native -FilePath $npm -Arguments @('run', 'build') -Capture)
        Write-Pass 'Frontend construido con la API pages.dev exacta.'
        [void](Invoke-Native -FilePath $npx -Arguments @(
            '--yes', 'wrangler', 'pages', 'deploy', 'dist',
            '--project-name', $PagesProject,
            '--branch', 'main',
            '--commit-hash', $Commit,
            '--commit-message', 'public-demo: publish persistent multitenant backend',
            '--commit-dirty=true') -Capture)
        Write-Pass 'dist publicado mediante Wrangler en el proyecto Pages existente.'
    }
    finally {
        [Environment]::SetEnvironmentVariable('VITE_API_BASE_URL', $previousApi, 'Process')
        [Environment]::SetEnvironmentVariable('VITE_APP_TIME_ZONE', $previousZone, 'Process')
        Pop-Location
        if (-not [string]::IsNullOrWhiteSpace($script:temporarySecretFile) -and
            (Test-Path -LiteralPath $script:temporarySecretFile -PathType Leaf)) {
            Remove-Item -LiteralPath $script:temporarySecretFile -Force
        }
        $script:temporarySecretFile = $null
    }
}

function New-PublicHttpSession {
    $handler = [Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $false
    $handler.UseCookies = $true
    $handler.CookieContainer = [Net.CookieContainer]::new()
    $client = [Net.Http.HttpClient]::new($handler, $true)
    $client.Timeout = [TimeSpan]::FromSeconds(30)
    return [pscustomobject]@{ Client = $client; Handler = $handler }
}

function Wait-PagesAvailability {
    param([Parameter(Mandatory)][Net.Http.HttpClient] $Client, [int] $TimeoutSeconds = 360)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $nextMessage = Get-Date
    while ((Get-Date) -lt $deadline) {
        try {
            $root = Send-SessionRequest -Client $Client -Method GET -Uri "$pagesOriginNormalized/"
            $api = Send-SessionRequest -Client $Client -Method GET -Uri "$pagesOriginNormalized/api/usuarios/perfil"
            if ($root.Status -eq 200 -and $api.Status -eq 401 -and
                $api.ContentType -match '(?i)application/json') {
                Assert-NoStore -Response $api -Label 'API pública anónima'
                return $root
            }
        }
        catch { }
        if ((Get-Date) -ge $nextMessage) {
            Write-Info 'Esperando disponibilidad coordinada de la SPA y la API en pages.dev.'
            $nextMessage = (Get-Date).AddSeconds(10)
        }
        Start-Sleep -Seconds 2
    }
    throw 'Pages no alcanzó SPA 200 y API 401 JSON dentro del plazo.'
}

function ConvertFrom-PublicJson {
    param([Parameter(Mandatory)][object] $Response, [Parameter(Mandatory)][string] $Label)
    if ($Response.ContentType -notmatch '(?i)application/json') { throw "$Label no devolvió JSON." }
    try { return $Response.Body | ConvertFrom-Json -Depth 30 }
    catch { throw "$Label devolvió JSON inválido." }
}

function Test-ExactStringSet {
    param([AllowNull()][object[]] $Actual, [Parameter(Mandatory)][string[]] $Expected)
    $actualSet = @($Actual | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    $expectedSet = @($Expected | Sort-Object -Unique)
    return $actualSet.Count -eq $expectedSet.Count -and
        @(Compare-Object -CaseSensitive $actualSet $expectedSet).Count -eq 0
}

function Assert-PublicProfile {
    param([Parameter(Mandatory)][object] $Profile, [Parameter(Mandatory)][object] $Manifest)
    $available = @($Profile.tenantsDisponibles)
    if ([string]$Profile.nombreUsuario -cne $publicUsername -or $Profile.activo -ne $true -or
        -not (Test-ExactStringSet -Actual @($Profile.roles) -Expected @($publicRoleCode)) -or
        -not (Test-ExactStringSet -Actual @($Profile.permisos) -Expected $publicPermissions) -or
        $null -eq $Profile.tenantActivo -or
        [string]$Profile.tenantActivo.id -cne [string]$Manifest.alpha.id -or
        [string]$Profile.tenantActivo.codigo -cne [string]$Manifest.alpha.code -or
        [string]$Profile.tenantActivo.nombre -cne [string]$Manifest.alpha.name -or
        [string]$Profile.tenantActivo.estado -cne 'ACTIVE' -or
        $available.Count -ne 1 -or
        [string]$available[0].id -cne [string]$Manifest.alpha.id -or
        [string]$available[0].nombre -cne [string]$Manifest.alpha.name) {
        throw 'El perfil promocional no pertenece exclusivamente a Alpha con DEMO_COMERCIAL exacto.'
    }
}

function Assert-RefreshCookie {
    param(
        [Parameter(Mandatory)][object] $Response,
        [AllowNull()][string] $PreviousValue,
        [switch] $RequireRotation
    )
    $cookieLine = @(Get-HeaderValues -Response $Response -Name 'Set-Cookie' | Where-Object {
            $_ -match '(?i)(?:^|;)\s*Path=/api/login(?:;|$)' -and $_ -match '(?i)(?:^|;)\s*HttpOnly(?:;|$)'
        } | Select-Object -First 1)
    if ($cookieLine.Count -ne 1) { throw 'No se recibió una única cookie de refresh identificable.' }
    $line = [string]$cookieLine[0]
    if ($line -notmatch '(?i)(?:^|;)\s*Secure(?:;|$)' -or
        $line -notmatch '(?i)(?:^|;)\s*HttpOnly(?:;|$)' -or
        $line -notmatch '(?i)(?:^|;)\s*SameSite=Strict(?:;|$)' -or
        $line -notmatch '(?i)(?:^|;)\s*Path=/api/login(?:;|$)' -or
        $line -match '(?i)(?:^|;)\s*Domain=') {
        throw 'La cookie de refresh no es Secure, HttpOnly, SameSite=Strict, host-only y Path=/api/login.'
    }
    $pair = ($line -split ';', 2)[0]
    $separator = $pair.IndexOf('=')
    if ($separator -lt 1) { throw 'La cookie de refresh es inválida.' }
    $value = $pair.Substring($separator + 1)
    if ([string]::IsNullOrWhiteSpace($value)) { throw 'La cookie de refresh no contiene valor.' }
    Add-Secret $value
    if ($RequireRotation -and $value -ceq $PreviousValue) { throw 'Refresh no rotó la cookie.' }
    return $value
}

function Assert-DeletedRefreshCookie {
    param([Parameter(Mandatory)][object] $Response)
    $cookieLine = @(Get-HeaderValues -Response $Response -Name 'Set-Cookie' | Where-Object {
            $_ -match '(?i)(?:^|;)\s*Path=/api/login(?:;|$)' -and $_ -match '(?i)(?:^|;)\s*HttpOnly(?:;|$)'
        } | Select-Object -First 1)
    if ($cookieLine.Count -ne 1) { throw 'Logout no devolvió la eliminación de la cookie de refresh.' }
    $line = [string]$cookieLine[0]
    $pair = ($line -split ';', 2)[0]
    $separator = $pair.IndexOf('=')
    if ($separator -lt 1 -or -not [string]::IsNullOrEmpty($pair.Substring($separator + 1)) -or
        $line -notmatch '(?i)(?:^|;)\s*Max-Age=0(?:;|$)' -or
        $line -notmatch '(?i)(?:^|;)\s*Secure(?:;|$)' -or
        $line -notmatch '(?i)(?:^|;)\s*HttpOnly(?:;|$)' -or
        $line -notmatch '(?i)(?:^|;)\s*SameSite=Strict(?:;|$)' -or
        $line -notmatch '(?i)(?:^|;)\s*Path=/api/login(?:;|$)' -or
        $line -match '(?i)(?:^|;)\s*Domain=') {
        throw 'Logout no eliminó la cookie con el contrato Secure, HttpOnly, Strict y host-only.'
    }
}

function Assert-ApiResponse {
    param([Parameter(Mandatory)][object] $Response, [Parameter(Mandatory)][int[]] $Expected,
          [Parameter(Mandatory)][string] $Label)
    Assert-HttpStatus -Response $Response -Expected $Expected -Label $Label
    Assert-NoStore -Response $Response -Label $Label
}

function Assert-PublicDeployment {
    param([Parameter(Mandatory)][object] $Manifest, [Parameter(Mandatory)][string] $TunnelOrigin)
    $session = New-PublicHttpSession
    $refreshSessionStarted = $false
    $logoutCompleted = $false
    try {
        $root = Wait-PagesAvailability -Client $session.Client
        if ($root.ContentType -notmatch '(?i)text/html' -or
            $root.Body -notmatch '(?i)<div\s+id=["'']root["'']') {
            throw 'La respuesta pública no contiene la SPA esperada.'
        }
        $assetMatch = [regex]::Match($root.Body, '/assets/[A-Za-z0-9._/-]+[.](?:js|css)')
        if (-not $assetMatch.Success) { throw 'La SPA pública no referencia un asset compilado.' }
        $asset = Send-SessionRequest -Client $session.Client -Method GET -Uri "$pagesOriginNormalized$($assetMatch.Value)"
        Assert-HttpStatus -Response $asset -Expected @(200) -Label 'Asset público'

        $anonymous = Send-SessionRequest -Client $session.Client -Method GET `
            -Uri "$pagesOriginNormalized/api/usuarios/perfil"
        Assert-ApiResponse -Response $anonymous -Expected @(401) -Label 'API pública anónima'
        [void](ConvertFrom-PublicJson -Response $anonymous -Label 'API pública anónima')

        $corsAllowed = Send-SessionRequest -Client $session.Client -Method OPTIONS `
            -Uri "$pagesOriginNormalized/api/login" -Headers @{
                Origin = $pagesOriginNormalized
                'Access-Control-Request-Method' = 'POST'
                'Access-Control-Request-Headers' = 'content-type'
            }
        Assert-ApiResponse -Response $corsAllowed -Expected @(200, 204) -Label 'CORS permitido'
        $allowedOrigin = (Get-HeaderValues -Response $corsAllowed -Name 'Access-Control-Allow-Origin') -join ','
        if ($allowedOrigin -cne $pagesOriginNormalized) { throw 'CORS no devolvió exclusivamente el origin Pages.' }

        $corsDenied = Send-SessionRequest -Client $session.Client -Method OPTIONS `
            -Uri "$pagesOriginNormalized/api/login" -Headers @{
                Origin = 'https://hostil.example'
                'Access-Control-Request-Method' = 'POST'
                'Access-Control-Request-Headers' = 'content-type'
            }
        Assert-ApiResponse -Response $corsDenied -Expected @(403) -Label 'CORS hostil'
        if (@(Get-HeaderValues -Response $corsDenied -Name 'Access-Control-Allow-Origin').Count -ne 0) {
            throw 'CORS hostil recibió Access-Control-Allow-Origin.'
        }

        $loginBody = [ordered]@{
            nombreUsuario = [string]$Manifest.publicDemo.username
            contrasena = [string]$Manifest.publicDemo.password
            tenantId = [string]$Manifest.alpha.id
        } | ConvertTo-Json -Compress
        $loginResponse = Send-SessionRequest -Client $session.Client -Method POST `
            -Uri "$pagesOriginNormalized/api/login" -Headers @{ Origin = $pagesOriginNormalized } -Body $loginBody
        Assert-ApiResponse -Response $loginResponse -Expected @(200) -Label 'Login promocional'
        $login = ConvertFrom-PublicJson -Response $loginResponse -Label 'Login promocional'
        $accessToken = [string]$login.accessToken
        if ([string]::IsNullOrWhiteSpace($accessToken)) { throw 'Login promocional no emitió access token.' }
        Add-Secret $accessToken
        $refreshValue = Assert-RefreshCookie -Response $loginResponse -PreviousValue $null
        $refreshSessionStarted = $true
        Assert-PublicProfile -Profile $login.usuario -Manifest $Manifest

        $authHeaders = @{ Authorization = "Bearer $accessToken"; Origin = $pagesOriginNormalized }
        $profileResponse = Send-SessionRequest -Client $session.Client -Method GET `
            -Uri "$pagesOriginNormalized/api/usuarios/perfil" -Headers $authHeaders
        Assert-ApiResponse -Response $profileResponse -Expected @(200) -Label 'Perfil promocional'
        Assert-PublicProfile -Profile (ConvertFrom-PublicJson -Response $profileResponse -Label 'Perfil promocional') `
            -Manifest $Manifest

        $studentsResponse = Send-SessionRequest -Client $session.Client -Method GET `
            -Uri "$pagesOriginNormalized/api/alumnos?page=0&size=200" -Headers $authHeaders
        Assert-ApiResponse -Response $studentsResponse -Expected @(200) -Label 'Listado Alpha'
        $students = ConvertFrom-PublicJson -Response $studentsResponse -Label 'Listado Alpha'
        if ([int64]$students.totalElements -lt 1 -or @($students.content).Count -lt 1 -or
            $studentsResponse.Body -notmatch [regex]::Escape('Alpha E2E d3a010ca1001') -or
            $studentsResponse.Body -match [regex]::Escape('Beta E2E d3a010ca1001') -or
            $studentsResponse.Body -match [regex]::Escape('beta.alumno@demo.local')) {
            throw 'El listado público no demuestra datos Alpha aislados de Beta.'
        }

        foreach ($restrictedPath in @('/api/usuarios', '/api/roles', '/api/platform/me')) {
            $restricted = Send-SessionRequest -Client $session.Client -Method GET `
                -Uri "$pagesOriginNormalized$restrictedPath" -Headers $authHeaders
            Assert-ApiResponse -Response $restricted -Expected @(403) -Label 'Área administrativa restringida'
        }

        $refreshResponse = Send-SessionRequest -Client $session.Client -Method POST `
            -Uri "$pagesOriginNormalized/api/login/refresh" -Headers @{ Origin = $pagesOriginNormalized }
        Assert-ApiResponse -Response $refreshResponse -Expected @(200) -Label 'Refresh promocional'
        $refresh = ConvertFrom-PublicJson -Response $refreshResponse -Label 'Refresh promocional'
        $refreshedAccessToken = [string]$refresh.accessToken
        if ([string]::IsNullOrWhiteSpace($refreshedAccessToken)) { throw 'Refresh no emitió access token.' }
        Add-Secret $refreshedAccessToken
        [void](Assert-RefreshCookie -Response $refreshResponse -PreviousValue $refreshValue -RequireRotation)
        Assert-PublicProfile -Profile $refresh.usuario -Manifest $Manifest

        $refreshedProfile = Send-SessionRequest -Client $session.Client -Method GET `
            -Uri "$pagesOriginNormalized/api/usuarios/perfil" -Headers @{
                Authorization = "Bearer $refreshedAccessToken"
                Origin = $pagesOriginNormalized
            }
        Assert-ApiResponse -Response $refreshedProfile -Expected @(200) -Label 'Perfil luego de refresh'

        $logout = Send-SessionRequest -Client $session.Client -Method POST `
            -Uri "$pagesOriginNormalized/api/login/logout" -Headers @{ Origin = $pagesOriginNormalized }
        Assert-ApiResponse -Response $logout -Expected @(204) -Label 'Logout promocional'
        Assert-DeletedRefreshCookie -Response $logout
        $logoutCompleted = $true
        $refreshAfterLogout = Send-SessionRequest -Client $session.Client -Method POST `
            -Uri "$pagesOriginNormalized/api/login/refresh" -Headers @{ Origin = $pagesOriginNormalized }
        Assert-ApiResponse -Response $refreshAfterLogout -Expected @(401) -Label 'Refresh posterior a logout'

        foreach ($actuatorPath in @('/actuator/health/readiness', '/actuator/prometheus')) {
            $actuator = Send-SessionRequest -Client $session.Client -Method GET `
                -Uri "$pagesOriginNormalized$actuatorPath"
            Assert-HttpStatus -Response $actuator -Expected @(200, 404) -Label 'Actuator por Pages'
            if ($actuator.Body -match '(?i)"status"\s*:\s*"UP"|#\s+HELP\s+') {
                throw 'Pages expuso contenido de actuator o Prometheus.'
            }
        }

        Wait-TunnelHttp -Origin $TunnelOrigin -Path '/api/usuarios/perfil' -Expected 404 -TimeoutSeconds 120
        Wait-TunnelHttp -Origin $TunnelOrigin -Path '/actuator/health/readiness' -Expected 404 -TimeoutSeconds 120
        Write-Pass 'SPA, API, CORS, login, Alpha, refresh, logout, proxy y actuator pasaron vía pages.dev.'
    }
    finally {
        if ($refreshSessionStarted -and -not $logoutCompleted) {
            try {
                [void](Send-SessionRequest -Client $session.Client -Method POST `
                    -Uri "$pagesOriginNormalized/api/login/logout" -Headers @{ Origin = $pagesOriginNormalized })
            }
            catch { }
        }
        $session.Client.Dispose()
    }
}

function Invoke-StartPublication {
    $commit = Assert-GitContract
    [void](Resolve-NativeCommand -Names @('docker.exe', 'docker'))
    [void](Resolve-NativeCommand -Names @('cloudflared.exe', 'cloudflared'))
    [void](Resolve-NativeCommand -Names @('npm.cmd', 'npm'))
    [void](Resolve-NativeCommand -Names @('npx.cmd', 'npx'))
    $docker = Resolve-NativeCommand -Names @('docker.exe', 'docker')
    [void](Invoke-Native -FilePath $docker -Arguments @('version', '--format', '{{.Server.Version}}') -Capture)
    Write-Pass 'Docker Desktop local disponible.'

    Invoke-LocalDemoAction -LocalAction Start -Rotate:$RotatePublicCredential -RequirePass
    $manifest = Read-PublicDemoManifest
    Assert-SecretsOutsideGit
    Assert-LocalBindings

    Stop-TrackedQuickTunnels
    $tunnel = Start-QuickTunnel -ProxyToken ([string]$manifest.publicDemo.proxyToken)
    Publish-Pages -Tunnel $tunnel -ProxyToken ([string]$manifest.publicDemo.proxyToken) -Commit $commit
    Assert-PublicDeployment -Manifest $manifest -TunnelOrigin ([string]$tunnel.Origin)
    Assert-LocalBindings
    [void](Invoke-Native -FilePath (Resolve-NativeCommand -Names @('git.exe', 'git')) `
        -Arguments @('-C', $repoRoot, 'diff', '--check') -Capture)
    Assert-SecretsOutsideGit
    Write-TunnelState -Origin ([string]$tunnel.Origin) -Process $tunnel.Process `
        -ExecutablePath ([string]$tunnel.ExecutablePath) -Commit $commit `
        -PublishedAt ([DateTimeOffset]::UtcNow.ToString('o'))

    Write-Host ''
    Write-Host 'DEMO PUBLICA DISPONIBLE'
    Write-Host "$pagesOriginNormalized/"
    Write-Host 'Mantener activos: PC host, Internet, Docker Desktop, demo local y cloudflared.'
    Write-Host 'STATUS: .\DESPLEGAR-DEMO-REMOTA.cmd -Action Status'
    Write-Host 'STOP:   .\DESPLEGAR-DEMO-REMOTA.cmd -Action Stop'
    Write-Host "Credencial promocional privada: $credentialManifest"
}

function Invoke-PublicStatus {
    [void](Assert-GitContract)
    Invoke-LocalDemoAction -LocalAction Status -RequirePass
    $manifest = Read-PublicDemoManifest
    Assert-SecretsOutsideGit
    Assert-LocalBindings
    $tracked = Assert-TrackedTunnel
    Assert-PublicDeployment -Manifest $manifest -TunnelOrigin ([string]$tracked.State.Origin)
    Write-Host 'PUBLIC_DEMO_READINESS=PASS'
    Write-Host "$pagesOriginNormalized/"
}

function Invoke-PublicStop {
    Stop-TrackedQuickTunnels
    Invoke-LocalDemoAction -LocalAction Stop
    Write-Host 'Demo pública detenida. Volúmenes, datos, credenciales y auditoría fueron conservados.'
}

try {
    Assert-StaticContract
    if ($RotatePublicCredential -and $Action -ne 'Start') {
        throw '-RotatePublicCredential sólo es válido con -Action Start.'
    }
    switch ($Action) {
        'Start' { Invoke-StartPublication }
        'Status' { Invoke-PublicStatus }
        'Stop' { Invoke-PublicStop }
    }
}
catch {
    $message = ConvertTo-SafeText $_.Exception.Message
    Write-Host "[FAIL] $message" -ForegroundColor Red
    if ($null -ne $script:newTunnelProcess) {
        try {
            if (-not $script:newTunnelProcess.HasExited) {
                Stop-Process -Id $script:newTunnelProcess.Id -ErrorAction Stop
            }
            Remove-Item -LiteralPath $publicStatePath -Force -ErrorAction SilentlyContinue
        }
        catch { }
    }
    exit 1
}
finally {
    if (-not [string]::IsNullOrWhiteSpace($script:temporarySecretFile) -and
        (Test-Path -LiteralPath $script:temporarySecretFile -PathType Leaf)) {
        Remove-Item -LiteralPath $script:temporarySecretFile -Force -ErrorAction SilentlyContinue
    }
    $script:secretValues.Clear()
}
