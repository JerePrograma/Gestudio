[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resetScript = Join-Path $PSScriptRoot 'reset-ephemeral-database.ps1'
$passes = 0

function Assert-Contract {
    param(
        [Parameter(Mandatory)][bool] $Condition,
        [Parameter(Mandatory)][string] $Message
    )
    if (-not $Condition) { throw $Message }
    $script:passes++
}

function Assert-RejectedWithoutDocker {
    param(
        [Parameter(Mandatory)][hashtable] $Arguments,
        [Parameter(Mandatory)][string] $ExpectedMessage
    )
    $previousPath = $env:PATH
    try {
        $env:PATH = ''
        $actual = $null
        try { & $resetScript @Arguments | Out-Null }
        catch { $actual = $_.Exception.Message }
    }
    finally { $env:PATH = $previousPath }
    Assert-Contract -Condition (-not [string]::IsNullOrWhiteSpace($actual) -and
        $actual.Contains($ExpectedMessage) -and -not $actual.Contains('Docker CLI')) `
        -Message "El preflight no rechazó antes de Docker: $ExpectedMessage"
}

foreach ($scriptPath in @($resetScript, $PSCommandPath)) {
    $bytes = [IO.File]::ReadAllBytes($scriptPath)
    Assert-Contract -Condition ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and
        $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) `
        -Message "$scriptPath debe conservar UTF-8 BOM para Windows PowerShell."
    $text = [Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    Assert-Contract -Condition (-not $text.Contains("`r")) `
        -Message "$scriptPath debe usar LF, sin CRLF mezclado."
    Assert-Contract -Condition $text.EndsWith("`n") `
        -Message "$scriptPath debe terminar con newline."
    Assert-Contract -Condition (-not ($text -split "`n" | Where-Object { $_ -match '[ \t]+$' })) `
        -Message "$scriptPath no debe contener whitespace al final de línea."
    $tokens = $null
    $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile(
        $scriptPath, [ref] $tokens, [ref] $parseErrors)
    $parseDetails = @($parseErrors | ForEach-Object { $_.Message }) -join '; '
    Assert-Contract -Condition ($parseErrors.Count -eq 0) `
        -Message "$scriptPath no parsea: $parseDetails"
}

$sourceBytes = [IO.File]::ReadAllBytes($resetScript)
$source = [Text.Encoding]::UTF8.GetString($sourceBytes, 3, $sourceBytes.Length - 3)
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile(
    $resetScript, [ref] $tokens, [ref] $parseErrors)
$functions = @{}
foreach ($definition in $ast.FindAll({
    param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]
}, $true)) {
    $functions[$definition.Name] = $definition.Extent.Text
}
foreach ($requiredFunction in @(
    'Assert-StaticSafetyContract', 'Assert-ComposeModel', 'Assert-OwnedContainer',
    'Assert-DatabaseOwnership', 'Invoke-DatabaseSql',
    'Assert-BackendImageMatchesMigrations', 'Assert-FlywayAndRuntime')) {
    Assert-Contract -Condition $functions.ContainsKey($requiredFunction) `
        -Message "Falta la función contractual $requiredFunction."
}

$help = Get-Help -Name $resetScript -Full
Assert-Contract -Condition (-not [string]::IsNullOrWhiteSpace($help.Synopsis) -and
    @($help.parameters.parameter.name) -contains 'TargetEnvironment' -and
    @($help.parameters.parameter.name) -contains 'ProjectName' -and
    @($help.parameters.parameter.name) -contains 'DatabaseName' -and
    @($help.parameters.parameter.name) -contains 'DockerContext' -and
    @($help.parameters.parameter.name) -contains 'Confirmation') `
    -Message 'La ayuda debe documentar target, contexto, proyecto, base y confirmación.'
$helpOutput = (& $resetScript -Help | Out-String)
Assert-Contract -Condition ($helpOutput.Contains('RESET-EPHEMERAL-DATABASE') -and
    $helpOutput.Contains('ya iniciada')) `
    -Message '-Help debe funcionar sin parámetros ni Docker.'

$valid = @{
    TargetEnvironment = 'ephemeral'
    DockerContext = 'desktop-linux'
    ProjectName = 'gestudio-ephemeral-a1b2c3d4e5f6'
    DatabaseName = 'gestudio_ephemeral_a1b2c3d4e5f6'
    EnvFile = 'does-not-exist.env'
    Confirmation = 'RESET-EPHEMERAL-DATABASE:desktop-linux:gestudio-ephemeral-a1b2c3d4e5f6:gestudio_ephemeral_a1b2c3d4e5f6'
}
$arguments = $valid.Clone(); $arguments.TargetEnvironment = 'production'
Assert-RejectedWithoutDocker $arguments 'sólo dev, test o ephemeral'
$arguments = $valid.Clone(); $arguments.TargetEnvironment = 'staging'
Assert-RejectedWithoutDocker $arguments 'sólo dev, test o ephemeral'
$arguments = $valid.Clone(); $arguments.ProjectName = 'gestudio-remote-demo'
Assert-RejectedWithoutDocker $arguments 'gestudio-remote-demo está protegido'
$arguments = $valid.Clone(); $arguments.DockerContext = 'production'
Assert-RejectedWithoutDocker $arguments 'DockerContext inválido'
$arguments = $valid.Clone(); $arguments.DatabaseName = 'gestudio_db'
Assert-RejectedWithoutDocker $arguments 'DatabaseName debe ser exactamente'
$arguments = $valid.Clone(); $arguments.Confirmation = 'yes'
Assert-RejectedWithoutDocker $arguments 'Confirmación inválida'
$previousDockerHost = [Environment]::GetEnvironmentVariable('DOCKER_HOST', 'Process')
try {
    [Environment]::SetEnvironmentVariable('DOCKER_HOST', 'tcp://production.invalid:2376', 'Process')
    Assert-RejectedWithoutDocker $valid 'DOCKER_HOST está definido'
}
finally {
    [Environment]::SetEnvironmentVariable('DOCKER_HOST', $previousDockerHost, 'Process')
}

$staticSafety = $functions['Assert-StaticSafetyContract']
Assert-Contract -Condition ($staticSafety.Contains("-cnotin @('dev', 'test', 'ephemeral')") -and
    $staticSafety.Contains('$ProjectName -ceq ''gestudio-remote-demo''') -and
    $staticSafety.Contains('$DockerContext -notmatch') -and
    $staticSafety.Contains('RESET-EPHEMERAL-DATABASE:') -and
    $staticSafety.Contains('$DatabaseName -cne $expectedDatabase')) `
    -Message 'El preflight debe conservar allowlist, demo protegida, correlación y confirmación fuerte.'
$ownership = $functions['Assert-DatabaseOwnership']
foreach ($label in @('com.docker.compose.project', 'com.docker.compose.volume')) {
    Assert-Contract -Condition $ownership.Contains($label) `
        -Message "La propiedad DB debe validar el label $label."
}
Assert-Contract -Condition ($ownership.Contains("'ps', '-a', '--no-trunc', '--filter'") -and
    $ownership.Contains('$attachments.Count -ne 1')) `
    -Message 'El volumen debe pertenecer a un único contenedor exacto.'

Assert-Contract -Condition ($source -notmatch '(?i)\bprune\b|volume\s+rm|down\s+--volumes|down\s+-v') `
    -Message 'El reset de schema no puede podar ni eliminar volúmenes.'
Assert-Contract -Condition ($source.Contains('DROP SCHEMA public CASCADE;') -and
    $source.Contains('CREATE SCHEMA public AUTHORIZATION pg_database_owner;')) `
    -Message 'La mutación debe estar acotada al schema public de la DB validada.'
$ownershipIndex = $source.IndexOf('Assert-DatabaseOwnership -ContainerId')
$dropIndex = $source.IndexOf('DROP SCHEMA public CASCADE;')
Assert-Contract -Condition ($ownershipIndex -ge 0 -and $dropIndex -gt $ownershipIndex) `
    -Message 'La validación exacta de propiedad debe preceder al DROP SCHEMA.'
Assert-Contract -Condition ($source.Contains("'up', '-d', '--no-deps', '--force-recreate', '--wait'") -and
    $source.Contains('Assert-FlywayAndRuntime') -and
    $source.Contains('APP_BOOTSTRAP_SUPERADMIN_ENABLED') -and
    $source.Contains('APP_EMAIL_REAL_NETWORK_ALLOWED') -and
    $source.Contains("Assert-SyntheticSecret (Get-RequiredProperty `$backendEnvironment 'JWT_SECRET'") -and
    $source.Contains("'APP_EMAIL_GMAIL_APP_PASSWORD'") -and
    $source.Contains("'APP_OBSERVABILITY_METRICS_TOKEN'")) `
    -Message 'El reset debe migrar/validar con backend healthy y side effects apagados.'
Assert-Contract -Condition ($source.Contains('gestudio-backend:ephemeral-') -and
    $source.Contains("'run', '--rm', '--network', 'none', '--pull', 'never'") -and
    $source.LastIndexOf('Assert-BackendImageMatchesMigrations') -lt $dropIndex) `
    -Message 'La imagen efímera y su metadata Flyway deben validarse sin red antes del DROP SCHEMA.'
Assert-Contract -Condition ($source.Contains("GetEnvironmentVariable('DOCKER_HOST', 'Process')") -and
    $source.Contains('$dockerEndpoint -notmatch ''^npipe://''') -and
    $source.Contains('$dockerEndpoint -cne ''unix:///var/run/docker.sock''')) `
    -Message 'Todo reset debe fijar un contexto con endpoint Docker exclusivamente local.'

Write-Host "[PASS] reset-ephemeral-database static contract ($passes assertions)" -ForegroundColor Green
