[CmdletBinding()]
param(
    [ValidateSet('All', 'BackendCoverage', 'BackendDiffCoverage', 'BackendMutation',
        'BackendMutationGlobal', 'BackendMutationCritical', 'BackendStatic', 'FrontendCoverage',
        'FrontendDiffCoverage', 'FrontendStatic', 'SupplyChain')]
    [string] $Scope = 'All',

    [string] $DiffBase = 'origin/main',

    [switch] $SkipDependencyVulnerabilityData
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$backend = Join-Path $repoRoot 'backend'
$frontend = Join-Path $repoRoot 'frontend'
$maven = Join-Path $backend ($(if ($IsWindows) { 'mvnw.cmd' } else { 'mvnw' }))
$artifactVerifier = Join-Path $PSScriptRoot 'verify-quality-artifacts.ps1'
$results = [ordered]@{}
$firstExitCode = 0

function Invoke-Gate {
    param([Parameter(Mandatory)][string] $Name,
          [Parameter(Mandatory)][scriptblock] $Action)

    $code = 0
    try {
        $global:LASTEXITCODE = 0
        & $Action
        if ($LASTEXITCODE -ne 0) { $code = $LASTEXITCODE }
    }
    catch {
        $code = if ($LASTEXITCODE -gt 0) { $LASTEXITCODE } else { 1 }
        Write-Host "[$Name] $($_.Exception.Message)" -ForegroundColor Red
    }
    $results[$Name] = if ($code -eq 0) { 'PASS' } else { "FAIL ($code)" }
    if ($code -ne 0 -and $script:firstExitCode -eq 0) { $script:firstExitCode = $code }
}

function Invoke-Maven {
    param([string[]] $Arguments)
    Push-Location $backend
    try {
        if ($IsWindows) { & $maven @Arguments }
        else { & bash $maven @Arguments }
        if ($LASTEXITCODE -ne 0) {
            throw "Maven falló con código $LASTEXITCODE."
        }
    }
    finally { Pop-Location }
}

function Invoke-MutationGate {
    param(
        [Parameter(Mandatory)][ValidateSet('global', 'critical')][string] $Kind,
        [Parameter(Mandatory)][string] $Profile,
        [Parameter(Mandatory)][ValidateSet('BackendMutationGlobal', 'BackendMutationCritical')]
        [string] $ArtifactScope
    )

    $executionId = [guid]::NewGuid().ToString('N')
    $markerPath = Join-Path ([IO.Path]::GetTempPath()) "gestudio-pit-$Kind-$executionId.json"
    $marker = [ordered]@{
        schemaVersion = 1
        executionId = $executionId
        scope = $Kind
        status = 'RUNNING'
        startedAtUtc = [DateTimeOffset]::UtcNow.ToString('O')
        completedAtUtc = $null
    }

    try {
        $marker | ConvertTo-Json | Set-Content -LiteralPath $markerPath -Encoding utf8
        Invoke-Maven @('-B', '-ntp', "-P$Profile", 'clean', 'test-compile',
            'org.pitest:pitest-maven:mutationCoverage')
        $marker.status = 'COMPLETED'
        $marker.completedAtUtc = [DateTimeOffset]::UtcNow.ToString('O')
        $marker | ConvertTo-Json | Set-Content -LiteralPath $markerPath -Encoding utf8
        & $artifactVerifier -Scope $ArtifactScope -MutationExecutionMarker $markerPath
    }
    finally {
        Remove-Item -LiteralPath $markerPath -Force -ErrorAction SilentlyContinue
    }
}

if ($Scope -in 'All', 'BackendCoverage') {
    Invoke-Gate 'backend coverage and executable Gherkin (90/85, critical 95/90/95)' {
        Invoke-Maven @('-B', '-ntp', '-Pquality-coverage', 'clean', 'verify')
        & $artifactVerifier -Scope BackendCoverage
    }
}

if ($Scope -in 'All', 'BackendDiffCoverage') {
    Invoke-Gate 'backend diff coverage (90)' {
        & (Join-Path $PSScriptRoot 'verify-backend-diff-coverage.ps1') -Base $DiffBase -Minimum 90
    }
}

if ($Scope -in 'All', 'BackendMutation', 'BackendMutationGlobal') {
    Invoke-Gate 'backend mutation global (80/85)' {
        Invoke-MutationGate -Kind global -Profile quality-mutation-global `
            -ArtifactScope BackendMutationGlobal
    }
}

if ($Scope -in 'All', 'BackendMutation', 'BackendMutationCritical') {
    Invoke-Gate 'backend mutation critical packages (90/90)' {
        Invoke-MutationGate -Kind critical -Profile quality-mutation-critical `
            -ArtifactScope BackendMutationCritical
    }
}

if ($Scope -in 'All', 'BackendStatic') {
    Invoke-Gate 'backend PMD global report' {
        Invoke-Maven @('-B', '-ntp', 'pmd:pmd')
    }
    Invoke-Gate 'backend CPD duplication' {
        Invoke-Maven @('-B', '-ntp', 'pmd:cpd-check')
    }
    Invoke-Gate 'backend PMD baseline and diff policy' {
        & (Join-Path $PSScriptRoot 'verify-backend-static-analysis.ps1') -Base $DiffBase
        & $artifactVerifier -Scope BackendStatic
    }
}

if ($Scope -in 'All', 'FrontendCoverage') {
    Invoke-Gate 'frontend coverage release targets (85/80, platform 90)' {
        Push-Location $frontend
        try {
            & npm run test:coverage
            if ($LASTEXITCODE -ne 0) { throw "npm run test:coverage falló con código $LASTEXITCODE." }
            & $artifactVerifier -Scope FrontendCoverage
        }
        finally { Pop-Location }
    }
}

if ($Scope -in 'All', 'FrontendDiffCoverage') {
    Invoke-Gate 'frontend diff coverage (90)' {
        & (Join-Path $PSScriptRoot 'run-frontend-diff-coverage.ps1') -Base $DiffBase
        & $artifactVerifier -Scope FrontendDiffCoverage
    }
}

if ($Scope -in 'All', 'FrontendStatic') {
    Invoke-Gate 'frontend lint' {
        Push-Location $frontend
        try { & npm run lint }
        finally { Pop-Location }
    }
    Invoke-Gate 'frontend duplication budget' {
        Push-Location $frontend
        try {
            & npm run quality:duplication
            if ($LASTEXITCODE -ne 0) { throw "npm run quality:duplication falló con código $LASTEXITCODE." }
            & $artifactVerifier -Scope FrontendDuplication
        }
        finally { Pop-Location }
    }
}

if ($Scope -in 'All', 'SupplyChain') {
    Invoke-Gate 'frontend dependency audit all scopes' {
        Push-Location $frontend
        try { & npm audit }
        finally { Pop-Location }
    }
    Invoke-Gate 'frontend production dependency audit' {
        Push-Location $frontend
        try { & npm audit --omit=dev }
        finally { Pop-Location }
    }
    Invoke-Gate 'backend dependency vulnerability audit' {
        if ($SkipDependencyVulnerabilityData) {
            throw 'El dependency audit backend fue omitido explícitamente; no puede ser PASS.'
        }
        Invoke-Maven @('-B', '-ntp', 'org.owasp:dependency-check-maven:check')
        & $artifactVerifier -Scope BackendDependencyAudit
    }
    Invoke-Gate 'backend CycloneDX SBOM' {
        Invoke-Maven @('-B', '-ntp', 'generate-resources')
        & $artifactVerifier -Scope BackendSbom
    }
    Invoke-Gate 'frontend CycloneDX SBOM' {
        Push-Location $frontend
        try {
            & npm run sbom
            if ($LASTEXITCODE -ne 0) { throw "npm run sbom falló con código $LASTEXITCODE." }
            & $artifactVerifier -Scope FrontendSbom
        }
        finally { Pop-Location }
    }
    Invoke-Gate 'GitHub Actions immutable-reference policy' {
        & (Join-Path $PSScriptRoot 'verify-actions-policy.ps1')
    }
}

Write-Host ''
Write-Host "Quality Fortress ($Scope):"
foreach ($entry in $results.GetEnumerator()) {
    Write-Host ("- {0}: {1}" -f $entry.Key, $entry.Value)
}
exit $firstExitCode
