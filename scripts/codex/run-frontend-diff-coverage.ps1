[CmdletBinding()]
param(
    [string] $Base = 'origin/main'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$frontend = Join-Path $repoRoot 'frontend'
$statusPath = Join-Path $frontend 'coverage\diff-coverage-status.json'
$coverageMapPath = Join-Path $frontend 'coverage\diff\coverage-final.json'
$evidencePath = Join-Path $frontend 'coverage\diff-coverage.json'
$inventoryVerifier = Join-Path $frontend 'scripts\verify-coverage-source-inventory.mjs'
$inventoryEvidencePath = Join-Path $frontend 'coverage\diff\source-inventory.json'
$minimum = 90.0

Push-Location $repoRoot
try {
    & git rev-parse --verify --quiet "$Base`^{commit}" *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "No se puede resolver la base Git de diff coverage: $Base"
    }
    $diff = @(& git diff --unified=0 --no-color --diff-filter=ACMR $Base -- frontend/src)
    if ($LASTEXITCODE -ne 0) {
        throw "git diff falló para la base $Base."
    }
    $untracked = @(& git ls-files --others --exclude-standard -- frontend/src)
    if ($LASTEXITCODE -ne 0) {
        throw 'No se pudieron enumerar fuentes frontend nuevas.'
    }
}
finally {
    Pop-Location
}

$changedByFile = [Collections.Generic.Dictionary[string, Collections.Generic.HashSet[int]]]::new(
    [StringComparer]::OrdinalIgnoreCase)
$currentFile = $null

foreach ($line in $diff) {
    if ($line -match '^\+\+\+ b/(?<path>frontend/src/.+\.(?:ts|tsx))$') {
        $currentFile = $Matches.path -replace '\\', '/'
        if ($currentFile -match '\.(?:test|spec)\.(?:ts|tsx)$' -or
            $currentFile -match '/test/' -or $currentFile -match '\.d\.ts$') {
            $currentFile = $null
            continue
        }
        if (-not $changedByFile.ContainsKey($currentFile)) {
            $changedByFile[$currentFile] = [Collections.Generic.HashSet[int]]::new()
        }
        continue
    }
    if ($null -ne $currentFile -and
        $line -match '^@@ -\d+(?:,\d+)? \+(?<start>\d+)(?:,(?<count>\d+))? @@') {
        $start = [int]$Matches.start
        $count = if ($Matches['count']) { [int]$Matches['count'] } else { 1 }
        for ($number = $start; $number -lt ($start + $count); $number++) {
            [void]$changedByFile[$currentFile].Add($number)
        }
    }
}

foreach ($relativePath in $untracked | Where-Object {
    $_ -match '^frontend/src/.+\.(?:ts|tsx)$' -and
    $_ -notmatch '\.(?:test|spec)\.(?:ts|tsx)$' -and
    $_ -notmatch '[\\/]test[\\/]' -and $_ -notmatch '\.d\.ts$'
}) {
    $normalized = $relativePath -replace '\\', '/'
    if (-not $changedByFile.ContainsKey($normalized)) {
        $changedByFile[$normalized] = [Collections.Generic.HashSet[int]]::new()
    }
    $sourcePath = Join-Path $repoRoot ($normalized -replace '/', [IO.Path]::DirectorySeparatorChar)
    $sourceLineCount = @(Get-Content -LiteralPath $sourcePath).Count
    for ($number = 1; $number -le $sourceLineCount; $number++) {
        [void]$changedByFile[$normalized].Add($number)
    }
}

$changedSources = @($changedByFile.Keys |
    ForEach-Object { $_ -replace '\\', '/' } |
    Sort-Object -Unique)

if ($changedSources.Count -eq 0) {
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $statusPath))
    $reason = 'NO_CHANGED_TYPESCRIPT_SOURCES'
    $status = [ordered]@{
        base = $Base
        applicable = $false
        reason = $reason
        changedSourceFiles = @()
    }
    [IO.File]::WriteAllText($statusPath, ($status | ConvertTo-Json -Depth 3), [Text.UTF8Encoding]::new($false))
    $evidence = [ordered]@{
        base = $Base
        minimum = $minimum
        applicable = $false
        reason = $reason
        changedSourceFiles = @()
    }
    [IO.File]::WriteAllText($evidencePath, ($evidence | ConvertTo-Json -Depth 3), [Text.UTF8Encoding]::new($false))
    Write-Host 'Frontend diff coverage: NOT_APPLICABLE (no hay fuentes TypeScript modificadas).'
    return
}

$coverageFiles = @($changedSources | ForEach-Object { $_ -replace '^frontend/', '' })
[void][IO.Directory]::CreateDirectory((Split-Path -Parent $statusPath))
$status = [ordered]@{ base = $Base; applicable = $true; changedSourceFiles = $changedSources }
[IO.File]::WriteAllText($statusPath, ($status | ConvertTo-Json -Depth 3), [Text.UTF8Encoding]::new($false))

$previousFiles = [Environment]::GetEnvironmentVariable('DIFF_COVERAGE_FILES', 'Process')
$exitCode = 0
Push-Location $frontend
try {
    $env:DIFF_COVERAGE_FILES = ConvertTo-Json -InputObject $coverageFiles -Compress
    & npm run test:diff-coverage
    $exitCode = $LASTEXITCODE
}
finally {
    [Environment]::SetEnvironmentVariable('DIFF_COVERAGE_FILES', $previousFiles, 'Process')
    Pop-Location
}

if ($exitCode -ne 0) {
    throw "npm run test:diff-coverage falló con código $exitCode."
}

if (-not (Test-Path -LiteralPath $coverageMapPath -PathType Leaf)) {
    throw "Falta el mapa Istanbul requerido para diff coverage frontend: $coverageMapPath"
}

& node $inventoryVerifier --coverage $coverageMapPath --status $statusPath --output $inventoryEvidencePath
if ($LASTEXITCODE -ne 0) {
    throw "El inventario fail-closed de diff coverage frontend falló con código $LASTEXITCODE."
}

$coverageMap = Get-Content -LiteralPath $coverageMapPath -Raw | ConvertFrom-Json
$inventory = Get-Content -LiteralPath $inventoryEvidencePath -Raw | ConvertFrom-Json
$typeOnlyFiles = @($inventory.typeOnlyFiles | ForEach-Object { [string]$_ -replace '\\', '/' })
$coverageByFile = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($property in $coverageMap.PSObject.Properties) {
    $absolute = [IO.Path]::GetFullPath([string]$property.Name)
    $relative = [IO.Path]::GetRelativePath($repoRoot, $absolute) -replace '\\', '/'
    $coverageByFile[$relative] = $property.Value
}

$totals = [ordered]@{
    lines = [ordered]@{ total = 0L; covered = 0L }
    statements = [ordered]@{ total = 0L; covered = 0L }
    branches = [ordered]@{ total = 0L; covered = 0L }
}
$fileResults = [Collections.Generic.List[object]]::new()

foreach ($entry in $changedByFile.GetEnumerator() | Sort-Object Key) {
    $fileMetrics = [ordered]@{
        lines = [ordered]@{ total = 0L; covered = 0L }
        statements = [ordered]@{ total = 0L; covered = 0L }
        branches = [ordered]@{ total = 0L; covered = 0L }
    }
    $isTypeOnly = $entry.Key -in $typeOnlyFiles
    if (-not $coverageByFile.ContainsKey($entry.Key)) {
        if (-not $isTypeOnly) {
            throw "El mapa Istanbul no incluyó la fuente frontend modificada: $($entry.Key)"
        }
        $fileResults.Add([ordered]@{
            path = $entry.Key
            sourceKind = 'type-only'
            addedLines = $entry.Value.Count
            executableChangedLines = 0
            metrics = $fileMetrics
        })
        continue
    }

    $fileCoverage = $coverageByFile[$entry.Key]
    $mapEntries = @($fileCoverage.statementMap.PSObject.Properties).Count +
        @($fileCoverage.fnMap.PSObject.Properties).Count +
        @($fileCoverage.branchMap.PSObject.Properties).Count
    if ($mapEntries -eq 0 -and -not $isTypeOnly) {
        throw "El mapa Istanbul dejó vacía una fuente frontend ejecutable: $($entry.Key)"
    }
    $lineStatementCounts = [Collections.Generic.Dictionary[int, Collections.Generic.List[int64]]]::new()

    foreach ($statementProperty in $fileCoverage.statementMap.PSObject.Properties) {
        $location = $statementProperty.Value
        $startLine = [int]$location.start.line
        if (-not $entry.Value.Contains($startLine)) { continue }
        if (-not $lineStatementCounts.ContainsKey($startLine)) {
            $lineStatementCounts[$startLine] = [Collections.Generic.List[int64]]::new()
        }
        $fileMetrics.statements.total++
        $totals.statements.total++
        $count = [int64]$fileCoverage.s.($statementProperty.Name)
        $lineStatementCounts[$startLine].Add($count)
        if ($count -gt 0) {
            $fileMetrics.statements.covered++
            $totals.statements.covered++
        }
    }

    foreach ($branchProperty in $fileCoverage.branchMap.PSObject.Properties) {
        $branch = $branchProperty.Value
        $counts = @($fileCoverage.b.($branchProperty.Name))
        for ($index = 0; $index -lt @($branch.locations).Count; $index++) {
            $location = @($branch.locations)[$index]
            $startLine = if ($null -ne $location.start -and
                $location.start.PSObject.Properties.Match('line').Count -gt 0) {
                [int]$location.start.line
            }
            elseif ($location.PSObject.Properties.Match('loc').Count -gt 0 -and
                $null -ne $location.loc -and
                $location.loc.start.PSObject.Properties.Match('line').Count -gt 0) {
                [int]$location.loc.start.line
            }
            elseif ($branch.PSObject.Properties.Match('loc').Count -gt 0 -and
                $null -ne $branch.loc -and
                $branch.loc.start.PSObject.Properties.Match('line').Count -gt 0) {
                [int]$branch.loc.start.line
            }
            else {
                throw "Branch sin ubicación medible en $($entry.Key), id $($branchProperty.Name)."
            }
            if (-not $entry.Value.Contains($startLine)) { continue }
            $fileMetrics.branches.total++
            $totals.branches.total++
            if ([int64]$counts[$index] -gt 0) {
                $fileMetrics.branches.covered++
                $totals.branches.covered++
            }
        }
    }

    foreach ($lineNumber in $lineStatementCounts.Keys) {
        $fileMetrics.lines.total++
        $totals.lines.total++
        $covered = @($lineStatementCounts[$lineNumber] | Where-Object { $_ -gt 0 }).Count -gt 0
        if ($covered) {
            $fileMetrics.lines.covered++
            $totals.lines.covered++
        }
    }

    $fileResults.Add([ordered]@{
        path = $entry.Key
        sourceKind = if ($isTypeOnly) { 'type-only' } else { 'runtime' }
        addedLines = $entry.Value.Count
        executableChangedLines = $lineStatementCounts.Count
        metrics = $fileMetrics
    })
}

foreach ($metricName in 'lines', 'statements', 'branches') {
    $metric = $totals[$metricName]
    $metric['percentage'] = if ($metric.total -eq 0) { $null } else {
        [Math]::Round(100.0 * $metric.covered / $metric.total, 2)
    }
}

$totalExecutable = [int64]$totals.lines.total + [int64]$totals.statements.total + [int64]$totals.branches.total
if ($totalExecutable -eq 0) {
    $reason = 'NO_EXECUTABLE_CHANGED_HUNKS'
    $status = [ordered]@{
        base = $Base
        applicable = $false
        reason = $reason
        changedSourceFiles = $changedSources
    }
    [IO.File]::WriteAllText($statusPath, ($status | ConvertTo-Json -Depth 3), [Text.UTF8Encoding]::new($false))
    $evidence = [ordered]@{
        base = $Base
        minimum = $minimum
        applicable = $false
        reason = $reason
        changedSourceFiles = $changedSources
        metrics = $totals
        files = $fileResults
    }
    [IO.File]::WriteAllText($evidencePath, ($evidence | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    Write-Host 'Frontend diff coverage: NOT_APPLICABLE (los hunks TypeScript modificados no contienen ejecutables medibles).'
    return
}

$evidence = [ordered]@{
    base = $Base
    minimum = $minimum
    applicable = $true
    changedSourceFiles = $changedSources
    metrics = $totals
    files = $fileResults
}
[IO.File]::WriteAllText($evidencePath, ($evidence | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))

$failures = @()
foreach ($metricName in 'lines', 'statements', 'branches') {
    $metric = $totals[$metricName]
    if ($metric.total -gt 0 -and [double]$metric.percentage -lt $minimum) {
        $failures += "$metricName=$($metric.percentage)%"
    }
}
if ($failures.Count -gt 0) {
    throw "Frontend diff coverage requiere al menos $minimum% por métrica: $($failures -join ', ')."
}

Write-Host ("Frontend diff coverage: PASS (lines={0}%, statements={1}%, branches={2}%, base {3})." -f
    $totals.lines.percentage, $totals.statements.percentage, $totals.branches.percentage, $Base)
