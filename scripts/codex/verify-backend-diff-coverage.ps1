[CmdletBinding()]
param(
    [string] $Base = 'origin/main',
    [ValidateRange(0, 100)]
    [double] $Minimum = 90
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$jacocoPath = Join-Path $repoRoot 'backend\target\site\jacoco\jacoco.xml'
$outputPath = Join-Path $repoRoot 'backend\target\diff-coverage.json'

if (-not (Test-Path -LiteralPath $jacocoPath -PathType Leaf)) {
    throw "Falta el reporte JaCoCo requerido para diff coverage: $jacocoPath"
}

Push-Location $repoRoot
try {
    & git rev-parse --verify --quiet "$Base`^{commit}" *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "No se puede resolver la base Git de diff coverage: $Base"
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

$changedByFile = [Collections.Generic.Dictionary[string, Collections.Generic.HashSet[int]]]::new(
    [StringComparer]::OrdinalIgnoreCase)
$currentFile = $null

foreach ($line in $diff) {
    if ($line -match '^\+\+\+ b/(?<path>.+\.java)$') {
        $currentFile = $Matches.path -replace '\\', '/'
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

foreach ($relativePath in $untracked | Where-Object { $_ -like '*.java' }) {
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

$jacoco = [xml](Get-Content -LiteralPath $jacocoPath -Raw)
$sourceReports = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($package in @($jacoco.report.package)) {
    foreach ($sourceFile in @($package.sourcefile)) {
        $relativePath = "backend/src/main/java/$($package.name)/$($sourceFile.name)"
        $sourceReports[$relativePath] = $sourceFile
    }
}

$totalExecutable = 0L
$coveredExecutable = 0L
$fileResults = [Collections.Generic.List[object]]::new()

foreach ($entry in $changedByFile.GetEnumerator() | Sort-Object Key) {
    if (-not $sourceReports.ContainsKey($entry.Key)) {
        throw "JaCoCo no incluyó la fuente backend modificada: $($entry.Key)"
    }

    $lineReports = [Collections.Generic.Dictionary[int, object]]::new()
    foreach ($lineReport in @($sourceReports[$entry.Key].line)) {
        $lineReports[[int]$lineReport.nr] = $lineReport
    }

    $fileTotal = 0L
    $fileCovered = 0L
    foreach ($lineNumber in $entry.Value) {
        if (-not $lineReports.ContainsKey($lineNumber)) { continue }
        $fileTotal++
        if ([int64]$lineReports[$lineNumber].ci -gt 0) { $fileCovered++ }
    }

    $totalExecutable += $fileTotal
    $coveredExecutable += $fileCovered
    $fileResults.Add([ordered]@{
        path = $entry.Key
        executableChangedLines = $fileTotal
        coveredChangedLines = $fileCovered
    })
}

$applicable = $changedByFile.Count -gt 0 -and $totalExecutable -gt 0
$percentage = if ($totalExecutable -eq 0) { $null } else {
    [Math]::Round(100.0 * $coveredExecutable / $totalExecutable, 2)
}
$result = [ordered]@{
    base = $Base
    minimum = $Minimum
    applicable = $applicable
    changedJavaFiles = $changedByFile.Count
    executableChangedLines = $totalExecutable
    coveredChangedLines = $coveredExecutable
    percentage = $percentage
    files = $fileResults
}

[void][IO.Directory]::CreateDirectory((Split-Path -Parent $outputPath))
[IO.File]::WriteAllText($outputPath, ($result | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))

if (-not $applicable) {
    Write-Host 'Backend diff coverage: NOT_APPLICABLE (no hay líneas Java ejecutables modificadas).'
    return
}
if ($percentage -lt $Minimum) {
    throw "Backend diff coverage obtuvo $percentage% y requiere al menos $Minimum%."
}

Write-Host "Backend diff coverage: PASS ($percentage%, base $Base)."
