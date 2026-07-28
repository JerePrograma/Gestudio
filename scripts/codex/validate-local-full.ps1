[CmdletBinding()]
param(
    [string] $RepositoryRoot,

    [ValidateRange(5, 180)]
    [int] $DemoTimeoutMinutes = 90,

    [ValidateRange(120, 3600)]
    [int] $OperationsTimeoutSeconds = 1200,

    [switch] $SkipSetup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSEdition -ne 'Core' -or
    $PSVersionTable.PSVersion -lt [version]'7.1.0') {
    throw "Este ejecutor requiere PowerShell 7.1 o superior. Detectado: $($PSVersionTable.PSVersion)."
}

$runningOnWindows = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
if (-not $runningOnWindows) {
    throw 'Este ejecutor local está preparado para Windows.'
}

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
}
else {
    $RepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
}

if (-not (Test-Path -LiteralPath (Join-Path $RepositoryRoot '.git'))) {
    throw "No se encontró un repositorio Git en $RepositoryRoot."
}

function Invoke-NativeText {
    param(
        [Parameter(Mandatory)]
        [string] $FilePath,

        [string[]] $Arguments = @()
    )

    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $FilePath @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    $text = ($output | ForEach-Object { $_.ToString() }) -join "`n"
    if ($exitCode -ne 0) {
        throw "Falló '$FilePath $($Arguments -join ' ')' con exit code ${exitCode}:`n$text"
    }

    return $text.Trim()
}

function Get-ToolVersion {
    param(
        [Parameter(Mandatory)]
        [string] $FilePath,

        [Parameter(Mandatory)]
        [string[]] $Arguments
    )

    return Invoke-NativeText -FilePath $FilePath -Arguments $Arguments
}

function Invoke-ValidationGate {
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $RelativeScript,

        [string[]] $Arguments = @()
    )

    $scriptPath = Join-Path $script:RepositoryRoot $RelativeScript
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        throw "No existe el script del gate: $scriptPath"
    }

    $safeName = $Name -replace '[^a-zA-Z0-9._-]', '-'
    $stdoutPath = Join-Path $script:validationRoot "$safeName.stdout.log"
    $stderrPath = Join-Path $script:validationRoot "$safeName.stderr.log"
    $startedAt = Get-Date

    Write-Host ''
    Write-Host ('=' * 72) -ForegroundColor Cyan
    Write-Host "GATE: $Name" -ForegroundColor Cyan
    Write-Host "SCRIPT: $RelativeScript"
    Write-Host "STDOUT: $stdoutPath"
    Write-Host "STDERR: $stderrPath"
    Write-Host ('=' * 72) -ForegroundColor Cyan

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $script:pwshPath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.WorkingDirectory = $script:RepositoryRoot

    foreach ($argument in @(
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $scriptPath
    ) + $Arguments) {
        [void]$startInfo.ArgumentList.Add([string]$argument)
    }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo

    try {
        if (-not $process.Start()) {
            throw "No se pudo iniciar el gate $Name."
        }

        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()

        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $exitCode = $process.ExitCode
    }
    finally {
        $process.Dispose()
    }

    [IO.File]::WriteAllText($stdoutPath, $stdout, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($stderrPath, $stderr, [Text.UTF8Encoding]::new($false))

    if (-not [string]::IsNullOrWhiteSpace($stdout)) {
        Write-Host $stdout.TrimEnd()
    }
    if (-not [string]::IsNullOrWhiteSpace($stderr)) {
        Write-Host $stderr.TrimEnd() -ForegroundColor Yellow
    }

    $duration = (Get-Date) - $startedAt
    $script:results.Add([pscustomobject]@{
        Gate = $Name
        Script = $RelativeScript
        ExitCode = $exitCode
        Result = if ($exitCode -eq 0) { 'PASS' } else { 'FAIL' }
        Duration = $duration.ToString()
        StdoutLog = $stdoutPath
        StderrLog = $stderrPath
    })

    if ($exitCode -ne 0) {
        throw "Falló '$Name' con exit code $exitCode. Revise $stdoutPath y $stderrPath."
    }

    Write-Host "[PASS] $Name" -ForegroundColor Green
}

Set-Location -LiteralPath $RepositoryRoot

$pwshCommand = Get-Command pwsh -ErrorAction Stop
$pwshPath = $pwshCommand.Source
$branch = Invoke-NativeText -FilePath 'git' -Arguments @('branch', '--show-current')
if ($branch -ne 'main') {
    throw "La rama activa debe ser main. Detectada: $branch"
}

$pending = Invoke-NativeText -FilePath 'git' -Arguments @(
    'status', '--porcelain=v1', '--untracked-files=all'
)
if (-not [string]::IsNullOrWhiteSpace($pending)) {
    Write-Host $pending -ForegroundColor Yellow
    throw 'El árbol contiene cambios locales. No se ejecutará la certificación.'
}

$head = Invoke-NativeText -FilePath 'git' -Arguments @('rev-parse', 'HEAD')
$remoteHead = Invoke-NativeText -FilePath 'git' -Arguments @('rev-parse', 'origin/main')
if ($head -ne $remoteHead) {
    throw "HEAD local ($head) no coincide con origin/main ($remoteHead)."
}

if ([string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
    throw 'JAVA_HOME no está definido. Configure un JDK 21 antes de continuar.'
}

$javacPath = Join-Path $env:JAVA_HOME 'bin\javac.exe'
if (-not (Test-Path -LiteralPath $javacPath -PathType Leaf)) {
    throw "JAVA_HOME no contiene javac.exe: $env:JAVA_HOME"
}

$javacVersion = Get-ToolVersion -FilePath $javacPath -Arguments @('-version')
if ($javacVersion -notmatch '^javac 21(?:\.|$)') {
    throw "Se requiere JDK 21. Detectado: $javacVersion"
}

$nodeVersion = Get-ToolVersion -FilePath 'node' -Arguments @('--version')
$npmVersion = Get-ToolVersion -FilePath 'npm' -Arguments @('--version')
$dockerVersion = Get-ToolVersion -FilePath 'docker' -Arguments @('info', '--format', '{{.ServerVersion}}')
$composeVersion = Get-ToolVersion -FilePath 'docker' -Arguments @('compose', 'version', '--short')

if ($nodeVersion -notmatch '^v(?<major>[0-9]+)\.' -or [int]$Matches.major -lt 22) {
    throw "Se requiere Node 22 o superior. Detectado: $nodeVersion"
}
if ($nodeVersion -notmatch '^v22\.') {
    Write-Warning "GitHub Actions usa Node 22; la validación local usa $nodeVersion."
}
if ($npmVersion -notmatch '^10\.') {
    Write-Warning "La referencia reproducible usa npm 10.x; la validación local usa npm $npmVersion."
}

$shortHead = Invoke-NativeText -FilePath 'git' -Arguments @('rev-parse', '--short=12', 'HEAD')
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$validationRoot = Join-Path $env:TEMP "GestudioValidation\$timestamp-$shortHead"
New-Item -ItemType Directory -Force -Path $validationRoot | Out-Null

$results = [Collections.Generic.List[object]]::new()
$failure = $null

Write-Host "PowerShell: $($PSVersionTable.PSVersion)"
Write-Host "JDK: $javacVersion"
Write-Host "Node: $nodeVersion"
Write-Host "npm: $npmVersion"
Write-Host "Docker: $dockerVersion"
Write-Host "Docker Compose: $composeVersion"
Write-Host "HEAD: $head"
Write-Host "Logs: $validationRoot"

try {
    if (-not $SkipSetup) {
        Invoke-ValidationGate -Name '01-setup' -RelativeScript 'scripts\codex\setup.ps1'
    }

    Invoke-ValidationGate `
        -Name '02-validate-all' `
        -RelativeScript 'scripts\codex\validate.ps1' `
        -Arguments @('-Scope', 'All')

    Invoke-ValidationGate `
        -Name '03-smoke-local' `
        -RelativeScript 'scripts\smoke-local.ps1'

    Invoke-ValidationGate `
        -Name '04-demo-seed' `
        -RelativeScript 'scripts\validate-demo-seed.ps1' `
        -Arguments @('-TimeoutMinutes', [string]$DemoTimeoutMinutes)

    Invoke-ValidationGate `
        -Name '05-backup-restore' `
        -RelativeScript 'scripts\ops\verify-backup-restore.ps1' `
        -Arguments @('-TimeoutSeconds', [string]$OperationsTimeoutSeconds)

    Invoke-ValidationGate `
        -Name '06-application-rollback' `
        -RelativeScript 'scripts\ops\verify-application-rollback.ps1' `
        -Arguments @('-TimeoutSeconds', [string]$OperationsTimeoutSeconds)

    Invoke-ValidationGate `
        -Name '07-observability' `
        -RelativeScript 'scripts\ops\verify-observability.ps1' `
        -Arguments @('-TimeoutSeconds', [string]$OperationsTimeoutSeconds)
}
catch {
    $failure = $_.Exception.Message
    Write-Host "[FAIL] $failure" -ForegroundColor Red
}
finally {
    $finalHead = Invoke-NativeText -FilePath 'git' -Arguments @('rev-parse', 'HEAD')
    $finalStatus = Invoke-NativeText -FilePath 'git' -Arguments @(
        'status', '--porcelain=v1', '--untracked-files=all'
    )
    $clean = [string]::IsNullOrWhiteSpace($finalStatus)
    $headUnchanged = $finalHead -eq $head
    $passed = $null -eq $failure -and $clean -and $headUnchanged

    $summary = [ordered]@{
        generatedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
        repository = $RepositoryRoot
        branch = $branch
        expectedHead = $head
        finalHead = $finalHead
        headUnchanged = $headUnchanged
        workingTreeClean = $clean
        result = if ($passed) { 'PASS' } else { 'FAIL' }
        failure = $failure
        gates = @($results)
    }

    $summaryPath = Join-Path $validationRoot 'summary.json'
    $summary | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $summaryPath -Encoding utf8

    Write-Host ''
    Write-Host '=== RESUMEN ===' -ForegroundColor Cyan
    $results | Format-Table Gate, Result, ExitCode, Duration -AutoSize
    Write-Host "HEAD inicial: $head"
    Write-Host "HEAD final:   $finalHead"
    Write-Host "Árbol limpio: $clean"
    Write-Host "Resultado:    $($summary.result)"
    Write-Host "Resumen JSON: $summaryPath"
    Write-Host "Logs:         $validationRoot"

    if (-not $clean) {
        Write-Host $finalStatus -ForegroundColor Yellow
    }
}

if ($null -ne $failure) {
    throw $failure
}

if (-not [string]::IsNullOrWhiteSpace((Invoke-NativeText -FilePath 'git' -Arguments @(
    'status', '--porcelain=v1', '--untracked-files=all'
)))) {
    throw 'El árbol dejó de estar limpio durante la validación.'
}

if ((Invoke-NativeText -FilePath 'git' -Arguments @('rev-parse', 'HEAD')) -ne $head) {
    throw 'HEAD cambió durante la validación.'
}

Write-Host ''
Write-Host 'CERTIFICACIÓN TÉCNICA COMPLETA: PASS' -ForegroundColor Green
