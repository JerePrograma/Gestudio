Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:startedAt = [DateTime]::UtcNow
$script:rawArguments = @($args)
$script:logPath = $null
$script:secretValues = @()
$script:environmentBackup = @{}
$script:environmentApplied = $false
$script:mutex = $null
$script:mutexOwned = $false

function Show-DeploymentHelp {
    @'
Gestudio - despliegue idempotente para Windows

Sintaxis:
  deploy.cmd
  deploy.cmd --dry-run
  deploy.cmd --verify-only
  deploy.cmd --help

Modos:
  sin argumentos  Preflight, backup si cambia Flyway, build convergente,
                  despliegue, health checks y estado atomico.
  --dry-run       Valida y calcula el plan sin crear configuracion ni recursos.
  --verify-only   Verifica el despliegue existente sin construir ni modificarlo.
  --help          Muestra esta ayuda sin requerir Docker.

Requisitos:
  Windows 10/11, PowerShell 5.1 o 7, Docker Desktop ya iniciado,
  Docker CLI y Docker Compose v2.

Archivos locales ignorados por Git:
  .gestudio-deploy/config/deploy.env
  .gestudio-deploy/state/deployment.json
  .gestudio-deploy/logs/
  .gestudio-deploy/backups/

Backups:
  Se usa scripts/ops/backup-postgres.ps1 antes de una actualizacion que
  cambie las migraciones. No se restaura automaticamente.

Idempotencia:
  Un fingerprint igual y un stack sano no reconstruyen imagenes, no recrean
  contenedores, no ejecutan migraciones y no rotan secretos.

Codigos de salida:
  0 correcto; 2 argumento/preflight; 3 configuracion; 4 Docker/Compose;
  5 build/migracion; 6 health; 7 verificacion funcional; 8 lock ocupado;
  9 backup; 10 drift no reparable de forma segura.
'@ | Write-Host
}

function Get-DeploymentMode {
    $selected = 'deploy'
    foreach ($argument in $script:rawArguments) {
        $candidate = switch -CaseSensitive ($argument) {
            '--dry-run' { 'dry-run' }
            '--verify-only' { 'verify-only' }
            '--help' { 'help' }
            default { throw "Argumento invalido: $argument" }
        }
        if ($selected -ne 'deploy' -or $candidate -eq 'deploy') {
            throw 'Use un solo modo por ejecucion.'
        }
        $selected = $candidate
    }
    return $selected
}

function ConvertTo-SanitizedText {
    param([AllowNull()][string] $Text)

    if ($null -eq $Text) { return '' }
    $sanitized = $Text -replace '(?i)((?:password|secret|token|credential|authorization)[^=:\s]*\s*[=:]\s*)\S+', '$1<redacted>'
    foreach ($secret in $script:secretValues) {
        if (-not [string]::IsNullOrWhiteSpace($secret)) {
            $sanitized = $sanitized -replace [regex]::Escape($secret), '<redacted>'
        }
    }
    return $sanitized
}

function Write-Status {
    param(
        [Parameter(Mandatory)][ValidateSet('INFO', 'WARN', 'ERROR', 'PASS')][string] $Level,
        [Parameter(Mandatory)][string] $Message
    )

    $line = '{0} [{1}] {2}' -f [DateTime]::UtcNow.ToString('o'), $Level, (ConvertTo-SanitizedText $Message)
    Write-Host $line
    if (-not [string]::IsNullOrWhiteSpace($script:logPath)) {
        [IO.File]::AppendAllText($script:logPath, $line + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    }
}

function New-DeployFailure {
    param([Parameter(Mandatory)][string] $Message, [Parameter(Mandatory)][int] $ExitCode)

    $exception = New-Object System.InvalidOperationException -ArgumentList $Message
    $exception.Data['ExitCode'] = $ExitCode
    return $exception
}

function Invoke-CheckedNative {
    param(
        [Parameter(Mandatory)][string] $FilePath,
        [Parameter(Mandatory)][string[]] $Arguments,
        [Parameter(Mandatory)][int] $FailureExitCode,
        [switch] $Capture
    )

    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $FilePath @Arguments 2>&1)
        $nativeExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    $text = ($output | ForEach-Object { $_.ToString() }) -join "`n"
    if ($nativeExitCode -ne 0) {
        $tail = (($text -split "`r?`n") | Select-Object -Last 60) -join "`n"
        throw (New-DeployFailure -Message "$FilePath fallo con codigo ${nativeExitCode}: $tail" -ExitCode $FailureExitCode)
    }
    if ($Capture) { return $text.Trim() }
    if (-not [string]::IsNullOrWhiteSpace($text)) { Write-Host (ConvertTo-SanitizedText $text) }
}

function Get-Sha256Text {
    param([Parameter(Mandatory)][string] $Text)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function New-SecureHexSecret {
    param([int] $Bytes = 32)

    $buffer = New-Object byte[] $Bytes
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($buffer) } finally { $rng.Dispose() }
    return ([BitConverter]::ToString($buffer)).Replace('-', '').ToLowerInvariant()
}

function Read-EnvValues {
    param([Parameter(Mandatory)][string] $Path)

    $values = @{}
    foreach ($line in [IO.File]::ReadAllLines([IO.Path]::GetFullPath($Path))) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) { continue }
        $separator = $line.IndexOf('=')
        if ($separator -lt 1) { throw (New-DeployFailure -Message "Linea invalida en $Path" -ExitCode 3) }
        $name = $line.Substring(0, $separator).Trim()
        if ($name -notmatch '^[A-Z][A-Z0-9_]*$' -or $values.ContainsKey($name)) {
            throw (New-DeployFailure -Message "Variable invalida o duplicada en ${Path}: $name" -ExitCode 3)
        }
        $values[$name] = $line.Substring($separator + 1)
    }
    return $values
}

function Write-AtomicText {
    param([Parameter(Mandatory)][string] $Path, [Parameter(Mandatory)][string] $Content)

    $directory = Split-Path $Path -Parent
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $temporary = Join-Path $directory ('.tmp-' + [Guid]::NewGuid().ToString('N'))
    $backup = Join-Path $directory ('.bak-' + [Guid]::NewGuid().ToString('N'))
    $encoding = [Text.UTF8Encoding]::new($false)
    try {
        [IO.File]::WriteAllText($temporary, $Content, $encoding)
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            [IO.File]::Replace($temporary, $Path, $backup, $true)
        }
        else {
            [IO.File]::Move($temporary, $Path)
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force }
        if (Test-Path -LiteralPath $backup -PathType Leaf) { Remove-Item -LiteralPath $backup -Force }
    }
}

function Get-TemplateContent {
    param([Parameter(Mandatory)][string] $TemplatePath, [switch] $DryRun)

    $secretKeys = @(
        'POSTGRES_PASSWORD', 'POSTGRES_APP_PASSWORD', 'JWT_SECRET',
        'APP_OBSERVABILITY_METRICS_TOKEN', 'APP_BOOTSTRAP_SUPERADMIN_PASSWORD'
    )
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($line in [IO.File]::ReadAllLines($TemplatePath)) {
        $updated = $line
        $separator = $line.IndexOf('=')
        if ($separator -gt 0) {
            $name = $line.Substring(0, $separator).Trim()
            if ($name -in $secretKeys -and [string]::IsNullOrEmpty($line.Substring($separator + 1))) {
                $value = if ($DryRun) { 'dry-run-not-persisted-' + ('0' * 40) } else { New-SecureHexSecret }
                $updated = "$name=$value"
            }
        }
        $lines.Add($updated)
    }
    return ($lines -join [Environment]::NewLine) + [Environment]::NewLine
}

function Ensure-EffectiveConfiguration {
    param(
        [Parameter(Mandatory)][string] $TemplatePath,
        [Parameter(Mandatory)][string] $EffectivePath
    )

    $added = New-Object System.Collections.Generic.List[string]
    if (-not (Test-Path -LiteralPath $EffectivePath -PathType Leaf)) {
        Write-AtomicText -Path $EffectivePath -Content (Get-TemplateContent -TemplatePath $TemplatePath)
        return [pscustomobject]@{ Created = $true; Added = @() }
    }

    $effective = Read-EnvValues -Path $EffectivePath
    $template = Read-EnvValues -Path $TemplatePath
    $content = [IO.File]::ReadAllText($EffectivePath).TrimEnd("`r", "`n")
    foreach ($name in $template.Keys | Sort-Object) {
        if ($effective.ContainsKey($name)) { continue }
        $value = $template[$name]
        if ([string]::IsNullOrEmpty($value) -and $name -in @(
            'POSTGRES_PASSWORD', 'POSTGRES_APP_PASSWORD', 'JWT_SECRET',
            'APP_OBSERVABILITY_METRICS_TOKEN', 'APP_BOOTSTRAP_SUPERADMIN_PASSWORD')) {
            $value = New-SecureHexSecret
        }
        $content += [Environment]::NewLine + "$name=$value"
        $added.Add($name)
    }
    if ($added.Count -gt 0) {
        Write-AtomicText -Path $EffectivePath -Content ($content + [Environment]::NewLine)
    }
    return [pscustomobject]@{ Created = $false; Added = @($added) }
}

function Assert-Configuration {
    param([Parameter(Mandatory)][hashtable] $Configuration)

    $required = @(
        'COMPOSE_PROJECT_NAME', 'POSTGRES_DB', 'POSTGRES_USER', 'POSTGRES_PASSWORD',
        'POSTGRES_APP_USER', 'POSTGRES_APP_PASSWORD', 'POSTGRES_PORT', 'BACKEND_PORT',
        'FRONTEND_PORT', 'BACKEND_IMAGE', 'FRONTEND_IMAGE', 'VITE_API_BASE_URL',
        'SPRING_PROFILES_ACTIVE', 'JWT_SECRET', 'JWT_ISSUER', 'APP_CORS_ALLOWED_ORIGINS',
        'APP_OBSERVABILITY_METRICS_TOKEN', 'APP_BOOTSTRAP_SUPERADMIN_ENABLED',
        'APP_BOOTSTRAP_SUPERADMIN_USERNAME', 'APP_BOOTSTRAP_SUPERADMIN_PASSWORD'
    )
    foreach ($name in $required) {
        if (-not $Configuration.ContainsKey($name) -or [string]::IsNullOrWhiteSpace($Configuration[$name]) -or
            $Configuration[$name] -match '^<.+>$') {
            throw (New-DeployFailure -Message "Configuracion incompleta: $name" -ExitCode 3)
        }
    }
    if ($Configuration['COMPOSE_PROJECT_NAME'] -notmatch '^[a-z0-9][a-z0-9_-]{2,62}$' -or
        $Configuration['COMPOSE_PROJECT_NAME'] -eq 'gestudio-remote-demo') {
        throw (New-DeployFailure -Message 'COMPOSE_PROJECT_NAME es invalido o esta reservado.' -ExitCode 3)
    }
    if ($Configuration['POSTGRES_USER'] -ceq $Configuration['POSTGRES_APP_USER']) {
        throw (New-DeployFailure -Message 'Los usuarios migrador y runtime deben ser distintos.' -ExitCode 3)
    }
    foreach ($name in @('POSTGRES_PASSWORD', 'POSTGRES_APP_PASSWORD', 'JWT_SECRET',
        'APP_OBSERVABILITY_METRICS_TOKEN', 'APP_BOOTSTRAP_SUPERADMIN_PASSWORD')) {
        $bytes = [Text.Encoding]::UTF8.GetByteCount($Configuration[$name])
        if ($bytes -lt 16 -or ($name -eq 'APP_BOOTSTRAP_SUPERADMIN_PASSWORD' -and $bytes -gt 72)) {
            throw (New-DeployFailure -Message "El secreto $name no cumple la longitud minima." -ExitCode 3)
        }
    }
    if ($Configuration['APP_BOOTSTRAP_SUPERADMIN_ENABLED'] -cne 'false') {
        throw (New-DeployFailure -Message 'El bootstrap debe quedar deshabilitado en la configuracion persistente.' -ExitCode 3)
    }
    if ($Configuration['SPRING_PROFILES_ACTIVE'] -cne 'dev') {
        throw (New-DeployFailure -Message 'Este launcher local de Windows requiere SPRING_PROFILES_ACTIVE=dev.' -ExitCode 3)
    }
    foreach ($name in @('POSTGRES_PORT', 'BACKEND_PORT', 'FRONTEND_PORT')) {
        $port = 0
        if (-not [int]::TryParse($Configuration[$name], [ref]$port) -or $port -lt 1 -or $port -gt 65535) {
            throw (New-DeployFailure -Message "Puerto invalido: $name" -ExitCode 3)
        }
    }
    $ports = @($Configuration['POSTGRES_PORT'], $Configuration['BACKEND_PORT'], $Configuration['FRONTEND_PORT'])
    if (@($ports | Select-Object -Unique).Count -ne 3) {
        throw (New-DeployFailure -Message 'Los tres puertos deben ser distintos.' -ExitCode 3)
    }
    $backendEndpoint = "http://127.0.0.1:$($Configuration['BACKEND_PORT'])/api"
    $frontendOrigin = "http://127.0.0.1:$($Configuration['FRONTEND_PORT'])"
    if ($Configuration['VITE_API_BASE_URL'] -cne $backendEndpoint -or
        $Configuration['APP_CORS_ALLOWED_ORIGINS'].Split(',') -notcontains $frontendOrigin) {
        throw (New-DeployFailure -Message 'VITE_API_BASE_URL o CORS no coinciden con los puertos persistidos.' -ExitCode 3)
    }
}

function Set-ConfigurationEnvironment {
    param([Parameter(Mandatory)][hashtable] $Configuration, [Parameter(Mandatory)][hashtable] $DynamicValues)

    foreach ($entry in @($Configuration.GetEnumerator()) + @($DynamicValues.GetEnumerator())) {
        $name = [string]$entry.Key
        if (-not $script:environmentBackup.ContainsKey($name)) {
            $script:environmentBackup[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        }
        [Environment]::SetEnvironmentVariable($name, [string]$entry.Value, 'Process')
    }
    $script:environmentApplied = $true
}

function Restore-ConfigurationEnvironment {
    if (-not $script:environmentApplied) { return }
    foreach ($entry in $script:environmentBackup.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable([string]$entry.Key, $entry.Value, 'Process')
    }
    $script:environmentApplied = $false
}

function Get-InputHash {
    param([Parameter(Mandatory)][string] $RepositoryRoot, [Parameter(Mandatory)][string[]] $RelativeRoots)

    $records = New-Object System.Collections.Generic.List[string]
    foreach ($relativeRoot in $RelativeRoots) {
        $absolute = Join-Path $RepositoryRoot $relativeRoot
        if (-not (Test-Path -LiteralPath $absolute)) { continue }
        $item = Get-Item -LiteralPath $absolute
        $files = if ($item.PSIsContainer) { @(Get-ChildItem -LiteralPath $absolute -Recurse -File) } else { @($item) }
        foreach ($file in $files) {
            if ($file.FullName -match '[\\/](target|node_modules|dist)[\\/]') { continue }
            $relative = $file.FullName.Substring($RepositoryRoot.TrimEnd('\').Length).TrimStart('\', '/').Replace('\', '/')
            $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            $records.Add("$relative|$hash")
        }
    }
    return Get-Sha256Text -Text ((@($records | Sort-Object -Unique)) -join "`n")
}

function Get-NonSecretConfigurationHash {
    param([Parameter(Mandatory)][hashtable] $Configuration)

    $records = @(
        $Configuration.GetEnumerator() |
            Where-Object { $_.Key -notmatch '(?i)(PASSWORD|SECRET|TOKEN|CREDENTIAL|KEY)' } |
            Sort-Object Key |
            ForEach-Object { '{0}={1}' -f $_.Key, $_.Value }
    )
    return Get-Sha256Text -Text ($records -join "`n")
}

function Get-DeploymentFingerprints {
    param([Parameter(Mandatory)][string] $RepositoryRoot, [Parameter(Mandatory)][hashtable] $Configuration, [Parameter(Mandatory)][string] $Commit)

    $backend = Get-InputHash -RepositoryRoot $RepositoryRoot -RelativeRoots @('backend', 'scripts\db')
    $frontend = Get-InputHash -RepositoryRoot $RepositoryRoot -RelativeRoots @('frontend')
    $compose = Get-InputHash -RepositoryRoot $RepositoryRoot -RelativeRoots @('docker-compose.yml')
    $migrations = Get-InputHash -RepositoryRoot $RepositoryRoot -RelativeRoots @('backend\src\main\resources\db\migration')
    $configurationHash = Get-NonSecretConfigurationHash -Configuration $Configuration
    $overall = Get-Sha256Text -Text (@($Commit, $backend, $frontend, $compose, $migrations, $configurationHash) -join "`n")
    return [pscustomobject]@{
        overall = $overall
        backend = $backend
        frontend = $frontend
        compose = $compose
        migrations = $migrations
        configuration = $configurationHash
    }
}

function Invoke-Compose {
    param([Parameter(Mandatory)][string[]] $Arguments, [switch] $Capture, [int] $FailureExitCode = 5)

    $prefix = @('compose', '-f', $script:composeFile, '--env-file', $script:configPath, '-p', $script:projectName)
    return Invoke-CheckedNative -FilePath 'docker' -Arguments ($prefix + $Arguments) `
        -FailureExitCode $FailureExitCode -Capture:$Capture
}

function Test-ImageExists {
    param([Parameter(Mandatory)][string] $Image)

    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $null = @(& docker image inspect $Image 2>&1)
        $code = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousPreference }
    return $code -eq 0
}

function Get-ProjectResourceSnapshot {
    param([Parameter(Mandatory)][string] $ProjectName)

    $containers = Invoke-CheckedNative -FilePath 'docker' -Arguments @(
        'ps', '-a', '--filter', "label=com.docker.compose.project=$ProjectName", '-q'
    ) -FailureExitCode 4 -Capture
    $volumes = Invoke-CheckedNative -FilePath 'docker' -Arguments @(
        'volume', 'ls', '--filter', "label=com.docker.compose.project=$ProjectName", '-q'
    ) -FailureExitCode 4 -Capture
    $networks = Invoke-CheckedNative -FilePath 'docker' -Arguments @(
        'network', 'ls', '--filter', "label=com.docker.compose.project=$ProjectName", '-q'
    ) -FailureExitCode 4 -Capture

    return [pscustomobject]@{
        containers = @(($containers -split "`r?`n") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        volumes = @(($volumes -split "`r?`n") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        networks = @(($networks -split "`r?`n") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
}

function Test-PortListening {
    param([Parameter(Mandatory)][int] $Port)

    $listeners = [Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()
    return @($listeners | Where-Object { $_.Port -eq $Port }).Count -gt 0
}

function Assert-PortsAvailable {
    param([Parameter(Mandatory)][hashtable] $Configuration, [Parameter(Mandatory)][string] $ProjectName)

    $protected = Invoke-CheckedNative -FilePath 'docker' -Arguments @(
        'ps', '-a', '--filter', 'label=com.docker.compose.project=gestudio-remote-demo', '-q'
    ) -FailureExitCode 4 -Capture
    $protectedPorts = ''
    if (-not [string]::IsNullOrWhiteSpace($protected)) {
        $protectedPorts = Invoke-CheckedNative -FilePath 'docker' -Arguments (@(
            'inspect', '--format', '{{json .HostConfig.PortBindings}}'
        ) + @($protected -split "`r?`n")) -FailureExitCode 4 -Capture
    }

    foreach ($name in @('POSTGRES_PORT', 'BACKEND_PORT', 'FRONTEND_PORT')) {
        $port = [int]$Configuration[$name]
        if ($protectedPorts -match ('"HostPort":"' + [regex]::Escape([string]$port) + '"')) {
            throw (New-DeployFailure -Message "El puerto $port pertenece a gestudio-remote-demo." -ExitCode 10)
        }
        if (-not (Test-PortListening -Port $port)) { continue }
        $owned = Invoke-CheckedNative -FilePath 'docker' -Arguments @(
            'ps', '--filter', "publish=$port", '--filter', "label=com.docker.compose.project=$ProjectName", '-q'
        ) -FailureExitCode 4 -Capture
        if ([string]::IsNullOrWhiteSpace($owned)) {
            throw (New-DeployFailure -Message "El puerto $port esta ocupado por otro proceso o proyecto." -ExitCode 10)
        }
    }
}

function Get-BootstrapClaimCount {
    param([Parameter(Mandatory)][string] $DatabaseContainer)

    $exists = Invoke-DeploymentSql -ContainerId $DatabaseContainer -Role migration `
        -Sql "SELECT coalesce(to_regclass('public.bootstrap_ejecuciones')::text, '');"
    if ([string]::IsNullOrWhiteSpace($exists)) { return 0 }
    return [int](Invoke-DeploymentSql -ContainerId $DatabaseContainer -Role migration `
        -Sql "SELECT count(*) FROM bootstrap_ejecuciones WHERE tipo = 'SUPERADMIN_INICIAL';")
}

function Invoke-VerifiedBackup {
    param([Parameter(Mandatory)][string] $OutputDirectory)

    [IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
    $before = @(Get-ChildItem -LiteralPath $OutputDirectory -Directory | ForEach-Object Name)
    Write-Status INFO 'Creando backup pre-upgrade con el script operativo existente'
    try {
        $output = @(& $script:backupScript -ComposeFile $script:composeFile -EnvFile $script:configPath `
            -ProjectName $script:projectName -OutputDirectory $OutputDirectory -StopBackend 2>&1)
        $scriptExit = $LASTEXITCODE
        if ($scriptExit -ne 0) { throw "backup-postgres.ps1 devolvio $scriptExit" }
    }
    catch {
        throw (New-DeployFailure -Message "Backup fallido: $($_.Exception.Message)" -ExitCode 9)
    }
    $created = @(
        Get-ChildItem -LiteralPath $OutputDirectory -Directory |
            Where-Object { $_.Name -notin $before } |
            Sort-Object LastWriteTimeUtc -Descending
    )
    if ($created.Count -ne 1 -or
        -not (Test-Path -LiteralPath (Join-Path $created[0].FullName 'manifest.json') -PathType Leaf) -or
        -not (Test-Path -LiteralPath (Join-Path $created[0].FullName 'database.dump') -PathType Leaf)) {
        throw (New-DeployFailure -Message 'El backup no produjo un paquete completo y unico.' -ExitCode 9)
    }
    Write-Status PASS "Backup validado: $($created[0].FullName)"
    return $created[0].FullName
}

function Read-DeploymentState {
    param([Parameter(Mandatory)][string] $Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { return ConvertFrom-Json ([IO.File]::ReadAllText($Path)) }
    catch { throw (New-DeployFailure -Message 'El estado persistido no contiene JSON valido.' -ExitCode 10) }
}

function Write-DeploymentState {
    param([Parameter(Mandatory)][string] $Path, [Parameter(Mandatory)][object] $State)

    $json = $State | ConvertTo-Json -Depth 10
    try { $null = ConvertFrom-Json $json } catch { throw 'No se pudo validar el estado antes de escribirlo.' }
    Write-AtomicText -Path $Path -Content ($json + [Environment]::NewLine)
}

$exitCode = 0
$temporaryConfig = $null
try {
    $mode = Get-DeploymentMode
    if ($mode -eq 'help') { Show-DeploymentHelp; exit 0 }

    if ($env:OS -cne 'Windows_NT' -or $PSVersionTable.PSVersion -lt [Version]'5.1') {
        throw (New-DeployFailure -Message 'Se requiere Windows y PowerShell 5.1 o posterior.' -ExitCode 2)
    }

    $repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
    $script:composeFile = Join-Path $repoRoot 'docker-compose.yml'
    $templatePath = Join-Path $PSScriptRoot 'deploy.env.example'
    $verifyScript = Join-Path $PSScriptRoot 'verify-deployment.ps1'
    $script:backupScript = Join-Path $repoRoot 'scripts\ops\backup-postgres.ps1'
    $requiredPaths = @(
        $script:composeFile, $templatePath, $verifyScript, $script:backupScript,
        (Join-Path $repoRoot 'scripts\ops\restore-postgres.ps1'),
        (Join-Path $repoRoot 'backend\Dockerfile'), (Join-Path $repoRoot 'frontend\Dockerfile')
    )
    foreach ($requiredPath in $requiredPaths) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            throw (New-DeployFailure -Message "Falta el archivo requerido: $requiredPath" -ExitCode 2)
        }
    }
    . $verifyScript

    $stateRoot = if ([string]::IsNullOrWhiteSpace($env:GESTUDIO_DEPLOY_STATE_ROOT)) {
        Join-Path $repoRoot '.gestudio-deploy'
    }
    else {
        [IO.Path]::GetFullPath($env:GESTUDIO_DEPLOY_STATE_ROOT)
    }
    $script:configPath = Join-Path $stateRoot 'config\deploy.env'
    $effectiveConfigPath = $script:configPath
    $statePath = Join-Path $stateRoot 'state\deployment.json'
    $logsRoot = Join-Path $stateRoot 'logs'
    $backupsRoot = Join-Path $stateRoot 'backups'

    $projectProbePath = if (Test-Path -LiteralPath $script:configPath -PathType Leaf) { $script:configPath } else { $templatePath }
    $projectProbe = Read-EnvValues -Path $projectProbePath
    $script:projectName = $projectProbe['COMPOSE_PROJECT_NAME']
    if ([string]::IsNullOrWhiteSpace($script:projectName)) {
        throw (New-DeployFailure -Message 'No se pudo resolver COMPOSE_PROJECT_NAME.' -ExitCode 3)
    }
    $mutexHash = Get-Sha256Text -Text ($repoRoot.ToLowerInvariant() + '|' + $script:projectName)
    $mutexName = 'Local\GestudioDeploy-' + $mutexHash.Substring(0, 32)
    $script:mutex = [Threading.Mutex]::new($false, $mutexName)
    try { $script:mutexOwned = $script:mutex.WaitOne(0) }
    catch [Threading.AbandonedMutexException] { $script:mutexOwned = $true }
    if (-not $script:mutexOwned) {
        throw (New-DeployFailure -Message "Ya existe otro despliegue activo para '$($script:projectName)'." -ExitCode 8)
    }

    if ($env:GESTUDIO_DEPLOY_TEST_MODE -eq '1' -and -not [string]::IsNullOrWhiteSpace($env:GESTUDIO_DEPLOY_TEST_LOCK_DELAY_SECONDS)) {
        $delay = 0
        if ([int]::TryParse($env:GESTUDIO_DEPLOY_TEST_LOCK_DELAY_SECONDS, [ref]$delay) -and $delay -gt 0 -and $delay -le 30) {
            # ponytail: deterministic test-only delay; remove when Windows offers an inspectable named-mutex probe.
            Start-Sleep -Seconds $delay
        }
    }

    $gitDirectory = Join-Path $repoRoot '.git'
    $commit = 'unversioned-bundle'
    if (Test-Path -LiteralPath $gitDirectory) {
        $gitStatus = Invoke-CheckedNative -FilePath 'git' -Arguments @(
            '-C', $repoRoot, 'status', '--porcelain=v1', '--untracked-files=all'
        ) -FailureExitCode 2 -Capture
        if (-not [string]::IsNullOrWhiteSpace($gitStatus)) {
            throw (New-DeployFailure -Message 'Git no esta limpio; no se desplegara un arbol ambiguo.' -ExitCode 2)
        }
        $commit = Invoke-CheckedNative -FilePath 'git' -Arguments @('-C', $repoRoot, 'rev-parse', 'HEAD') `
            -FailureExitCode 2 -Capture
    }

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw (New-DeployFailure -Message 'Docker CLI no esta disponible; Docker Desktop no se iniciara automaticamente.' -ExitCode 4)
    }
    $null = Invoke-CheckedNative -FilePath 'docker' -Arguments @('version') -FailureExitCode 4 -Capture
    $null = Invoke-CheckedNative -FilePath 'docker' -Arguments @('info') -FailureExitCode 4 -Capture
    $composeVersion = Invoke-CheckedNative -FilePath 'docker' -Arguments @('compose', 'version') -FailureExitCode 4 -Capture
    $dockerContext = Invoke-CheckedNative -FilePath 'docker' -Arguments @('context', 'show') -FailureExitCode 4 -Capture

    $configResult = $null
    if ($mode -eq 'deploy') {
        $temporaryConfig = Join-Path ([IO.Path]::GetTempPath()) ('gestudio-deploy-' + [Guid]::NewGuid().ToString('N') + '.env')
        if (Test-Path -LiteralPath $effectiveConfigPath -PathType Leaf) {
            Copy-Item -LiteralPath $effectiveConfigPath -Destination $temporaryConfig
        }
        $configResult = Ensure-EffectiveConfiguration -TemplatePath $templatePath -EffectivePath $temporaryConfig
        $script:configPath = $temporaryConfig
    }
    elseif (-not (Test-Path -LiteralPath $script:configPath -PathType Leaf)) {
        if ($mode -eq 'verify-only') {
            throw (New-DeployFailure -Message 'No existe una configuracion desplegada para verificar.' -ExitCode 3)
        }
        $temporaryConfig = Join-Path ([IO.Path]::GetTempPath()) ('gestudio-dry-run-' + [Guid]::NewGuid().ToString('N') + '.env')
        [IO.File]::WriteAllText($temporaryConfig, (Get-TemplateContent -TemplatePath $templatePath -DryRun), [Text.UTF8Encoding]::new($false))
        $script:configPath = $temporaryConfig
    }

    $configuration = Read-EnvValues -Path $script:configPath
    Assert-Configuration -Configuration $configuration
    $script:projectName = $configuration['COMPOSE_PROJECT_NAME']
    $script:secretValues = @(
        $configuration['POSTGRES_PASSWORD'], $configuration['POSTGRES_APP_PASSWORD'],
        $configuration['JWT_SECRET'], $configuration['APP_OBSERVABILITY_METRICS_TOKEN'],
        $configuration['APP_BOOTSTRAP_SUPERADMIN_PASSWORD']
    )

    $fingerprints = Get-DeploymentFingerprints -RepositoryRoot $repoRoot -Configuration $configuration -Commit $commit
    $dynamic = @{
        VCS_REF = $commit
        COMPOSE_SHA = $fingerprints.compose
        BACKEND_SOURCE_SHA = $fingerprints.backend
        FRONTEND_SOURCE_SHA = $fingerprints.frontend
    }
    Set-ConfigurationEnvironment -Configuration $configuration -DynamicValues $dynamic
    $null = Invoke-Compose -Arguments @('config', '--quiet') -Capture -FailureExitCode 3
    Assert-PortsAvailable -Configuration $configuration -ProjectName $script:projectName

    if ($mode -eq 'deploy') {
        if ($configResult.Created -or $configResult.Added.Count -gt 0) {
            Write-AtomicText -Path $effectiveConfigPath -Content ([IO.File]::ReadAllText($temporaryConfig))
        }
        $script:configPath = $effectiveConfigPath
        [IO.Directory]::CreateDirectory($logsRoot) | Out-Null
        $script:logPath = Join-Path $logsRoot ('deploy-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ') + '-' + $PID + '.log')
        [IO.File]::WriteAllText($script:logPath, '', [Text.UTF8Encoding]::new($false))
    }
    Write-Status INFO "modo=$mode commit=$commit proyecto=$($script:projectName) contexto=$dockerContext compose=$composeVersion"
    Write-Status INFO "fingerprint=$($fingerprints.overall) puertos=$($configuration['POSTGRES_PORT'])/$($configuration['BACKEND_PORT'])/$($configuration['FRONTEND_PORT'])"
    if ($null -ne $configResult -and $configResult.Created) { Write-Status INFO 'Configuracion efectiva creada sin imprimir secretos' }
    if ($null -ne $configResult) {
        foreach ($addedName in $configResult.Added) { Write-Status INFO "Variable agregada a la configuracion: $addedName" }
    }

    if ($stateRoot.StartsWith($repoRoot, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $gitDirectory)) {
        $ignoreProbePath = Join-Path $stateRoot 'config\deploy.env'
        $relativeConfig = $ignoreProbePath.Substring($repoRoot.Length).TrimStart('\', '/')
        $null = Invoke-CheckedNative -FilePath 'git' -Arguments @('-C', $repoRoot, 'check-ignore', '--quiet', '--', $relativeConfig) `
            -FailureExitCode 3 -Capture
    }

    $previousState = Read-DeploymentState -Path $statePath
    $resourcesBefore = Get-ProjectResourceSnapshot -ProjectName $script:projectName
    $hasResources = $resourcesBefore.containers.Count -gt 0 -or $resourcesBefore.volumes.Count -gt 0 -or $resourcesBefore.networks.Count -gt 0

    $commitChanged = $null -ne $previousState -and [string]$previousState.commit -cne $commit
    $backendBuild = $null -eq $previousState -or $commitChanged -or [string]$previousState.backendFingerprint -cne $fingerprints.backend -or
        -not (Test-ImageExists -Image $configuration['BACKEND_IMAGE'])
    $frontendBuild = $null -eq $previousState -or $commitChanged -or [string]$previousState.frontendFingerprint -cne $fingerprints.frontend -or
        -not (Test-ImageExists -Image $configuration['FRONTEND_IMAGE'])
    $migrationChanged = $null -ne $previousState -and [string]$previousState.migrationFingerprint -cne $fingerprints.migrations
    $fingerprintChanged = $null -eq $previousState -or [string]$previousState.fingerprint -cne $fingerprints.overall

    if ($mode -eq 'dry-run') {
        Write-Status INFO ('Plan: configuracion={0}; backup={1}; build={2}; compose-up={3}; verificacion=si' -f `
            ($(if (Test-Path -LiteralPath (Join-Path $stateRoot 'config\deploy.env')) { 'reutilizar' } else { 'crear' })),
            ($(if ($migrationChanged -and $hasResources) { 'si' } else { 'no' })),
            ((@($(if ($backendBuild) { 'backend' }), $(if ($frontendBuild) { 'frontend' })) | Where-Object { $_ }) -join ','),
            ($(if ($fingerprintChanged) { 'si' } else { 'solo ante drift seguro' })))
        Write-Status PASS 'Dry run finalizado sin mutaciones'
        exit 0
    }

    if ($mode -eq 'verify-only') {
        if ($null -eq $previousState -or [string]$previousState.fingerprint -cne $fingerprints.overall -or
            [string]$previousState.commit -cne $commit) {
            throw (New-DeployFailure -Message 'El estado persistido no coincide con este commit y fingerprint.' -ExitCode 10)
        }
        $null = Invoke-GestudioDeploymentVerification -RepositoryRoot $repoRoot -ComposeFile $script:composeFile `
            -EnvFile $script:configPath -ProjectName $script:projectName -Configuration $configuration `
            -ExpectedCommit $commit -ExpectedFingerprint $fingerprints.overall -PreviousState $previousState `
            -StatusWriter ${function:Write-Status}
        Write-Status PASS 'Verificacion sin mutaciones finalizada'
        exit 0
    }

    if (-not $fingerprintChanged -and $null -ne $previousState) {
        try {
            $verification = Invoke-GestudioDeploymentVerification -RepositoryRoot $repoRoot -ComposeFile $script:composeFile `
                -EnvFile $script:configPath -ProjectName $script:projectName -Configuration $configuration `
                -ExpectedCommit $commit -ExpectedFingerprint $fingerprints.overall -PreviousState $previousState `
                -StatusWriter ${function:Write-Status}
            Write-Status INFO 'Fingerprint sin cambios y stack sano: no se ejecuta build, backup, up ni migracion'
        }
        catch {
            $verificationCode = if ($_.Exception.Data.Contains('ExitCode')) { [int]$_.Exception.Data['ExitCode'] } else { 7 }
            if ($verificationCode -ne 6) { throw }
            Write-Status WARN 'Se detecto drift reparable de disponibilidad; convergiendo sin build'
            $null = Invoke-Compose -Arguments @('up', '-d', '--no-build') -Capture -FailureExitCode 5
            $verification = Invoke-GestudioDeploymentVerification -RepositoryRoot $repoRoot -ComposeFile $script:composeFile `
                -EnvFile $script:configPath -ProjectName $script:projectName -Configuration $configuration `
                -ExpectedCommit $commit -ExpectedFingerprint $fingerprints.overall -PreviousState $null `
                -StatusWriter ${function:Write-Status}
        }
    }
    else {
        $dbContainer = Invoke-Compose -Arguments @('ps', '--all', '-q', 'db') -Capture -FailureExitCode 4
        $lastBackupPath = $null
        if ($null -ne $previousState -and $null -ne $previousState.lastBackupPath) {
            $lastBackupPath = [string]$previousState.lastBackupPath
        }
        if ($migrationChanged -and $hasResources) {
            if ([string]::IsNullOrWhiteSpace($dbContainer)) {
                $null = Invoke-Compose -Arguments @('up', '-d', '--no-deps', 'db') -Capture -FailureExitCode 9
                $dbContainer = Invoke-Compose -Arguments @('ps', '-q', 'db') -Capture -FailureExitCode 9
            }
            $null = Wait-DeploymentServiceHealthy -ContainerId $dbContainer -ProjectName $script:projectName `
                -Service db -TimeoutSeconds 120
            $lastBackupPath = Invoke-VerifiedBackup -OutputDirectory $backupsRoot
        }

        if ($backendBuild) {
            Write-Status INFO 'Construyendo imagen backend'
            $null = Invoke-Compose -Arguments @('build', 'backend') -Capture -FailureExitCode 5
            Write-Status PASS 'Imagen backend construida'
        }
        if ($frontendBuild) {
            Write-Status INFO 'Construyendo imagen frontend'
            $null = Invoke-Compose -Arguments @('build', 'frontend') -Capture -FailureExitCode 5
            Write-Status PASS 'Imagen frontend construida'
        }

        if ([string]::IsNullOrWhiteSpace($dbContainer)) {
            $null = Invoke-Compose -Arguments @('up', '-d', '--no-deps', 'db') -Capture -FailureExitCode 5
            $dbContainer = Invoke-Compose -Arguments @('ps', '-q', 'db') -Capture -FailureExitCode 5
        }
        $null = Wait-DeploymentServiceHealthy -ContainerId $dbContainer -ProjectName $script:projectName `
            -Service db -TimeoutSeconds 120

        $claimCount = Get-BootstrapClaimCount -DatabaseContainer $dbContainer
        if ($claimCount -eq 0) {
            if ($null -ne $previousState) {
                throw (New-DeployFailure -Message 'Falta el bootstrap registrado por el estado previo.' -ExitCode 10)
            }
            Write-Status INFO 'Ejecutando bootstrap inicial aislado y de una sola vez'
            $null = Invoke-Compose -Arguments @(
                'run', '--rm', '--no-deps', '-e', 'APP_BOOTSTRAP_SUPERADMIN_ENABLED=true',
                'backend', '--spring.main.web-application-type=none', '--app.scheduling-enabled=false'
            ) -Capture -FailureExitCode 5
            $claimCount = Get-BootstrapClaimCount -DatabaseContainer $dbContainer
            if ($claimCount -ne 1) {
                throw (New-DeployFailure -Message 'El bootstrap no produjo exactamente un claim.' -ExitCode 5)
            }
            Write-Status PASS 'Bootstrap inicial creado sin persistir la bandera habilitada'
        }
        elseif ($claimCount -ne 1) {
            throw (New-DeployFailure -Message "Cantidad invalida de claims bootstrap: $claimCount" -ExitCode 10)
        }

        Write-Status INFO 'Convergiendo servicios con Docker Compose'
        $null = Invoke-Compose -Arguments @('up', '-d', '--no-build') -Capture -FailureExitCode 5
        $verification = Invoke-GestudioDeploymentVerification -RepositoryRoot $repoRoot -ComposeFile $script:composeFile `
            -EnvFile $script:configPath -ProjectName $script:projectName -Configuration $configuration `
            -ExpectedCommit $commit -ExpectedFingerprint $fingerprints.overall -PreviousState $null `
            -StatusWriter ${function:Write-Status}
    }

    if (-not (Get-Variable lastBackupPath -ErrorAction SilentlyContinue)) {
        $lastBackupPath = if ($null -ne $previousState -and $null -ne $previousState.lastBackupPath) {
            [string]$previousState.lastBackupPath
        } else { $null }
    }
    [xml]$pom = [IO.File]::ReadAllText((Join-Path $repoRoot 'backend\pom.xml'))
    $state = [ordered]@{
        formatVersion = 1
        lastSuccessUtc = [DateTime]::UtcNow.ToString('o')
        commit = $commit
        applicationVersion = [string]$pom.project.version
        fingerprint = $fingerprints.overall
        backendFingerprint = $fingerprints.backend
        frontendFingerprint = $fingerprints.frontend
        composeFingerprint = $fingerprints.compose
        migrationFingerprint = $fingerprints.migrations
        projectName = $script:projectName
        composeFiles = @('docker-compose.yml')
        flyway = $verification.flyway
        bootstrap = $verification.bootstrap
        containers = $verification.containers
        ports = [ordered]@{
            postgres = [int]$configuration['POSTGRES_PORT']
            backend = [int]$configuration['BACKEND_PORT']
            frontend = [int]$configuration['FRONTEND_PORT']
        }
        endpoints = $verification.endpoints
        healthChecks = $verification.healthChecks
        lastBackupPath = $lastBackupPath
    }
    Write-DeploymentState -Path $statePath -State $state
    $resourcesAfter = Get-ProjectResourceSnapshot -ProjectName $script:projectName
    Write-Status INFO "recursos propios: contenedores=$($resourcesAfter.containers.Count) volumenes=$($resourcesAfter.volumes.Count) redes=$($resourcesAfter.networks.Count)"
    Write-Status PASS "Despliegue correcto en $([Math]::Round(([DateTime]::UtcNow - $script:startedAt).TotalSeconds, 1)) s"
    $exitCode = 0
}
catch {
    $exitCode = 2
    if ($_.Exception.Data.Contains('ExitCode')) { $exitCode = [int]$_.Exception.Data['ExitCode'] }
    Write-Status ERROR ("$($_.Exception.Message) (linea $($_.InvocationInfo.ScriptLineNumber))")
}
finally {
    if ($null -ne $temporaryConfig -and (Test-Path -LiteralPath $temporaryConfig -PathType Leaf)) {
        Remove-Item -LiteralPath $temporaryConfig -Force
    }
    Restore-ConfigurationEnvironment
    if ($script:mutexOwned -and $null -ne $script:mutex) {
        try { $script:mutex.ReleaseMutex() } catch { }
    }
    if ($null -ne $script:mutex) { $script:mutex.Dispose() }
    if (-not [string]::IsNullOrWhiteSpace($script:logPath)) {
        $duration = [Math]::Round(([DateTime]::UtcNow - $script:startedAt).TotalSeconds, 1)
        $line = '{0} [INFO] exitCode={1} durationSeconds={2}' -f [DateTime]::UtcNow.ToString('o'), $exitCode, $duration
        [IO.File]::AppendAllText($script:logPath, $line + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    }
}

exit $exitCode
