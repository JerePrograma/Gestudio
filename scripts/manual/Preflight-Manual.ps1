[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://localhost:18081',
    [string]$BackendUrl = 'http://localhost:18080',
    [switch]$AllowNonLocalUrl,
    [switch]$SkipCredentialCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Manual.Common.ps1')

$repoRoot = Get-ManualRepositoryRoot

if (-not (Test-Path -LiteralPath (Join-Path $repoRoot '.git'))) {
    throw "No existe .git en la raíz esperada: $repoRoot"
}

$requiredFiles = @(
    'README.md'
    '.gitignore'
    'frontend\package.json'
    'frontend\package-lock.json'
    'backend\pom.xml'
    'scripts\demo-local.ps1'
    'scripts\codex\validate.ps1'
    'scripts\smoke-local.ps1'
    'scripts\validate-demo-seed.ps1'
    'docs\manual-usuarios\manifest.json'
    'docs\manual-usuarios\templates\manual.html'
    'docs\manual-usuarios\templates\manual.css'
    'scripts\manual\flows\capture-manual.cjs'
    'scripts\manual\flows\render-manual.cjs'
)

foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $relativePath) -PathType Leaf)) {
        throw "No existe $relativePath."
    }
}

$requiredCommands = @('git', 'docker', 'node', 'npm', 'npx')
foreach ($commandName in $requiredCommands) {
    if ($null -eq (Get-Command $commandName -ErrorAction SilentlyContinue)) {
        if ($commandName -eq 'docker') {
            throw 'Falta Docker Desktop o Docker no está disponible.'
        }

        throw "Falta la herramienta requerida: $commandName."
    }
}

if ($PSVersionTable.PSVersion -lt [version]'5.1') {
    throw "PowerShell 5.1 o superior es obligatorio. Versión detectada: $($PSVersionTable.PSVersion)."
}

$branchResult = Invoke-ManualNativeCommand `
    -FilePath 'git' `
    -Arguments @('-C', $repoRoot, 'branch', '--show-current') `
    -CaptureOutput

if ($branchResult.Output.Trim() -ne 'main') {
    throw "La rama local debe ser main. Rama detectada: '$($branchResult.Output.Trim())'."
}

$statusResult = Invoke-ManualNativeCommand `
    -FilePath 'git' `
    -Arguments @('-C', $repoRoot, 'status', '--porcelain') `
    -CaptureOutput

if (-not [string]::IsNullOrWhiteSpace($statusResult.Output)) {
    throw 'El árbol de trabajo contiene cambios locales. Revise git status antes de generar el manual.'
}

Invoke-ManualNativeCommand -FilePath 'docker' -Arguments @('info') | Out-Null

$composeVersion = Invoke-ManualNativeCommand `
    -FilePath 'docker' `
    -Arguments @('compose', 'version', '--short') `
    -CaptureOutput
$composeVersionText = $composeVersion.Output.Trim()

if ($composeVersionText -notmatch '^v?(?<major>[0-9]+)(?:\.|$)') {
    throw "No se pudo interpretar la versión de Docker Compose: '$composeVersionText'."
}

if ([int]$Matches.major -lt 2) {
    throw "Docker Compose 2 o superior es obligatorio. Versión detectada: '$composeVersionText'."
}

$nodeVersion = Invoke-ManualNativeCommand -FilePath 'node' -Arguments @('--version') -CaptureOutput
if ($nodeVersion.Output -notmatch '^v(?<major>[0-9]+)\.') {
    throw "No se pudo interpretar la versión de Node: '$($nodeVersion.Output)'."
}

if ([int]$Matches.major -lt 22) {
    throw "Node 22 o superior es obligatorio. Versión detectada: '$($nodeVersion.Output)'."
}

Invoke-ManualNativeCommand -FilePath 'npm' -Arguments @('--version') -CaptureOutput | Out-Null

function Test-ManualJava21Executable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateSet('java', 'javac')]
        [string]$Kind
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }

    $result = Invoke-ManualNativeCommand `
        -FilePath $Path `
        -Arguments @('-version') `
        -CaptureOutput `
        -AllowFailure

    if ($result.ExitCode -ne 0) {
        return $false
    }

    if ($Kind -eq 'java') {
        return $result.Output -match 'version\s+"21(?:\.|\")'
    }

    return $result.Output -match 'javac\s+21(?:\.|$)'
}

function Resolve-ManualJdk21 {
    [CmdletBinding()]
    param()

    $isWindows = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
    $javaName = if ($isWindows) { 'java.exe' } else { 'java' }
    $javacName = if ($isWindows) { 'javac.exe' } else { 'javac' }
    $candidates = [Collections.Generic.List[string]]::new()

    if (-not [string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
        $candidates.Add((Join-Path $env:JAVA_HOME "bin/$javaName"))
    }

    $javacCommand = Get-Command javac -ErrorAction SilentlyContinue
    if ($null -ne $javacCommand -and -not [string]::IsNullOrWhiteSpace($javacCommand.Source)) {
        $candidates.Add((Join-Path (Split-Path -Parent $javacCommand.Source) $javaName))
    }

    $javaCommand = Get-Command java -ErrorAction SilentlyContinue
    if ($null -ne $javaCommand -and -not [string]::IsNullOrWhiteSpace($javaCommand.Source)) {
        $candidates.Add($javaCommand.Source)
    }

    $roots = if ($isWindows) {
        @(
            (Join-Path $env:ProgramFiles 'Java')
            (Join-Path $env:ProgramFiles 'Amazon Corretto')
            (Join-Path $env:ProgramFiles 'Eclipse Adoptium')
            (Join-Path $env:USERPROFILE '.jdks')
        )
    }
    else {
        @('/usr/lib/jvm', '/opt/java', (Join-Path $HOME '.jdks'))
    }

    foreach ($root in $roots) {
        if (-not [string]::IsNullOrWhiteSpace($root) -and (Test-Path -LiteralPath $root -PathType Container)) {
            Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $candidates.Add((Join-Path $_.FullName "bin/$javaName"))
            }
        }
    }

    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        if (-not (Test-ManualJava21Executable -Path $candidate -Kind java)) {
            continue
        }

        $binDirectory = Split-Path -Parent ([IO.Path]::GetFullPath($candidate))
        $javacPath = Join-Path $binDirectory $javacName
        if (-not (Test-ManualJava21Executable -Path $javacPath -Kind javac)) {
            continue
        }

        return [pscustomobject]@{
            Home = Split-Path -Parent $binDirectory
            Java = [IO.Path]::GetFullPath($candidate)
            Javac = [IO.Path]::GetFullPath($javacPath)
        }
    }

    throw 'No se encontró un JDK 21 completo. Configure JAVA_HOME o agregue el binario de JDK 21 al PATH.'
}

$jdk = Resolve-ManualJdk21
$jdkBin = Split-Path -Parent $jdk.Java
[Environment]::SetEnvironmentVariable('JAVA_HOME', $jdk.Home, 'Process')

$pathEntries = @($env:PATH -split [IO.Path]::PathSeparator)
if ($pathEntries -notcontains $jdkBin) {
    [Environment]::SetEnvironmentVariable(
        'PATH',
        ($jdkBin + [IO.Path]::PathSeparator + $env:PATH),
        'Process'
    )
}

$allowExternal = $AllowNonLocalUrl -or
    [Environment]::GetEnvironmentVariable('GESTUDIO_MANUAL_ALLOW_NON_LOCAL_URL', 'Process') -eq '1'

foreach ($urlText in @($BaseUrl, $BackendUrl)) {
    $uri = $null

    if (-not [uri]::TryCreate($urlText, [UriKind]::Absolute, [ref]$uri)) {
        throw "La URL indicada no es válida: $urlText"
    }

    if (-not (Test-ManualLocalUri -Uri $uri) -and -not $allowExternal) {
        throw 'La URL indicada no es local y requiere autorización explícita mediante GESTUDIO_MANUAL_ALLOW_NON_LOCAL_URL=1.'
    }

    if ($uri.Scheme -notin @('http', 'https')) {
        throw "El esquema de URL no está permitido: $($uri.Scheme)."
    }
}

if (-not $SkipCredentialCheck) {
    Assert-ManualDemoCredentials
}

$playwrightVersion = Invoke-ManualNativeCommand `
    -FilePath 'npx' `
    -Arguments @('--yes', 'playwright@1.54.1', '--version') `
    -CaptureOutput

if ($playwrightVersion.Output -notmatch '1\.54\.1') {
    throw "No se pudo resolver Playwright 1.54.1. Salida: '$($playwrightVersion.Output)'."
}

$trackedArtifacts = Invoke-ManualNativeCommand `
    -FilePath 'git' `
    -Arguments @(
        '-C', $repoRoot, 'ls-files', '--',
        'artifacts/manual/**',
        'docs/manual-usuarios/screenshots/**',
        'docs/manual-usuarios/.tmp/**',
        'playwright-report/**',
        'test-results/**'
    ) `
    -CaptureOutput

if (-not [string]::IsNullOrWhiteSpace($trackedArtifacts.Output)) {
    throw 'Existen artefactos generados versionados accidentalmente.'
}

Write-Host "Preflight correcto. Docker Compose $composeVersionText y JDK 21 detectados. No se mostraron secretos."
