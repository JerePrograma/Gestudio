[CmdletBinding()]
param(
    [string] $Base = 'origin/main'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$reportPath = Join-Path $repoRoot 'backend\target\pmd.xml'
$baselinePath = Join-Path $PSScriptRoot 'pmd-baseline.json'
$statusPath = Join-Path $repoRoot 'backend\target\pmd-baseline-status.json'
$keySeparator = [char]0x1f

function Normalize-Message {
    param([AllowEmptyString()][string] $Message)

    return ($Message.Trim() -replace '\s+', ' ')
}

function Get-FindingKey {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Rule,
        [Parameter(Mandatory)][string] $Message
    )

    return $Path, $Rule, $Message -join $keySeparator
}

function Get-RelativeSourcePath {
    param([Parameter(Mandatory)][string] $ReportedPath)

    $fullPath = if ([IO.Path]::IsPathRooted($ReportedPath)) {
        [IO.Path]::GetFullPath($ReportedPath)
    }
    elseif (($ReportedPath -replace '\\', '/') -like 'src/main/java/*') {
        [IO.Path]::GetFullPath((Join-Path $repoRoot "backend\$ReportedPath"))
    }
    else {
        [IO.Path]::GetFullPath((Join-Path $repoRoot $ReportedPath))
    }
    $relativePath = [IO.Path]::GetRelativePath($repoRoot, $fullPath) -replace '\\', '/'
    if ($relativePath -notlike 'backend/src/main/java/*.java') {
        throw "PMD informó una fuente fuera del alcance backend esperado: $ReportedPath"
    }
    return $relativePath
}

if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
    throw "Falta el reporte PMD global requerido: $reportPath"
}
if (-not (Test-Path -LiteralPath $baselinePath -PathType Leaf)) {
    throw "Falta el baseline PMD explícito: $baselinePath"
}

Push-Location $repoRoot
try {
    & git rev-parse --verify --quiet "$Base`^{commit}" *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "No se puede resolver la base Git del análisis estático diferencial: $Base"
    }
    $resolvedBase = (& git rev-parse "$Base`^{commit}").Trim()
    if ($LASTEXITCODE -ne 0 -or $resolvedBase -notmatch '^[0-9a-f]{40}$') {
        throw "La base Git del análisis estático no resolvió a un commit: $Base"
    }

    $diff = @(& git diff --unified=0 --no-color --diff-filter=ACMR $Base -- backend/src/main/java)
    if ($LASTEXITCODE -ne 0) {
        throw "git diff falló para la base $Base."
    }
    $untracked = @(& git ls-files --others --exclude-standard -- backend/src/main/java)
    if ($LASTEXITCODE -ne 0) {
        throw 'No se pudieron enumerar fuentes backend nuevas.'
    }
}
finally {
    Pop-Location
}

[xml] $report = Get-Content -LiteralPath $reportPath -Raw
if ($report.DocumentElement.LocalName -ne 'pmd') {
    throw 'El reporte PMD no tiene la raíz esperada.'
}

$configurationErrors = @($report.SelectNodes("//*[local-name()='configerror' or local-name()='processingerror' or local-name()='error']"))
$suppressedViolations = @($report.SelectNodes("//*[local-name()='suppressedviolation']"))
$sourceSuppressions = [Collections.Generic.List[object]]::new()
foreach ($sourceFile in @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'backend\src\main\java') -Filter '*.java' -File -Recurse)) {
    $source = Get-Content -LiteralPath $sourceFile.FullName -Raw
    foreach ($pattern in '(?im)\bNOPMD\b', '(?is)@SuppressWarnings\s*\([^)]*"PMD(?:\.|")') {
        foreach ($match in [regex]::Matches($source, $pattern)) {
            $line = 1 + [regex]::Matches($source.Substring(0, $match.Index), "`n").Count
            $sourceSuppressions.Add([pscustomobject]@{
                path = ([IO.Path]::GetRelativePath($repoRoot, $sourceFile.FullName) -replace '\\', '/')
                line = $line
                token = $match.Value
            })
        }
    }
}
$findings = [Collections.Generic.List[object]]::new()
foreach ($fileNode in @($report.SelectNodes("/*[local-name()='pmd']/*[local-name()='file']"))) {
    $relativePath = Get-RelativeSourcePath ([string] $fileNode.name)
    foreach ($violation in @($fileNode.SelectNodes("./*[local-name()='violation']"))) {
        $message = Normalize-Message ([string] $violation.InnerText)
        $findings.Add([pscustomobject]@{
            path = $relativePath
            rule = [string] $violation.rule
            message = $message
            beginLine = [int] $violation.beginline
            endLine = [int] $violation.endline
            beginColumn = [int] $violation.begincolumn
            endColumn = [int] $violation.endcolumn
        })
    }
}

$exactGroups = @($findings | Group-Object path, rule, message, beginLine, endLine, beginColumn, endColumn)
$duplicateGroups = @($exactGroups | Where-Object Count -gt 1)
$uniqueFindings = @($exactGroups | ForEach-Object { $_.Group[0] })

$baseline = Get-Content -LiteralPath $baselinePath -Raw | ConvertFrom-Json
if ([int] $baseline.schemaVersion -ne 1 -or [string] $baseline.baseSha -notmatch '^[0-9a-f]{40}$') {
    throw 'El baseline PMD no tiene schemaVersion/baseSha válidos.'
}

$baselineByKey = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
$baselineTotal = 0L
foreach ($entry in @($baseline.findings)) {
    $path = ([string] $entry.path) -replace '\\', '/'
    $rule = [string] $entry.rule
    $message = Normalize-Message ([string] $entry.message)
    $count = [int64] $entry.count
    if ($path -notlike 'backend/src/main/java/*.java' -or
        [string]::IsNullOrWhiteSpace($rule) -or
        [string]::IsNullOrWhiteSpace($message) -or
        $count -le 0) {
        throw "Entrada inválida en baseline PMD: $path / $rule"
    }
    $key = Get-FindingKey $path $rule $message
    if ($baselineByKey.ContainsKey($key)) {
        throw "Entrada duplicada en baseline PMD: $path / $rule / $message"
    }
    $normalizedEntry = [pscustomobject]@{
        path = $path
        rule = $rule
        message = $message
        count = $count
    }
    $baselineByKey[$key] = $normalizedEntry
    $baselineTotal += $count
}
if ($baselineTotal -eq 0) {
    throw 'El baseline PMD está vacío; la deuda legacy declarada no fue cargada.'
}
if ([int64] $baseline.findingCount -ne $baselineTotal) {
    throw "El baseline PMD declara $($baseline.findingCount) findings, pero contiene $baselineTotal."
}

$currentByKey = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
foreach ($group in @($uniqueFindings | Group-Object path, rule, message)) {
    $sample = $group.Group[0]
    $key = Get-FindingKey $sample.path $sample.rule $sample.message
    $currentByKey[$key] = [pscustomobject]@{
        path = $sample.path
        rule = $sample.rule
        message = $sample.message
        count = [int64] $group.Count
        findings = @($group.Group | Sort-Object beginLine, beginColumn)
    }
}

$globalRegressions = [Collections.Generic.List[object]]::new()
$resolvedBaseline = [Collections.Generic.List[object]]::new()
foreach ($key in @($currentByKey.Keys | Sort-Object)) {
    $current = $currentByKey[$key]
    $allowed = if ($baselineByKey.ContainsKey($key)) { [int64] $baselineByKey[$key].count } else { 0L }
    if ($current.count -gt $allowed) {
        $globalRegressions.Add([pscustomobject]@{
            path = $current.path
            rule = $current.rule
            message = $current.message
            baselineCount = $allowed
            currentCount = $current.count
            addedCount = $current.count - $allowed
            locations = @($current.findings | ForEach-Object { "$($_.beginLine):$($_.beginColumn)" })
        })
    }
}
foreach ($key in @($baselineByKey.Keys | Sort-Object)) {
    $allowed = [int64] $baselineByKey[$key].count
    $current = if ($currentByKey.ContainsKey($key)) { [int64] $currentByKey[$key].count } else { 0L }
    if ($current -lt $allowed) {
        $entry = $baselineByKey[$key]
        $resolvedBaseline.Add([pscustomobject]@{
            path = $entry.path
            rule = $entry.rule
            message = $entry.message
            baselineCount = $allowed
            currentCount = $current
            resolvedCount = $allowed - $current
        })
    }
}

$changedLines = [Collections.Generic.Dictionary[string, Collections.Generic.HashSet[int]]]::new(
    [StringComparer]::OrdinalIgnoreCase)
$currentFile = $null
foreach ($line in $diff) {
    if ($line -match '^\+\+\+ b/(?<path>.+\.java)$') {
        $currentFile = $Matches.path -replace '\\', '/'
        if (-not $changedLines.ContainsKey($currentFile)) {
            $changedLines[$currentFile] = [Collections.Generic.HashSet[int]]::new()
        }
        continue
    }
    if ($null -ne $currentFile -and
        $line -match '^@@ -\d+(?:,\d+)? \+(?<start>\d+)(?:,(?<count>\d+))? @@') {
        $start = [int] $Matches.start
        $count = if ($Matches['count']) { [int] $Matches.count } else { 1 }
        for ($number = $start; $number -lt ($start + $count); $number++) {
            [void] $changedLines[$currentFile].Add($number)
        }
    }
}
foreach ($relativePath in $untracked | Where-Object { $_ -like '*.java' }) {
    $normalizedPath = $relativePath -replace '\\', '/'
    if (-not $changedLines.ContainsKey($normalizedPath)) {
        $changedLines[$normalizedPath] = [Collections.Generic.HashSet[int]]::new()
    }
    $sourcePath = Join-Path $repoRoot ($normalizedPath -replace '/', [IO.Path]::DirectorySeparatorChar)
    $sourceLineCount = @(Get-Content -LiteralPath $sourcePath).Count
    for ($number = 1; $number -le $sourceLineCount; $number++) {
        [void] $changedLines[$normalizedPath].Add($number)
    }
}

$diffRegressions = [Collections.Generic.List[object]]::new()
foreach ($finding in $uniqueFindings) {
    if (-not $changedLines.ContainsKey($finding.path)) { continue }
    $intersects = $false
    for ($number = $finding.beginLine; $number -le $finding.endLine; $number++) {
        if ($changedLines[$finding.path].Contains($number)) {
            $intersects = $true
            break
        }
    }
    if ($intersects) {
        $diffRegressions.Add($finding)
    }
}

$globalRegressionCount = 0L
foreach ($regression in $globalRegressions) {
    $globalRegressionCount += [int64] $regression.addedCount
}
$resolvedBaselineCount = 0L
foreach ($resolved in $resolvedBaseline) {
    $resolvedBaselineCount += [int64] $resolved.resolvedCount
}
$passed = $configurationErrors.Count -eq 0 -and
    $suppressedViolations.Count -eq 0 -and
    $sourceSuppressions.Count -eq 0 -and
    $duplicateGroups.Count -eq 0 -and
    $globalRegressionCount -eq 0 -and
    $resolvedBaselineCount -eq 0 -and
    $diffRegressions.Count -eq 0

$status = [ordered]@{
    schemaVersion = 1
    passed = $passed
    base = $Base
    resolvedBase = $resolvedBase
    baselineBaseSha = [string] $baseline.baseSha
    pmdVersion = [string] $report.DocumentElement.version
    totalFindings = $uniqueFindings.Count
    baselineFindings = $baselineTotal
    configurationErrors = $configurationErrors.Count
    suppressedViolations = $suppressedViolations.Count
    sourceSuppressions = $sourceSuppressions.Count
    duplicateFindingGroups = $duplicateGroups.Count
    globalRegressionCount = $globalRegressionCount
    resolvedBaselineCount = $resolvedBaselineCount
    diffRegressionCount = $diffRegressions.Count
    changedSourceFiles = @($changedLines.Keys | Sort-Object)
    globalRegressions = @($globalRegressions)
    resolvedBaseline = @($resolvedBaseline)
    diffRegressions = @($diffRegressions | Sort-Object path, beginLine, beginColumn)
    sourceSuppressionLocations = @($sourceSuppressions | Sort-Object path, line)
}
[void] [IO.Directory]::CreateDirectory((Split-Path -Parent $statusPath))
[IO.File]::WriteAllText(
    $statusPath,
    ($status | ConvertTo-Json -Depth 8),
    [Text.UTF8Encoding]::new($false))

if (-not $passed) {
    $problems = [Collections.Generic.List[string]]::new()
    if ($configurationErrors.Count -gt 0) { $problems.Add("$($configurationErrors.Count) errores de configuración/procesamiento PMD") }
    if ($suppressedViolations.Count -gt 0) { $problems.Add("$($suppressedViolations.Count) violaciones PMD suprimidas") }
    if ($sourceSuppressions.Count -gt 0) { $problems.Add("$($sourceSuppressions.Count) supresiones PMD/NOPMD en fuentes") }
    if ($duplicateGroups.Count -gt 0) { $problems.Add("$($duplicateGroups.Count) findings PMD duplicados exactamente") }
    if ($globalRegressionCount -gt 0) { $problems.Add("$globalRegressionCount findings por encima del baseline") }
    if ($resolvedBaselineCount -gt 0) { $problems.Add("$resolvedBaselineCount findings resueltos aún presentes en el baseline") }
    if ($diffRegressions.Count -gt 0) { $problems.Add("$($diffRegressions.Count) findings sobre líneas modificadas") }
    throw "Backend static analysis: FAIL ($($problems -join '; ')). Evidencia: $statusPath"
}

Write-Host "Backend static analysis: PASS ($($uniqueFindings.Count) findings legacy declarados, base $Base)."
