[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Start', 'Status', 'Stop', 'Reset')]
    [string] $Action,
    [switch] $ConfirmReset,
    [string] $PublicOrigin = '',
    [switch] $RotatePublicCredential
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$composeFile = Join-Path $repoRoot 'docker-compose.yml'
$runnerPath = Join-Path $PSScriptRoot 'e2e\run-control-plane.ps1'
$seedLauncher = Join-Path $PSScriptRoot 'demo-local.ps1'
$project = 'gestudio-demo-local'
$databasePort = 15432
$backendPort = 18080
$frontendPort = 18081
$backendImage = 'gestudio-backend:demo-local'
$frontendImage = 'gestudio-frontend:demo-local'
$localData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
if ([string]::IsNullOrWhiteSpace($localData)) { throw 'No se pudo resolver LOCALAPPDATA.' }
$stateRoot = [IO.Path]::GetFullPath((Join-Path $localData 'Gestudio\gestudio-demo-local'))
$envFile = Join-Path $stateRoot 'e2e.env'
$portsOverride = Join-Path $stateRoot 'ports.compose.yml'
$credentialManifest = Join-Path $stateRoot 'credentials.json'
$recoveryCodes = Join-Path $stateRoot 'platform-recovery-codes.txt'
$fixtureState = Join-Path $stateRoot 'fixture-state.json'
$secretValues = [Collections.Generic.List[string]]::new()
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

function Add-Secret {
    param([AllowNull()][string] $Value)
    if (-not [string]::IsNullOrEmpty($Value) -and -not $script:secretValues.Contains($Value)) {
        $script:secretValues.Add($Value)
    }
}

function ConvertTo-SafeText {
    param([AllowNull()][object] $Value)
    $safe = if ($null -eq $Value) { '' } else { [string]$Value }
    foreach ($secret in $script:secretValues) {
        if (-not [string]::IsNullOrEmpty($secret)) { $safe = $safe.Replace($secret, '[REDACTED]') }
    }
    return $safe
}

function New-CryptographicSecret {
    param([Parameter(Mandatory)][ValidateRange(16, 64)][int] $Bytes)
    $random = [byte[]]::new($Bytes)
    [Security.Cryptography.RandomNumberGenerator]::Fill($random)
    return [Convert]::ToHexString($random).ToLowerInvariant()
}

function New-PublicPassword {
    $password = "Aa9!$(New-CryptographicSecret -Bytes 24)"
    Add-Secret $password
    return $password
}

function Normalize-PublicOrigin {
    param([Parameter(Mandatory)][string] $Origin)
    $candidate = $Origin.Trim()
    if ([string]::IsNullOrWhiteSpace($candidate) -or $candidate.Contains('*')) {
        throw 'PublicOrigin debe ser un origen HTTPS explícito y sin wildcard.'
    }
    try { $uri = [Uri]::new($candidate, [UriKind]::Absolute) }
    catch { throw 'PublicOrigin no es un origen HTTPS válido.' }
    if ($uri.Scheme -cne 'https' -or [string]::IsNullOrWhiteSpace($uri.Host) -or
        -not [string]::IsNullOrEmpty($uri.UserInfo) -or
        -not [string]::IsNullOrEmpty($uri.Query) -or
        -not [string]::IsNullOrEmpty($uri.Fragment) -or
        ($uri.AbsolutePath -cne '/')) {
        throw 'PublicOrigin debe contener sólo scheme HTTPS y authority, sin path, query, fragment ni credenciales.'
    }
    return $uri.GetLeftPart([UriPartial]::Authority)
}

function Test-ExactStringSet {
    param(
        [AllowNull()][object[]] $Actual,
        [Parameter(Mandatory)][string[]] $Expected
    )
    $actualValues = @($Actual | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    $expectedValues = @($Expected | Sort-Object -Unique)
    return $actualValues.Count -eq $expectedValues.Count -and
        (($actualValues -join "`n") -ceq ($expectedValues -join "`n"))
}

function Invoke-Native {
    param(
        [Parameter(Mandatory)][string] $FilePath,
        [Parameter(Mandatory)][string[]] $Arguments,
        [switch] $Capture,
        [switch] $AllowFailure
    )
    $output = @(& $FilePath @Arguments 2>&1 | ForEach-Object { [string]$_ })
    $code = $LASTEXITCODE
    if ($code -ne 0 -and -not $AllowFailure) {
        throw "$(Split-Path $FilePath -Leaf) falló con exit code ${code}: $(ConvertTo-SafeText (($output | Select-Object -Last 80) -join [Environment]::NewLine))"
    }
    if ($Capture) { return ($output -join [Environment]::NewLine).Trim() }
    foreach ($line in $output) { Write-Host (ConvertTo-SafeText $line) }
    return $code
}

function Assert-LocalDockerTarget {
    if ($project -ceq 'gestudio-remote-demo') { throw 'El proyecto protegido no puede operarse.' }
    if (-not [string]::IsNullOrWhiteSpace(
            [Environment]::GetEnvironmentVariable('DOCKER_HOST', 'Process'))) {
        throw 'DOCKER_HOST está definido; se rechazan overrides de daemon.'
    }
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw 'Docker no está disponible.' }
    $context = Invoke-Native -FilePath 'docker' -Arguments @('context', 'show') -Capture
    if ([string]::IsNullOrWhiteSpace($context) -or
        $context -match '(?i)(prod|production|stage|staging|remote|demo)') {
        throw 'El contexto Docker activo es vacío o posee un nombre protegido.'
    }
    $endpoint = (Invoke-Native -FilePath 'docker' -Arguments @(
        'context', 'inspect', '--format', '{{json .Endpoints.docker.Host}}', $context
    ) -Capture | ConvertFrom-Json)
    $localEndpoint = if ($IsWindows) {
        $endpoint -match '^npipe://'
    } else {
        $endpoint -ceq 'unix:///var/run/docker.sock'
    }
    if (-not $localEndpoint) { throw 'El endpoint Docker no es el socket local permitido.' }
    $osType = Invoke-Native -FilePath 'docker' -Arguments @(
        '--context', $context, 'info', '--format', '{{.OSType}}'
    ) -Capture
    if ($osType.Trim() -cne 'linux') { throw 'La demo exige un daemon Docker Linux local.' }
    return $context
}

function Get-ComposePrefix {
    return @('compose', '--env-file', $envFile, '-f', $composeFile, '-f', $portsOverride, '-p', $project)
}

function Invoke-Compose {
    param([Parameter(Mandatory)][string[]] $Arguments, [switch] $Capture, [switch] $AllowFailure)
    $effectiveEnvironment = Read-EnvironmentFile
    $previousValues = @{}
    try {
        foreach ($entry in $effectiveEnvironment.GetEnumerator()) {
            $previousValues[[string]$entry.Key] = [Environment]::GetEnvironmentVariable(
                [string]$entry.Key,
                'Process'
            )
            [Environment]::SetEnvironmentVariable(
                [string]$entry.Key,
                [string]$entry.Value,
                'Process'
            )
        }
        return Invoke-Native -FilePath 'docker' -Arguments ((Get-ComposePrefix) + $Arguments) `
            -Capture:$Capture -AllowFailure:$AllowFailure
    }
    finally {
        foreach ($entry in $previousValues.GetEnumerator()) {
            [Environment]::SetEnvironmentVariable(
                [string]$entry.Key,
                $entry.Value,
                'Process'
            )
        }
    }
}

function Get-ProjectResources {
    $containers = @((Invoke-Native -FilePath 'docker' -Arguments @(
        'ps', '-aq', '--filter', "label=com.docker.compose.project=$project"
    ) -Capture) -split '[\r\n]+' | Where-Object { $_ })
    $volumes = @((Invoke-Native -FilePath 'docker' -Arguments @(
        'volume', 'ls', '-q', '--filter', "label=com.docker.compose.project=$project"
    ) -Capture) -split '[\r\n]+' | Where-Object { $_ })
    $networks = @((Invoke-Native -FilePath 'docker' -Arguments @(
        'network', 'ls', '-q', '--filter', "label=com.docker.compose.project=$project"
    ) -Capture) -split '[\r\n]+' | Where-Object { $_ })
    return [pscustomobject]@{ Containers = @($containers); Volumes = @($volumes); Networks = @($networks) }
}

function Read-EnvironmentFile {
    if (-not (Test-Path -LiteralPath $envFile -PathType Leaf)) { throw 'Falta la configuración privada de la demo.' }
    $values = @{}
    foreach ($line in [IO.File]::ReadAllLines($envFile)) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { continue }
        $separator = $line.IndexOf('=')
        if ($separator -lt 1) { throw 'La configuración privada contiene una línea inválida.' }
        $key = $line.Substring(0, $separator)
        if ($values.ContainsKey($key)) { throw "La configuración privada duplica $key." }
        $values[$key] = $line.Substring($separator + 1)
    }
    return $values
}

function Read-CredentialManifest {
    if (-not (Test-Path -LiteralPath $credentialManifest -PathType Leaf)) {
        throw 'Falta el manifiesto privado de credenciales.'
    }
    $manifest = Get-Content -LiteralPath $credentialManifest -Raw | ConvertFrom-Json -Depth 8
    foreach ($value in @(
        $manifest.platform.password, $manifest.platform.totpSecret,
        $manifest.alpha.password, $manifest.beta.password
    )) { Add-Secret ([string]$value) }
    foreach ($actorPassword in @($manifest.actors.PSObject.Properties | ForEach-Object { $_.Value })) {
        Add-Secret ([string]$actorPassword)
    }
    $publicProperty = $manifest.PSObject.Properties['publicDemo']
    if ($null -ne $publicProperty -and $null -ne $publicProperty.Value) {
        $passwordProperty = $publicProperty.Value.PSObject.Properties['password']
        $proxyProperty = $publicProperty.Value.PSObject.Properties['proxyToken']
        if ($null -ne $passwordProperty) { Add-Secret ([string]$passwordProperty.Value) }
        if ($null -ne $proxyProperty) { Add-Secret ([string]$proxyProperty.Value) }
    }
    return $manifest
}

function Get-PublicDemoConfiguration {
    param([Parameter(Mandatory)][object] $Manifest)
    $property = $Manifest.PSObject.Properties['publicDemo']
    if ($null -eq $property) { return $null }
    if ($null -eq $property.Value) { throw 'publicDemo es inválido en el manifiesto privado.' }
    $public = $property.Value
    foreach ($name in @('username', 'password', 'proxyToken', 'pagesOrigin')) {
        $valueProperty = $public.PSObject.Properties[$name]
        if ($null -eq $valueProperty -or [string]::IsNullOrWhiteSpace([string]$valueProperty.Value)) {
            throw "publicDemo.$name falta en el manifiesto privado."
        }
    }
    $username = [string]$public.username
    $password = [string]$public.password
    $proxyToken = [string]$public.proxyToken
    $origin = Normalize-PublicOrigin -Origin ([string]$public.pagesOrigin)
    if ($username -cne $publicUsername) {
        throw 'El username promocional persistido no cumple el contrato de la demo.'
    }
    $passwordBytes = [Text.Encoding]::UTF8.GetByteCount($password)
    if ($passwordBytes -lt 12 -or $passwordBytes -gt 72 -or $password -match '[\r\n]') {
        throw 'La contraseña promocional persistida no cumple el contrato de seguridad.'
    }
    if ([Text.Encoding]::UTF8.GetByteCount($proxyToken) -lt 32 -or $proxyToken -match '[\r\n]') {
        throw 'El proxy token persistido no cumple el contrato de seguridad.'
    }
    if ([string]$public.pagesOrigin -cne $origin) {
        throw 'pagesOrigin debe persistirse como origen HTTPS canónico.'
    }
    $otherSecrets = [Collections.Generic.List[string]]::new()
    foreach ($value in @(
        $Manifest.platform.password, $Manifest.platform.totpSecret,
        $Manifest.alpha.password, $Manifest.beta.password
    )) {
        if (-not [string]::IsNullOrEmpty([string]$value)) { $otherSecrets.Add([string]$value) }
    }
    foreach ($actorPassword in @($Manifest.actors.PSObject.Properties | ForEach-Object { $_.Value })) {
        if (-not [string]::IsNullOrEmpty([string]$actorPassword)) {
            $otherSecrets.Add([string]$actorPassword)
        }
    }
    if (Test-Path -LiteralPath $envFile -PathType Leaf) {
        $privateEnvironment = Read-EnvironmentFile
        foreach ($entry in $privateEnvironment.GetEnumerator()) {
            if ([string]$entry.Key -cne 'APP_REMOTE_DEMO_PROXY_TOKEN' -and
                [string]$entry.Key -match '(?i)(PASSWORD|SECRET|TOKEN)$' -and
                -not [string]::IsNullOrEmpty([string]$entry.Value)) {
                $otherSecrets.Add([string]$entry.Value)
            }
        }
    }
    if ($password -ceq $proxyToken -or @($otherSecrets | Where-Object {
            $_ -ceq $password -or $_ -ceq $proxyToken
        }).Count -ne 0) {
        throw 'La contraseña promocional y el proxy token deben ser secretos independientes.'
    }
    Add-Secret $password
    Add-Secret $proxyToken
    return [pscustomobject]@{
        username = $username
        password = $password
        proxyToken = $proxyToken
        pagesOrigin = $origin
    }
}

function Write-CredentialManifest {
    param([Parameter(Mandatory)][object] $Manifest)
    Set-PrivateFileContent -Path $credentialManifest `
        -Content (($Manifest | ConvertTo-Json -Depth 8) + "`n")
}

function Set-PublicDemoConfiguration {
    param(
        [Parameter(Mandatory)][object] $Manifest,
        [Parameter(Mandatory)][string] $Origin,
        [Parameter(Mandatory)][string] $Password,
        [Parameter(Mandatory)][string] $ProxyToken
    )
    Add-Secret $Password
    Add-Secret $ProxyToken
    $value = [pscustomobject][ordered]@{
        username = $publicUsername
        password = $Password
        proxyToken = $ProxyToken
        pagesOrigin = $Origin
    }
    $property = $Manifest.PSObject.Properties['publicDemo']
    if ($null -eq $property) {
        $Manifest | Add-Member -MemberType NoteProperty -Name publicDemo -Value $value
    }
    else {
        $property.Value = $value
    }
    Write-CredentialManifest -Manifest $Manifest
    return $value
}

function Assert-PrivatePath {
    param([Parameter(Mandatory)][string] $Path, [Parameter(Mandatory)][bool] $Directory)
    if (-not (Test-Path -LiteralPath $Path)) { throw "Falta el recurso privado esperado: $(Split-Path $Path -Leaf)" }
    if (-not $IsWindows) {
        $expected = if ($Directory) { '700' } else { '600' }
        $actual = Invoke-Native -FilePath 'stat' -Arguments @('-c', '%a', '--', $Path) -Capture
        if ($actual -cne $expected) { throw "Permisos privados inválidos en $(Split-Path $Path -Leaf)." }
        return
    }
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

function Get-FileSha256 {
    param([Parameter(Mandatory)][string] $Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
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
            $sha.AppendData([Text.Encoding]::UTF8.GetBytes($relative + "`n"))
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

function Set-PrivateFileContent {
    param([Parameter(Mandatory)][string] $Path, [Parameter(Mandatory)][string] $Content)
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
    if ($IsWindows) {
        $item = [IO.FileInfo]::new($Path)
        $sections = [Security.AccessControl.AccessControlSections]::Access
        $acl = [IO.FileSystemAclExtensions]::GetAccessControl($item, $sections)
        $rules = @($acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]))
        $acl.SetAccessRuleProtection($true, $false)
        foreach ($rule in $rules) { [void]$acl.RemoveAccessRuleAll($rule) }
        $owner = [Security.Principal.WindowsIdentity]::GetCurrent().User
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
                $owner,
                [Security.AccessControl.FileSystemRights]::FullControl,
                [Security.AccessControl.AccessControlType]::Allow))
        [IO.FileSystemAclExtensions]::SetAccessControl($item, $acl)
    }
    else {
        [void](Invoke-Native -FilePath 'chmod' -Arguments @('600', '--', $Path))
    }
    Assert-PrivatePath -Path $Path -Directory $false
}

function Get-BusinessDateKey {
    $zone = $null
    foreach ($zoneId in @('Argentina Standard Time', 'America/Argentina/Buenos_Aires')) {
        try {
            $zone = [TimeZoneInfo]::FindSystemTimeZoneById($zoneId)
            break
        }
        catch { }
    }
    if ($null -eq $zone) { throw 'No se pudo resolver la zona horaria de negocio.' }
    return [TimeZoneInfo]::ConvertTimeFromUtc([DateTime]::UtcNow, $zone).ToString('yyyy-MM-dd')
}

function Get-FixtureContract {
    $components = @(
        '1',
        (Get-BusinessDateKey),
        (Get-FileSha256 -Path $PSCommandPath),
        (Get-FileSha256 -Path $seedLauncher),
        (Get-FileSha256 -Path (Join-Path $PSScriptRoot 'gestudio_demo_seed_full.sql'))
    ) -join "`n"
    $digest = [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($components))
    return [pscustomobject]@{
        schemaVersion = 1
        businessDate = Get-BusinessDateKey
        contractHash = [Convert]::ToHexString($digest).ToLowerInvariant()
    }
}

function Test-FixtureStateCurrent {
    if (-not (Test-Path -LiteralPath $fixtureState -PathType Leaf)) { return $false }
    try {
        $saved = Get-Content -LiteralPath $fixtureState -Raw | ConvertFrom-Json
        $current = Get-FixtureContract
        return [int]$saved.schemaVersion -eq $current.schemaVersion -and
            [string]$saved.businessDate -ceq $current.businessDate -and
            [string]$saved.contractHash -ceq $current.contractHash
    }
    catch { return $false }
}

function Write-FixtureState {
    $current = Get-FixtureContract
    $json = $current | ConvertTo-Json -Depth 3
    Set-PrivateFileContent -Path $fixtureState -Content ($json + "`n")
}

function Update-EnvironmentValues {
    param([Parameter(Mandatory)][Collections.IDictionary] $Updates)
    $values = Read-EnvironmentFile
    $order = [Collections.Generic.List[string]]::new()
    foreach ($line in [IO.File]::ReadAllLines($envFile)) {
        if ($line -match '^(?<key>[A-Za-z_][A-Za-z0-9_]*)=') { $order.Add($Matches.key) }
    }
    foreach ($entry in $Updates.GetEnumerator()) {
        $key = [string]$entry.Key
        $value = [string]$entry.Value
        if ($key -notmatch '^[A-Za-z_][A-Za-z0-9_]*$' -or $value -match '[\r\n]') {
            throw 'Se rechazó un valor inválido para la configuración privada.'
        }
        if (-not $values.ContainsKey($key)) { $order.Add($key) }
        $values[$key] = $value
    }
    $content = ($order | ForEach-Object { "$_=$($values[$_])" }) -join "`n"
    Set-PrivateFileContent -Path $envFile -Content ($content + "`n")
}

function Update-BuildMetadata {
    Update-EnvironmentValues -Updates ([ordered]@{
        VCS_REF = Invoke-Native -FilePath 'git' -Arguments @('-C', $repoRoot, 'rev-parse', 'HEAD') -Capture
        COMPOSE_SHA = Get-FileSha256 -Path $composeFile
        BACKEND_SOURCE_SHA = Get-SourceFingerprint -Path (Join-Path $repoRoot 'backend')
        FRONTEND_SOURCE_SHA = Get-SourceFingerprint -Path (Join-Path $repoRoot 'frontend')
    })
}

function Set-PublicEnvironment {
    param([Parameter(Mandatory)][object] $PublicDemo)
    Update-EnvironmentValues -Updates ([ordered]@{
        SPRING_PROFILES_ACTIVE = 'remote-demo'
        APP_CORS_ALLOWED_ORIGINS = [string]$PublicDemo.pagesOrigin
        APP_REMOTE_DEMO_PROXY_TOKEN = [string]$PublicDemo.proxyToken
        APP_SECURITY_REFRESH_COOKIE_SECURE = 'true'
        APP_SECURITY_REFRESH_COOKIE_SAME_SITE = 'Strict'
        APP_SECURITY_REFRESH_COOKIE_DOMAIN = ''
        APP_PLATFORM_REFRESH_COOKIE_SECURE = 'true'
        APP_PLATFORM_REFRESH_COOKIE_SAME_SITE = 'Strict'
        APP_PLATFORM_REFRESH_COOKIE_DOMAIN = ''
    })
}

function Invoke-DatabaseSql {
    param([Parameter(Mandatory)][string] $Sql)
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Sql))
    return Invoke-Compose -Arguments @(
        'exec', '-T', 'db', 'sh', '-ec',
        'printf "%s" "$1" | base64 -d | psql --no-psqlrc --quiet --tuples-only --no-align --set ON_ERROR_STOP=1 --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" --file=-',
        'sh', $encoded
    ) -Capture
}

function Invoke-AlphaSeed {
    $manifest = Read-CredentialManifest
    $environment = Read-EnvironmentFile
    $oldPassword = [Environment]::GetEnvironmentVariable('PGPASSWORD', 'Process')
    try {
        [Environment]::SetEnvironmentVariable('PGPASSWORD', [string]$environment.POSTGRES_PASSWORD, 'Process')
        $arguments = @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $seedLauncher,
            '-Action', 'SeedNative', '-DatabaseHost', '127.0.0.1',
            '-DatabasePort', [string]$databasePort, '-DatabaseName', [string]$environment.POSTGRES_DB,
            '-DatabaseUser', [string]$environment.POSTGRES_USER,
            '-DemoTenantId', [string]$manifest.alpha.id,
            '-DemoTenantCode', [string]$manifest.alpha.code,
            '-DemoTenantName', [string]$manifest.alpha.name,
            '-CredentialManifestPath', $credentialManifest,
            '-AllowExistingControlPlane'
        )
        [void](Invoke-Native -FilePath 'pwsh' -Arguments $arguments)
    }
    finally {
        [Environment]::SetEnvironmentVariable('PGPASSWORD', $oldPassword, 'Process')
    }
}

function Invoke-BetaSeed {
    $manifest = Read-CredentialManifest
    $betaId = [string]$manifest.beta.id
    $alphaId = [string]$manifest.alpha.id
    if ($betaId -notmatch '^[0-9a-f-]{36}$' -or $alphaId -notmatch '^[0-9a-f-]{36}$') {
        throw 'IDs tenant inválidos en el manifiesto privado.'
    }
    [void](Invoke-DatabaseSql -Sql @"
BEGIN;
UPDATE alumnos
SET documento='49287134', email='beta.alumno@demo.local'
WHERE tenant_id='$betaId'::uuid AND apellido='Beta E2E d3a010ca1001';

INSERT INTO salones(tenant_id,nombre,descripcion,activo)
VALUES ('$betaId'::uuid,'Sala Beta','Sala sintética del tenant Beta',TRUE)
ON CONFLICT (tenant_id,nombre) DO UPDATE SET activo=TRUE;

INSERT INTO profesores(tenant_id,nombre,apellido,telefono,activo,version)
SELECT '$betaId'::uuid,'Docente','Beta','000000',TRUE,0
WHERE NOT EXISTS (SELECT 1 FROM profesores WHERE tenant_id='$betaId'::uuid AND nombre='Docente' AND apellido='Beta');

INSERT INTO disciplinas(tenant_id,nombre,salon_id,profesor_id,valor_cuota,matricula,clase_suelta,clase_prueba,activo,version)
SELECT '$betaId'::uuid,'Danza Beta',s.id,p.id,15000.00,5000.00,4000.00,0.00,TRUE,0
FROM salones s, profesores p
WHERE s.tenant_id='$betaId'::uuid AND s.nombre='Sala Beta'
  AND p.tenant_id='$betaId'::uuid AND p.nombre='Docente' AND p.apellido='Beta'
  AND NOT EXISTS (SELECT 1 FROM disciplinas WHERE tenant_id='$betaId'::uuid AND nombre='Danza Beta');

INSERT INTO stocks(tenant_id,nombre,precio,cantidad_actual,requiere_control_de_stock,codigo_barras,activo,version)
VALUES ('$betaId'::uuid,'Botella Beta',6000.00,5,TRUE,'7790000000012',TRUE,0)
ON CONFLICT (tenant_id,nombre) DO UPDATE
SET precio=EXCLUDED.precio,cantidad_actual=EXCLUDED.cantidad_actual,
    codigo_barras=EXCLUDED.codigo_barras,activo=TRUE;

INSERT INTO movimientos_stock(tenant_id,stock_id,tipo,cantidad,usuario_id,idempotency_key,motivo)
SELECT '$betaId'::uuid,s.id,'INGRESO',5,u.id,'demo-local:beta:stock-inicial','Existencia inicial sintética'
FROM stocks s, usuarios u
WHERE s.tenant_id='$betaId'::uuid AND s.nombre='Botella Beta'
  AND lower(u.nombre_usuario)='beta.demo.admin'
ON CONFLICT (tenant_id,idempotency_key) DO NOTHING;

DO `$demo`$
BEGIN
  IF (SELECT count(*) FROM alumnos WHERE tenant_id='$alphaId'::uuid AND documento='49287134') <> 1
     OR (SELECT count(*) FROM alumnos WHERE tenant_id='$betaId'::uuid AND documento='49287134') <> 1
     OR (SELECT count(*) FROM stocks WHERE tenant_id='$alphaId'::uuid AND codigo_barras='7790000000012') <> 1
     OR (SELECT count(*) FROM stocks WHERE tenant_id='$betaId'::uuid AND codigo_barras='7790000000012') <> 1 THEN
    RAISE EXCEPTION 'Las colisiones tenant-scoped no quedaron materializadas';
  END IF;
END
`$demo`$;
COMMIT;
"@)
}

function Test-HttpStatus {
    param(
        [Parameter(Mandatory)][string] $Uri,
        [Parameter(Mandatory)][int[]] $Expected,
        [Collections.IDictionary] $Headers = @{}
    )
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $Uri -Headers $Headers `
            -TimeoutSec 15 -SkipHttpErrorCheck
        return [int]$response.StatusCode -in $Expected
    }
    catch { return $false }
}

function Invoke-LocalDemoApi {
    param(
        [Parameter(Mandatory)][object] $PublicDemo,
        [Parameter(Mandatory)][ValidateSet('GET', 'POST', 'PUT')][string] $Method,
        [Parameter(Mandatory)][string] $Path,
        [AllowNull()][object] $Body,
        [AllowNull()][string] $AccessToken,
        [AllowNull()][string] $CookieHeader,
        [Parameter(Mandatory)][int[]] $Expected
    )
    if ($Path -notmatch '^/api(?:/|$)') { throw 'Se rechazó una llamada fuera del API local.' }
    $headers = @{
        Origin = [string]$PublicDemo.pagesOrigin
        'X-Gestudio-Proxy-Token' = [string]$PublicDemo.proxyToken
    }
    if (-not [string]::IsNullOrWhiteSpace($AccessToken)) {
        Add-Secret $AccessToken
        $headers.Authorization = "Bearer $AccessToken"
    }
    if (-not [string]::IsNullOrWhiteSpace($CookieHeader)) {
        Add-Secret $CookieHeader
        $headers.Cookie = $CookieHeader
    }
    $parameters = @{
        UseBasicParsing = $true
        Uri = "http://127.0.0.1:$backendPort$Path"
        Method = $Method
        Headers = $headers
        TimeoutSec = 30
        SkipHttpErrorCheck = $true
    }
    if ($null -ne $Body) {
        $parameters.ContentType = 'application/json'
        $parameters.Body = $Body | ConvertTo-Json -Depth 10 -Compress
    }
    try { $response = Invoke-WebRequest @parameters }
    catch { throw "El API local no respondió para $Method $Path." }
    if ([int]$response.StatusCode -notin $Expected) {
        throw "El API local devolvió HTTP $([int]$response.StatusCode) para $Method $Path."
    }
    return $response
}

function Get-LocalRefreshCookieHeader {
    param([Parameter(Mandatory)][object] $Response)
    $setCookies = @($Response.Headers.'Set-Cookie')
    $cookieLine = @($setCookies | Where-Object {
            [string]$_ -match '(?i)(?:^|;)\s*Path=/api/login(?:;|$)'
        } | Select-Object -First 1)
    if ($cookieLine.Count -ne 1) { throw 'El login local no devolvió una cookie de refresh identificable.' }
    $pair = (([string]$cookieLine[0]) -split ';', 2)[0]
    $separator = $pair.IndexOf('=')
    if ($separator -lt 1 -or [string]::IsNullOrWhiteSpace($pair.Substring($separator + 1))) {
        throw 'La cookie de refresh local es inválida.'
    }
    Add-Secret $pair.Substring($separator + 1)
    Add-Secret $pair
    return $pair
}

function Revoke-LocalRefreshSession {
    param(
        [Parameter(Mandatory)][object] $PublicDemo,
        [Parameter(Mandatory)][string] $CookieHeader
    )
    [void](Invoke-LocalDemoApi -PublicDemo $PublicDemo -Method POST -Path '/api/login/logout' `
        -Body $null -AccessToken $null -CookieHeader $CookieHeader -Expected @(204))
}

function ConvertFrom-ApiResponse {
    param([Parameter(Mandatory)][object] $Response)
    if ([string]::IsNullOrWhiteSpace([string]$Response.Content)) {
        throw 'El API local devolvió una respuesta JSON vacía.'
    }
    try { return $Response.Content | ConvertFrom-Json -Depth 20 }
    catch { throw 'El API local devolvió una respuesta JSON inválida.' }
}

function Assert-PublicProfile {
    param(
        [Parameter(Mandatory)][object] $Profile,
        [Parameter(Mandatory)][object] $Manifest
    )
    $roles = @($Profile.roles | ForEach-Object { [string]$_ })
    $permissions = @($Profile.permisos | ForEach-Object { [string]$_ })
    $available = @($Profile.tenantsDisponibles)
    if ([string]$Profile.nombreUsuario -cne $publicUsername -or
        $Profile.activo -ne $true -or
        -not (Test-ExactStringSet -Actual $roles -Expected @($publicRoleCode)) -or
        -not (Test-ExactStringSet -Actual $permissions -Expected $publicPermissions) -or
        @($permissions | Where-Object {
                $_ -in @('PERM_USUARIOS_ADMIN', 'PERM_ROLES_ADMIN', 'PERM_CONFIG_ADMIN')
            }).Count -ne 0 -or
        $null -eq $Profile.tenantActivo -or
        [string]$Profile.tenantActivo.id -cne [string]$Manifest.alpha.id -or
        [string]$Profile.tenantActivo.codigo -cne [string]$Manifest.alpha.code -or
        [string]$Profile.tenantActivo.nombre -cne [string]$Manifest.alpha.name -or
        [string]$Profile.tenantActivo.estado -cne 'ACTIVE' -or
        $available.Count -ne 1 -or
        [string]$available[0].id -cne [string]$Manifest.alpha.id -or
        [string]$available[0].codigo -cne [string]$Manifest.alpha.code -or
        [string]$available[0].nombre -cne [string]$Manifest.alpha.name -or
        [string]$available[0].estado -cne 'ACTIVE') {
        throw 'El perfil promocional no quedó aislado en Alpha con el rol de sólo lectura exacto.'
    }
}

function Invoke-PublicFixtureConvergence {
    param(
        [Parameter(Mandatory)][object] $Manifest,
        [Parameter(Mandatory)][object] $PublicDemo,
        [AllowNull()][string] $PasswordOverride
    )
    $passwordNeedsRepair = $false
    if ([string]::IsNullOrWhiteSpace($PasswordOverride)) {
        $probeResponse = Invoke-LocalDemoApi -PublicDemo $PublicDemo -Method POST -Path '/api/login' `
            -Body ([ordered]@{
                nombreUsuario = [string]$PublicDemo.username
                contrasena = [string]$PublicDemo.password
                tenantId = [string]$Manifest.alpha.id
            }) -AccessToken $null -Expected @(200, 401)
        if ([int]$probeResponse.StatusCode -eq 200) {
            $probeCookie = Get-LocalRefreshCookieHeader -Response $probeResponse
            $alreadyConverged = $false
            try {
                $probe = ConvertFrom-ApiResponse -Response $probeResponse
                Assert-PublicProfile -Profile $probe.usuario -Manifest $Manifest
                $alreadyConverged = $true
            }
            catch { $alreadyConverged = $false }
            finally { Revoke-LocalRefreshSession -PublicDemo $PublicDemo -CookieHeader $probeCookie }
            if ($alreadyConverged) { return }
        }
        else { $passwordNeedsRepair = $true }
    }

    $actorProperty = $Manifest.actors.PSObject.Properties['demo-superadmin']
    if ($null -eq $actorProperty -or [string]::IsNullOrWhiteSpace([string]$actorProperty.Value)) {
        throw 'Falta la credencial privada del actor de fixture.'
    }
    $actorPassword = [string]$actorProperty.Value
    Add-Secret $actorPassword
    $loginResponse = Invoke-LocalDemoApi -PublicDemo $PublicDemo -Method POST -Path '/api/login' `
        -Body ([ordered]@{
            nombreUsuario = 'demo-superadmin'
            contrasena = $actorPassword
            tenantId = [string]$Manifest.alpha.id
        }) -AccessToken $null -Expected @(200)
    $actorCookie = Get-LocalRefreshCookieHeader -Response $loginResponse
    try {
        $login = ConvertFrom-ApiResponse -Response $loginResponse
        $actorToken = [string]$login.accessToken
        if ([string]::IsNullOrWhiteSpace($actorToken) -or
            [string]$login.usuario.tenantActivo.id -cne [string]$Manifest.alpha.id) {
            throw 'El actor privado no inició sesión exclusivamente en Alpha.'
        }
        Add-Secret $actorToken

        $rolesResponse = Invoke-LocalDemoApi -PublicDemo $PublicDemo -Method GET -Path '/api/roles' `
            -Body $null -AccessToken $actorToken -Expected @(200)
        $roles = @((ConvertFrom-ApiResponse -Response $rolesResponse))
        $matches = @($roles | Where-Object { [string]$_.codigo -ceq $publicRoleCode })
        if ($matches.Count -gt 1) { throw 'Existe más de un rol DEMO_COMERCIAL en Alpha.' }
        $desiredRole = [ordered]@{
            codigo = $publicRoleCode
            nombre = 'Demo comercial'
            descripcionFuncional = 'Acceso promocional de solo lectura'
            permisos = $publicPermissions
        }
        if ($matches.Count -eq 0) {
            $roleResponse = Invoke-LocalDemoApi -PublicDemo $PublicDemo -Method POST -Path '/api/roles' `
                -Body $desiredRole -AccessToken $actorToken -Expected @(201)
            $role = ConvertFrom-ApiResponse -Response $roleResponse
        }
        else {
            $role = $matches[0]
            $rolePermissions = @($role.permisos | ForEach-Object { [string]$_.codigo })
            if ([string]$role.nombre -cne [string]$desiredRole.nombre -or
                [string]$role.descripcionFuncional -cne [string]$desiredRole.descripcionFuncional -or
                $role.activo -ne $true -or $role.sistema -ne $false -or $role.editable -ne $true -or
                -not (Test-ExactStringSet -Actual $rolePermissions -Expected $publicPermissions)) {
                $roleResponse = Invoke-LocalDemoApi -PublicDemo $PublicDemo -Method PUT `
                    -Path "/api/roles/$([long]$role.id)" -Body ([ordered]@{
                        nombre = $desiredRole.nombre
                        descripcionFuncional = $desiredRole.descripcionFuncional
                        activo = $true
                        permisos = $publicPermissions
                    }) -AccessToken $actorToken -Expected @(200)
                $role = ConvertFrom-ApiResponse -Response $roleResponse
            }
        }
        if ([string]$role.codigo -cne $publicRoleCode) {
            throw 'No se pudo converger el rol promocional en Alpha.'
        }

        $usersResponse = Invoke-LocalDemoApi -PublicDemo $PublicDemo -Method GET -Path '/api/usuarios' `
            -Body $null -AccessToken $actorToken -Expected @(200)
        $users = @((ConvertFrom-ApiResponse -Response $usersResponse))
        $userMatches = @($users | Where-Object { [string]$_.nombreUsuario -ieq $publicUsername })
        if ($userMatches.Count -gt 1) { throw 'Existe más de un usuario promocional visible en Alpha.' }
        $effectivePassword = if ([string]::IsNullOrWhiteSpace($PasswordOverride)) {
            [string]$PublicDemo.password
        } else {
            Add-Secret $PasswordOverride
            $PasswordOverride
        }
        if ($userMatches.Count -eq 0) {
            $userResponse = Invoke-LocalDemoApi -PublicDemo $PublicDemo -Method POST `
                -Path '/api/usuarios/registro' -Body ([ordered]@{
                    nombreUsuario = $publicUsername
                    contrasena = $effectivePassword
                    roles = @($publicRoleCode)
                }) -AccessToken $actorToken -Expected @(201)
            $user = ConvertFrom-ApiResponse -Response $userResponse
        }
        else {
            $user = $userMatches[0]
            $userRoles = @($user.roles | ForEach-Object { [string]$_ })
            $requiresUpdate = $user.activo -ne $true -or $passwordNeedsRepair -or
                -not (Test-ExactStringSet -Actual $userRoles -Expected @($publicRoleCode)) -or
                -not [string]::IsNullOrWhiteSpace($PasswordOverride)
            if ($requiresUpdate) {
                $body = [ordered]@{
                    nombreUsuario = $publicUsername
                    roles = @($publicRoleCode)
                    activo = $true
                }
                if ($passwordNeedsRepair -or -not [string]::IsNullOrWhiteSpace($PasswordOverride)) {
                    $body.contrasena = $effectivePassword
                }
                $userResponse = Invoke-LocalDemoApi -PublicDemo $PublicDemo -Method PUT `
                    -Path "/api/usuarios/$([long]$user.id)" -Body $body `
                    -AccessToken $actorToken -Expected @(200)
                $user = ConvertFrom-ApiResponse -Response $userResponse
            }
        }
        Assert-PublicProfile -Profile $user -Manifest $Manifest
    }
    finally { Revoke-LocalRefreshSession -PublicDemo $PublicDemo -CookieHeader $actorCookie }
}

function Assert-PublicDemoHttpContract {
    param(
        [Parameter(Mandatory)][object] $Manifest,
        [Parameter(Mandatory)][object] $PublicDemo
    )
    $loginResponse = Invoke-LocalDemoApi -PublicDemo $PublicDemo -Method POST -Path '/api/login' `
        -Body ([ordered]@{
            nombreUsuario = [string]$PublicDemo.username
            contrasena = [string]$PublicDemo.password
            tenantId = [string]$Manifest.alpha.id
        }) -AccessToken $null -Expected @(200)
    $refreshCookie = Get-LocalRefreshCookieHeader -Response $loginResponse
    try {
        $login = ConvertFrom-ApiResponse -Response $loginResponse
        $accessToken = [string]$login.accessToken
        if ([string]::IsNullOrWhiteSpace($accessToken)) { throw 'El login promocional no emitió access token.' }
        Add-Secret $accessToken
        Assert-PublicProfile -Profile $login.usuario -Manifest $Manifest

        $profileResponse = Invoke-LocalDemoApi -PublicDemo $PublicDemo -Method GET `
            -Path '/api/usuarios/perfil' -Body $null -AccessToken $accessToken -Expected @(200)
        Assert-PublicProfile -Profile (ConvertFrom-ApiResponse -Response $profileResponse) -Manifest $Manifest

        $studentsResponse = Invoke-LocalDemoApi -PublicDemo $PublicDemo -Method GET `
            -Path '/api/alumnos?page=0&size=200' -Body $null -AccessToken $accessToken -Expected @(200)
        $students = ConvertFrom-ApiResponse -Response $studentsResponse
        if ([int64]$students.totalElements -lt 1 -or @($students.content).Count -lt 1 -or
            [string]$studentsResponse.Content -notmatch [regex]::Escape('Alpha E2E d3a010ca1001') -or
            [string]$studentsResponse.Content -match [regex]::Escape('Beta E2E d3a010ca1001') -or
            [string]$studentsResponse.Content -match [regex]::Escape('beta.alumno@demo.local')) {
            throw 'El listado promocional no contiene el marcador Alpha aislado de Beta.'
        }
        [void](Invoke-LocalDemoApi -PublicDemo $PublicDemo -Method GET -Path '/api/usuarios' `
            -Body $null -AccessToken $accessToken -Expected @(403))
        [void](Invoke-LocalDemoApi -PublicDemo $PublicDemo -Method GET -Path '/api/roles' `
            -Body $null -AccessToken $accessToken -Expected @(403))
        [void](Invoke-LocalDemoApi -PublicDemo $PublicDemo -Method GET -Path '/api/platform/me' `
            -Body $null -AccessToken $accessToken -Expected @(403))
    }
    finally { Revoke-LocalRefreshSession -PublicDemo $PublicDemo -CookieHeader $refreshCookie }
}

function Get-ImageContract {
    param([Parameter(Mandatory)][string] $Image, [Parameter(Mandatory)][string] $Service,
          [Parameter(Mandatory)][string] $Revision, [Parameter(Mandatory)][string] $ComposeSha,
          [Parameter(Mandatory)][string] $SourceSha)
    try {
        $imageId = Invoke-Native -FilePath 'docker' -Arguments @('image', 'inspect', '--format', '{{.Id}}', $Image) -Capture
        $labels = (Invoke-Native -FilePath 'docker' -Arguments @(
            'image', 'inspect', '--format', '{{json .Config.Labels}}', $Image
        ) -Capture | ConvertFrom-Json)
        $containerId = Invoke-Compose -Arguments @('ps', '-q', $Service) -Capture
        if ($containerId -notmatch '^[a-f0-9]{64}$') { return $false }
        $containerImage = Invoke-Native -FilePath 'docker' -Arguments @('inspect', '--format', '{{.Image}}', $containerId) -Capture
        return $containerImage -ceq $imageId -and
            $labels.'org.opencontainers.image.revision' -ceq $Revision -and
            $labels.'org.gestudio.compose.sha256' -ceq $ComposeSha -and
            $labels.'org.gestudio.source.sha256' -ceq $SourceSha
    }
    catch { return $false }
}

function Invoke-Status {
    $reasons = [Collections.Generic.List[string]]::new()
    try { [void](Assert-LocalDockerTarget) } catch { $reasons.Add($_.Exception.Message) }
    foreach ($path in @($stateRoot, $envFile, $portsOverride, $credentialManifest, $recoveryCodes, $fixtureState)) {
        if (-not (Test-Path -LiteralPath $path)) { $reasons.Add("Falta $(Split-Path $path -Leaf)") }
    }
    if ($reasons.Count -gt 0) {
        Write-Host 'Demo disponible: NO'
        $reasons | ForEach-Object { Write-Host "- $_" }
        Write-Host 'STATUS: FAIL'
        return $false
    }
    try {
        Assert-PrivatePath -Path $stateRoot -Directory $true
        foreach ($path in @($envFile, $portsOverride, $credentialManifest, $recoveryCodes, $fixtureState)) {
            Assert-PrivatePath -Path $path -Directory $false
        }
        if (-not (Test-FixtureStateCurrent)) {
            $reasons.Add('El contrato persistido del fixture presenta drift.')
        }
        $manifest = Read-CredentialManifest
        $publicDemo = Get-PublicDemoConfiguration -Manifest $manifest
        $publicMode = $null -ne $publicDemo
        $environment = Read-EnvironmentFile

        $config = (Invoke-Compose -Arguments @('config', '--format', 'json') -Capture | ConvertFrom-Json -Depth 30)
        if ($config.name -cne $project -or
            $config.services.db.ports.Count -ne 1 -or $config.services.db.ports[0].host_ip -cne '127.0.0.1' -or
            [int]$config.services.db.ports[0].published -ne $databasePort -or
            $config.services.backend.ports.Count -ne 1 -or $config.services.backend.ports[0].host_ip -cne '127.0.0.1' -or
            [int]$config.services.backend.ports[0].published -ne $backendPort -or
            $config.services.frontend.ports.Count -ne 1 -or $config.services.frontend.ports[0].host_ip -cne '127.0.0.1' -or
            [int]$config.services.frontend.ports[0].published -ne $frontendPort -or
             $config.services.backend.environment.APP_BOOTSTRAP_SUPERADMIN_ENABLED -cne 'false') {
            $reasons.Add('Compose efectivo no respeta proyecto, loopback o bootstrap-off.')
        }
        $backendEnvironment = $config.services.backend.environment
        if ($publicMode) {
            if ([string]$environment.SPRING_PROFILES_ACTIVE -cne 'remote-demo' -or
                [string]$environment.APP_CORS_ALLOWED_ORIGINS -cne [string]$publicDemo.pagesOrigin -or
                [string]$environment.APP_REMOTE_DEMO_PROXY_TOKEN -cne [string]$publicDemo.proxyToken -or
                [string]$backendEnvironment.SPRING_PROFILES_ACTIVE -cne 'remote-demo' -or
                [string]$backendEnvironment.APP_CORS_ALLOWED_ORIGINS -cne [string]$publicDemo.pagesOrigin -or
                [string]$backendEnvironment.APP_REMOTE_DEMO_PROXY_TOKEN -cne [string]$publicDemo.proxyToken -or
                [string]$backendEnvironment.APP_SECURITY_REFRESH_COOKIE_SECURE -cne 'true' -or
                [string]$backendEnvironment.APP_SECURITY_REFRESH_COOKIE_SAME_SITE -cne 'Strict' -or
                -not [string]::IsNullOrEmpty([string]$backendEnvironment.APP_SECURITY_REFRESH_COOKIE_DOMAIN) -or
                [string]$backendEnvironment.APP_PLATFORM_REFRESH_COOKIE_SECURE -cne 'true' -or
                [string]$backendEnvironment.APP_PLATFORM_REFRESH_COOKIE_SAME_SITE -cne 'Strict' -or
                -not [string]::IsNullOrEmpty([string]$backendEnvironment.APP_PLATFORM_REFRESH_COOKIE_DOMAIN) -or
                [string]$backendEnvironment.APP_SCHEDULING_ENABLED -cne 'false') {
                $reasons.Add('El perfil público, CORS, proxy o cookies no cumplen el contrato remoto.')
            }
        }
        elseif ([string]$backendEnvironment.SPRING_PROFILES_ACTIVE -cne 'dev' -or
            -not [string]::IsNullOrEmpty([string]$backendEnvironment.APP_REMOTE_DEMO_PROXY_TOKEN)) {
            $reasons.Add('La demo privada no conserva su perfil local sin proxy público.')
        }

        $containerRows = @((Invoke-Native -FilePath 'docker' -Arguments @(
            'ps', '-a', '--filter', "label=com.docker.compose.project=$project", '--format',
            '{{.ID}}|{{.Label "com.docker.compose.service"}}|{{.State}}|{{.Status}}'
        ) -Capture) -split '[\r\n]+' | Where-Object { $_ })
        if ($containerRows.Count -ne 3 -or @($containerRows | Where-Object {
                $_ -notmatch '^[a-f0-9]+\|(db|backend|frontend)\|running\|Up .*\(healthy\)$'
            }).Count -ne 0 -or @($containerRows | ForEach-Object { ($_ -split '\|')[1] } | Select-Object -Unique).Count -ne 3) {
            $reasons.Add('Los tres contenedores exactos no están running/healthy.')
        }

        $anonymousApiOk = if ($publicMode) {
            $proxyHeaders = @{
                Origin = [string]$publicDemo.pagesOrigin
                'X-Gestudio-Proxy-Token' = [string]$publicDemo.proxyToken
            }
            (Test-HttpStatus -Uri "http://127.0.0.1:$backendPort/api/alumnos" -Expected @(404)) -and
                (Test-HttpStatus -Uri "http://127.0.0.1:$backendPort/api/alumnos" `
                    -Headers $proxyHeaders -Expected @(401))
        }
        else {
            Test-HttpStatus -Uri "http://127.0.0.1:$backendPort/api/alumnos" -Expected @(401)
        }
        if (-not (Test-HttpStatus -Uri "http://127.0.0.1:$backendPort/actuator/health/liveness" -Expected @(200)) -or
            -not (Test-HttpStatus -Uri "http://127.0.0.1:$backendPort/actuator/health/readiness" -Expected @(200)) -or
            -not (Test-HttpStatus -Uri "http://127.0.0.1:$frontendPort/" -Expected @(200)) -or
            -not $anonymousApiOk) {
            $reasons.Add('Health, frontend o contrato anónimo HTTP falló.')
        }

        $revision = Invoke-Native -FilePath 'git' -Arguments @('-C', $repoRoot, 'rev-parse', 'HEAD') -Capture
        $composeSha = Get-FileSha256 -Path $composeFile
        $backendSource = Get-SourceFingerprint -Path (Join-Path $repoRoot 'backend')
        $frontendSource = Get-SourceFingerprint -Path (Join-Path $repoRoot 'frontend')
        if (-not (Get-ImageContract -Image $backendImage -Service 'backend' -Revision $revision `
                -ComposeSha $composeSha -SourceSha $backendSource) -or
            -not (Get-ImageContract -Image $frontendImage -Service 'frontend' -Revision $revision `
                -ComposeSha $composeSha -SourceSha $frontendSource)) {
            $reasons.Add('Las imágenes o contenedores presentan drift respecto del checkout.')
        }

        $latest = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'backend\src\main\resources\db\migration') `
            -Filter 'V*__*.sql' -File | ForEach-Object {
                if ($_.Name -match '^V(?<v>[0-9]+)__') { [int]$Matches.v }
            } | Measure-Object -Maximum).Maximum
        $alphaId = [string]$manifest.alpha.id
        $betaId = [string]$manifest.beta.id
        $appRole = [string]$environment.POSTGRES_APP_USER
        $controlRole = [string]$environment.POSTGRES_CONTROL_USER
        foreach ($identifier in @($alphaId, $betaId)) {
            if ($identifier -notmatch '^[0-9a-f-]{36}$') { throw 'ID tenant privado inválido.' }
        }
        foreach ($role in @($appRole, $controlRole)) {
            if ($role -notmatch '^[a-zA-Z0-9_]+$') { throw 'Rol técnico privado inválido.' }
        }
        $databaseState = (Invoke-DatabaseSql -Sql @"
SELECT
  (SELECT count(*) FROM flyway_schema_history WHERE NOT success)::text || '|' ||
  (SELECT max(version::int) FROM flyway_schema_history WHERE success)::text || '|' ||
  (SELECT count(*) FROM flyway_schema_history WHERE lower(script) LIKE '%demo%seed%' OR lower(script) LIKE '%seed%demo%')::text || '|' ||
  gestudio_multitenancy_health() || '|' ||
  (SELECT count(*) FROM pg_roles WHERE rolname='$appRole' AND NOT rolsuper AND NOT rolbypassrls)::text || '|' ||
  (SELECT count(*) FROM pg_roles WHERE rolname='$controlRole' AND NOT rolsuper AND NOT rolbypassrls)::text || '|' ||
  (SELECT count(*) FROM platform_admins pa JOIN usuarios u ON u.id=pa.usuario_id AND u.activo
     JOIN platform_mfa_credentials m ON m.usuario_id=u.id AND m.method='TOTP' AND m.verified_at IS NOT NULL AND m.revoked_at IS NULL
     WHERE pa.active)::text || '|' ||
  (SELECT count(*) FROM tenant_memberships tm JOIN bootstrap_ejecuciones b ON b.usuario_id=tm.usuario_id WHERE b.tipo='SUPERADMIN_INICIAL')::text || '|' ||
  (SELECT count(*) FROM tenants WHERE id IN ('$alphaId'::uuid,'$betaId'::uuid) AND status='ACTIVE')::text || '|' ||
  (SELECT count(*) FROM tenants)::text || '|' ||
  (SELECT count(*) FROM tenant_memberships WHERE tenant_id='$alphaId'::uuid AND status='ACTIVE')::text || '|' ||
  (SELECT count(*) FROM tenant_memberships WHERE tenant_id='$betaId'::uuid AND status='ACTIVE')::text || '|' ||
  (SELECT count(*) FROM alumnos WHERE tenant_id='$alphaId'::uuid)::text || '|' ||
  (SELECT count(*) FROM alumnos WHERE tenant_id='$betaId'::uuid)::text || '|' ||
  (SELECT count(*) FROM disciplinas WHERE tenant_id='$alphaId'::uuid)::text || '|' ||
  (SELECT count(*) FROM disciplinas WHERE tenant_id='$betaId'::uuid)::text || '|' ||
  (SELECT count(*) FROM stocks WHERE tenant_id='$alphaId'::uuid)::text || '|' ||
  (SELECT count(*) FROM stocks WHERE tenant_id='$betaId'::uuid)::text || '|' ||
  (SELECT count(*) FROM pagos WHERE tenant_id='$alphaId'::uuid)::text || '|' ||
  (SELECT count(*) FROM alumnos WHERE documento='49287134' AND tenant_id IN ('$alphaId'::uuid,'$betaId'::uuid))::text || '|' ||
  (SELECT count(*) FROM stocks WHERE codigo_barras='7790000000012' AND tenant_id IN ('$alphaId'::uuid,'$betaId'::uuid))::text || '|' ||
  (SELECT count(*) FROM platform_audit_events)::text || '|' ||
  (SELECT count(*) FROM platform_audit_events WHERE metadata::text ~* '(password|authorization|cookie|totp|recovery|secret|bearer|eyJ[A-Za-z0-9_-]*\.)')::text || '|' ||
  (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='public' AND c.relname IN ('alumnos','pagos','stocks') AND c.relrowsecurity AND c.relforcerowsecurity)::text || '|' ||
  (SELECT count(*) FROM usuarios u WHERE u.nombre_usuario IN ('platform.demo.admin','alpha.demo.admin','beta.demo.admin')
     AND u.activo AND u.contrasena ~ '^[$]2[aby][$]')::text || '|' ||
  (SELECT (NOT has_table_privilege('$controlRole','alumnos','SELECT'))::int)::text || '|' ||
  (SELECT (NOT has_table_privilege('$controlRole','platform_audit_events','UPDATE')
           AND NOT has_table_privilege('$controlRole','platform_audit_events','DELETE'))::int)::text || '|' ||
  (SELECT count(*) FROM stocks s LEFT JOIN (
      SELECT stock_id,sum(CASE WHEN tipo IN ('INGRESO','AJUSTE_POSITIVO','REVERSO') THEN cantidad
                               WHEN tipo IN ('VENTA','AJUSTE_NEGATIVO') THEN -cantidad ELSE 0 END) quantity
      FROM movimientos_stock GROUP BY stock_id
   ) book ON book.stock_id=s.id
   WHERE s.requiere_control_de_stock AND s.cantidad_actual<>coalesce(book.quantity,0))::text;
"@).Trim()
        $parts = $databaseState.Split('|')
        $minimumAlphaMemberships = if ($publicMode) { 7 } else { 6 }
        if ($parts.Count -ne 28 -or $parts[0] -cne '0' -or $parts[1] -cne [string]$latest -or
            $parts[2] -cne '0' -or $parts[3] -cne 'GREEN' -or $parts[4] -cne '1' -or
            $parts[5] -cne '1' -or $parts[6] -cne '1' -or $parts[7] -cne '0' -or
            $parts[8] -cne '2' -or $parts[9] -cne '2' -or [int]$parts[10] -lt $minimumAlphaMemberships -or
            $parts[11] -cne '1' -or [int]$parts[12] -lt 29 -or [int]$parts[13] -lt 1 -or
            [int]$parts[14] -lt 6 -or [int]$parts[15] -lt 1 -or [int]$parts[16] -lt 6 -or
            [int]$parts[17] -lt 1 -or [int]$parts[18] -lt 48 -or $parts[19] -cne '2' -or
            $parts[20] -cne '2' -or [int]$parts[21] -lt 11 -or $parts[22] -cne '0' -or
            $parts[23] -cne '3' -or $parts[24] -cne '3' -or $parts[25] -cne '1' -or
            $parts[26] -cne '1' -or $parts[27] -cne '0') {
            $reasons.Add('Flyway, RLS, plataforma, tenants, memberships, datasets o auditoría no cumplen el contrato.')
        }

        if ($publicMode) {
            $publicDatabaseState = (Invoke-DatabaseSql -Sql @"
SELECT
  (SELECT count(*) FROM usuarios u
     WHERE lower(u.nombre_usuario)='$publicUsername' AND u.activo
       AND u.contrasena ~ '^[$]2[aby][$]')::text || '|' ||
  (SELECT count(*) FROM tenant_memberships m JOIN usuarios u ON u.id=m.usuario_id
     WHERE lower(u.nombre_usuario)='$publicUsername' AND m.tenant_id='$alphaId'::uuid
       AND m.status='ACTIVE')::text || '|' ||
  (SELECT count(*) FROM tenant_memberships m JOIN usuarios u ON u.id=m.usuario_id
     WHERE lower(u.nombre_usuario)='$publicUsername' AND m.tenant_id<>'$alphaId'::uuid)::text || '|' ||
  (SELECT count(*) FROM tenant_membership_roles mr
     JOIN tenant_memberships m ON m.id=mr.membership_id
     JOIN usuarios u ON u.id=m.usuario_id
     WHERE lower(u.nombre_usuario)='$publicUsername' AND m.tenant_id='$alphaId'::uuid)::text || '|' ||
  (SELECT count(*) FROM tenant_membership_roles mr
     JOIN tenant_memberships m ON m.id=mr.membership_id
     JOIN usuarios u ON u.id=m.usuario_id
     JOIN roles r ON r.id=mr.role_id AND r.tenant_id=mr.tenant_id
     WHERE lower(u.nombre_usuario)='$publicUsername' AND m.tenant_id='$alphaId'::uuid
       AND r.codigo='$publicRoleCode' AND r.activo AND NOT r.sistema AND r.editable)::text || '|' ||
  (SELECT count(*) FROM rol_permisos rp JOIN roles r ON r.id=rp.rol_id
     WHERE r.tenant_id='$alphaId'::uuid AND r.codigo='$publicRoleCode')::text || '|' ||
  (SELECT count(*) FROM rol_permisos rp
     JOIN roles r ON r.id=rp.rol_id JOIN permisos p ON p.id=rp.permiso_id
     WHERE r.tenant_id='$alphaId'::uuid AND r.codigo='$publicRoleCode'
       AND p.codigo NOT IN (
         'PERM_APP_ACCESO','PERM_ALUMNOS_LEER','PERM_INSCRIPCIONES_LEER',
         'PERM_DISCIPLINAS_LEER','PERM_PROFESORES_LEER','PERM_ASISTENCIAS_LEER',
         'PERM_PAGOS_LEER','PERM_CAJA_LEER','PERM_STOCK_LEER',
         'PERM_REPORTES_LEER','PERM_CONFIG_LEER'))::text || '|' ||
  (SELECT count(*) FROM platform_admins pa JOIN usuarios u ON u.id=pa.usuario_id
     WHERE lower(u.nombre_usuario)='$publicUsername')::text || '|' ||
  (SELECT count(*) FROM platform_mfa_credentials m JOIN usuarios u ON u.id=m.usuario_id
     WHERE lower(u.nombre_usuario)='$publicUsername')::text || '|' ||
  (SELECT count(*) FROM alumnos
     WHERE tenant_id='$alphaId'::uuid AND apellido='Alpha E2E d3a010ca1001')::text || '|' ||
  (SELECT count(*) FROM alumnos
     WHERE tenant_id='$betaId'::uuid AND apellido='Beta E2E d3a010ca1001'
       AND email='beta.alumno@demo.local')::text;
"@).Trim()
            $publicParts = $publicDatabaseState.Split('|')
            if ($publicParts.Count -ne 11 -or $publicParts[0] -cne '1' -or
                $publicParts[1] -cne '1' -or $publicParts[2] -cne '0' -or
                $publicParts[3] -cne '1' -or $publicParts[4] -cne '1' -or
                $publicParts[5] -cne '11' -or $publicParts[6] -cne '0' -or
                $publicParts[7] -cne '0' -or $publicParts[8] -cne '0' -or
                $publicParts[9] -cne '1' -or $publicParts[10] -cne '1') {
                $reasons.Add('La identidad promocional no cumple roles, permisos, aislamiento o separación de plataforma.')
            }
        }

        $tenantIsolation = ((Invoke-DatabaseSql -Sql @"
SET ROLE "$appRole";
SELECT set_config('app.current_tenant_id','$alphaId',false);
SELECT count(*)::text || '|' || count(*) FILTER (WHERE tenant_id='$betaId'::uuid)::text FROM alumnos;
RESET ROLE;
"@) -split '[\r\n]+' | Where-Object { $_ -match '^[0-9]+\|[0-9]+$' } | Select-Object -Last 1)
        if ($tenantIsolation -notmatch '^(?<alpha>[1-9][0-9]*)\|0$') {
            $reasons.Add('La lectura con runtime Alpha no quedó aislada por RLS.')
        }

        $logs = Invoke-Compose -Arguments @('logs', '--no-color', '--tail', '1000', 'db', 'backend', 'frontend') -Capture
        foreach ($secret in $secretValues) {
            if (-not [string]::IsNullOrEmpty($secret) -and $logs.Contains($secret, [StringComparison]::Ordinal)) {
                $reasons.Add('Los logs contienen material secreto conocido.')
                break
            }
        }
    }
    catch { $reasons.Add((ConvertTo-SafeText $_.Exception.Message)) }

    Write-Host "Frontend: http://127.0.0.1:$frontendPort"
    Write-Host "Backend:  http://127.0.0.1:$backendPort"
    Write-Host "Control:  http://127.0.0.1:$frontendPort/platform/login"
    Write-Host "Proyecto: $project"
    Write-Host "Credenciales privadas: $credentialManifest"
    if ($reasons.Count -eq 0) {
        Write-Host 'Demo disponible: SÍ' -ForegroundColor Green
        Write-Host 'STATUS: PASS'
        return $true
    }
    Write-Host 'Demo disponible: NO' -ForegroundColor Red
    $reasons | Select-Object -Unique | ForEach-Object { Write-Host "- $_" }
    Write-Host 'STATUS: FAIL'
    return $false
}

function Assert-PortsAvailable {
    foreach ($port in @($databasePort, $backendPort, $frontendPort)) {
        $listener = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
        if ($listener) { throw "El puerto loopback $port ya está ocupado." }
    }
}

function Invoke-Start {
    [void](Assert-LocalDockerTarget)
    [void](Invoke-Native -FilePath 'docker' -Arguments @('version', '--format', '{{.Server.Version}}') -Capture)
    [void](Invoke-Native -FilePath 'docker' -Arguments @('compose', 'version', '--short') -Capture)
    $resources = Get-ProjectResources
    $freshState = -not (Test-Path -LiteralPath $stateRoot)
    if ($freshState) {
        if ($resources.Containers.Count -ne 0 -or $resources.Volumes.Count -ne 0 -or $resources.Networks.Count -ne 0) {
            throw 'Existen recursos demo sin su configuración privada; use Reset con confirmación explícita.'
        }
        Assert-PortsAvailable
        [void](Invoke-Native -FilePath 'pwsh' -Arguments @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $runnerPath,
            '-PersistentDemo', '-StateRoot', $stateRoot,
            '-PersistentDatabasePort', [string]$databasePort,
            '-PersistentBackendPort', [string]$backendPort,
            '-PersistentFrontendPort', [string]$frontendPort
        ))
        Invoke-AlphaSeed
        Invoke-BetaSeed
        Write-FixtureState
    }
    else {
        foreach ($required in @($envFile, $portsOverride, $credentialManifest, $recoveryCodes)) {
            if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
                throw 'La configuración persistente está incompleta; use Reset con confirmación explícita.'
            }
        }
        $running = $resources.Containers.Count -gt 0
        if (-not $running) { Assert-PortsAvailable }
        Update-BuildMetadata
        [void](Invoke-Compose -Arguments @('up', '-d', '--wait', '--wait-timeout', '120', 'db'))
        if (-not (Test-FixtureStateCurrent)) {
            Write-Host 'Cambió el contrato del fixture; se reaplica de forma idempotente.'
            Invoke-AlphaSeed
            Invoke-BetaSeed
            Write-FixtureState
        }
    }

    $manifest = Read-CredentialManifest
    $publicDemo = Get-PublicDemoConfiguration -Manifest $manifest
    $pendingPassword = $null
    if (-not [string]::IsNullOrWhiteSpace($PublicOrigin)) {
        $origin = Normalize-PublicOrigin -Origin $PublicOrigin
        if ($null -eq $publicDemo) {
            $password = New-PublicPassword
            $proxyToken = New-CryptographicSecret -Bytes 32
            Add-Secret $proxyToken
            $publicDemo = Set-PublicDemoConfiguration -Manifest $manifest -Origin $origin `
                -Password $password -ProxyToken $proxyToken
        }
        elseif ([string]$publicDemo.pagesOrigin -cne $origin) {
            $publicDemo = Set-PublicDemoConfiguration -Manifest $manifest -Origin $origin `
                -Password ([string]$publicDemo.password) -ProxyToken ([string]$publicDemo.proxyToken)
        }
    }
    if ($RotatePublicCredential) {
        if ($null -eq $publicDemo) {
            throw 'RotatePublicCredential exige una demo pública existente o PublicOrigin.'
        }
        $pendingPassword = New-PublicPassword
    }

    if ($null -ne $publicDemo) {
        Set-PublicEnvironment -PublicDemo $publicDemo
        Update-BuildMetadata
    }
    if (-not $freshState -or $null -ne $publicDemo) {
        [void](Invoke-Compose -Arguments @(
            'up', '-d', '--build', '--force-recreate', '--wait', '--wait-timeout', '420'
        ))
    }
    if ($null -ne $publicDemo) {
        Invoke-PublicFixtureConvergence -Manifest $manifest -PublicDemo $publicDemo `
            -PasswordOverride $pendingPassword
        if (-not [string]::IsNullOrWhiteSpace($pendingPassword)) {
            $manifest = Read-CredentialManifest
            $persisted = Get-PublicDemoConfiguration -Manifest $manifest
            $publicDemo = Set-PublicDemoConfiguration -Manifest $manifest `
                -Origin ([string]$persisted.pagesOrigin) -Password $pendingPassword `
                -ProxyToken ([string]$persisted.proxyToken)
        }
    }
    if (-not (Invoke-Status)) { throw 'El Start terminó con STATUS fallido.' }
}

function Invoke-Stop {
    [void](Assert-LocalDockerTarget)
    if (-not (Test-Path -LiteralPath $envFile -PathType Leaf)) {
        Write-Host 'La demo no está inicializada.'
        return
    }
    [void](Invoke-Compose -Arguments @('down', '--remove-orphans'))
    Write-Host 'Demo detenida; volúmenes, configuración, credenciales y datos fueron conservados.'
}

function Remove-ExactStateRoot {
    $expected = [IO.Path]::GetFullPath((Join-Path $localData 'Gestudio\gestudio-demo-local'))
    if ([IO.Path]::GetFullPath($stateRoot) -cne $expected -or (Split-Path $expected -Leaf) -cne $project) {
        throw 'Se rechazó eliminar un directorio fuera del scope exacto de la demo.'
    }
    if (Test-Path -LiteralPath $expected) { Remove-Item -LiteralPath $expected -Recurse -Force }
}

function Invoke-Reset {
    if (-not $ConfirmReset) { throw 'Reset exige -ConfirmReset.' }
    [void](Assert-LocalDockerTarget)
    if (Test-Path -LiteralPath $envFile -PathType Leaf) {
        [void](Invoke-Compose -Arguments @('down', '--volumes', '--remove-orphans'))
    }
    else {
        $resources = Get-ProjectResources
        if ($resources.Containers.Count -ne 0 -or $resources.Volumes.Count -ne 0 -or $resources.Networks.Count -ne 0) {
            throw 'Hay recursos demo sin configuración verificable; se rechaza un borrado ambiguo.'
        }
    }
    Remove-ExactStateRoot
    Invoke-Start
}

try {
    switch ($Action) {
        'Start' { Invoke-Start }
        'Status' { if (-not (Invoke-Status)) { exit 1 } }
        'Stop' { Invoke-Stop }
        'Reset' { Invoke-Reset }
    }
}
finally {
    $secretValues.Clear()
}
