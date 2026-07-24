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

$requiredCommands = @('git', 'docker', 'node', 'npm', 'npx', 'java', 'javac')
foreach ($commandName in $requiredCommands) {
    if ($null -eq (Get-Command $commandName -ErrorAction SilentlyContinue)) {
        switch ($commandName) {
            'docker' { throw 'Falta Docker Desktop o Docker no está disponible.' }
            'java'   { throw 'Falta Java 21 o java no está disponible.' }
            'javac'  { throw 'Falta un JDK 21 completo: javac no está disponible.' }
            default  { throw "Falta la herramienta requerida: $commandName." }
        }
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

if ($composeVersion.Output -notmatch '^v?2\.') {
    throw "Falta Docker Compose v2. Versión detectada: '$($composeVersion.Output)'."
}

$nodeVersion = Invoke-ManualNativeCommand -FilePath 'node' -Arguments @('--version') -CaptureOutput
if ($nodeVersion.Output -notmatch '^v(?<major>[0-9]+)\.') {
    throw "No se pudo interpretar la versión de Node: '$($nodeVersion.Output)'."
}

if ([int]$Matches.major -lt 22) {
    throw "Node 22 o superior es obligatorio. Versión detectada: '$($nodeVersion.Output)'."
}

Invoke-ManualNativeCommand -FilePath 'npm' -Arguments @('--version') -CaptureOutput | Out-Null

$javaVersion = Invoke-ManualNativeCommand -FilePath 'java' -Arguments @('-version') -CaptureOutput
if ($javaVersion.Output -notmatch 'version\s+"21(?:\.|")') {
    throw "Java 21 es obligatorio. Salida detectada: '$($javaVersion.Output)'."
}

$javacVersion = Invoke-ManualNativeCommand -FilePath 'javac' -Arguments @('-version') -CaptureOutput
if ($javacVersion.Output -notmatch 'javac\s+21(?:\.|$)') {
    throw "JDK 21 es obligatorio. Salida detectada: '$($javacVersion.Output)'."
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

Write-Host 'Preflight correcto. No se mostraron secretos.'
