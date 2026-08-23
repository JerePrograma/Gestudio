[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('BackendCoverage', 'BackendStatic', 'BackendMutationGlobal',
        'BackendMutationCritical', 'BackendDependencyAudit', 'BackendSbom', 'FrontendCoverage',
        'FrontendDiffCoverage', 'FrontendDuplication', 'FrontendSbom')]
    [string] $Scope,

    [string] $MutationExecutionMarker
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$frontendInventoryVerifier = Join-Path $repoRoot 'frontend\scripts\verify-coverage-source-inventory.mjs'

function Require-File {
    param([Parameter(Mandatory)][string] $RelativePath)

    $path = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Falta el artefacto obligatorio: $RelativePath"
    }
    $item = Get-Item -LiteralPath $path
    if ($item.Length -eq 0) {
        throw "El artefacto obligatorio está vacío: $RelativePath"
    }
    return $item.FullName
}

function Read-JsonArtifact {
    param([Parameter(Mandatory)][string] $RelativePath)

    $path = Require-File $RelativePath
    return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}

function Read-XmlArtifact {
    param([Parameter(Mandatory)][string] $RelativePath)

    $path = Require-File $RelativePath
    return [xml](Get-Content -LiteralPath $path -Raw)
}

function Read-MutationExecutionMarker {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][ValidateSet('global', 'critical')][string] $ExpectedScope
    )

    if (-not [IO.Path]::IsPathFullyQualified($Path) -or
        -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw 'La verificación PIT requiere el marcador absoluto de esta ejecución.'
    }
    $item = Get-Item -LiteralPath $Path
    if ($item.Length -eq 0) {
        throw 'El marcador de ejecución PIT está vacío.'
    }
    $marker = Get-Content -LiteralPath $item.FullName -Raw | ConvertFrom-Json
    foreach ($property in 'schemaVersion', 'executionId', 'scope', 'status',
        'startedAtUtc', 'completedAtUtc') {
        if ($marker.PSObject.Properties.Name -notcontains $property) {
            throw "El marcador de ejecución PIT no contiene $property."
        }
    }
    $executionId = [guid]::Empty
    if ([int]$marker.schemaVersion -ne 1 -or
        -not [guid]::TryParseExact([string]$marker.executionId, 'N', [ref]$executionId) -or
        [string]$marker.scope -ne $ExpectedScope -or
        [string]$marker.status -ne 'COMPLETED') {
        throw "El marcador PIT no acredita una ejecución $ExpectedScope completa."
    }
    try {
        $startedAt = [DateTimeOffset]::Parse(
            [string]$marker.startedAtUtc,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind)
        $completedAt = [DateTimeOffset]::Parse(
            [string]$marker.completedAtUtc,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind)
    }
    catch {
        throw 'El marcador PIT no contiene timestamps ISO-8601 válidos.'
    }
    if ($startedAt.Offset -ne [TimeSpan]::Zero -or $completedAt.Offset -ne [TimeSpan]::Zero -or
        $completedAt -lt $startedAt) {
        throw 'El marcador PIT no contiene un intervalo UTC válido.'
    }
    return [pscustomobject]@{
        StartedAtUtc = $startedAt.UtcDateTime
        CompletedAtUtc = $completedAt.UtcDateTime
    }
}

function Require-FreshArtifact {
    param(
        [Parameter(Mandatory)][string] $RelativePath,
        [Parameter(Mandatory)][datetime] $StartedAtUtc,
        [Parameter(Mandatory)][datetime] $CompletedAtUtc
    )

    $path = Require-File $RelativePath
    $modifiedAt = (Get-Item -LiteralPath $path).LastWriteTimeUtc
    if ($modifiedAt -lt $StartedAtUtc.AddSeconds(-1) -or
        $modifiedAt -gt $CompletedAtUtc.AddSeconds(1)) {
        throw "$RelativePath no pertenece al intervalo de esta ejecución PIT."
    }
    return $path
}

function Get-MutationMetrics {
    param(
        [Parameter(Mandatory)][object[]] $MutationNodes,
        [Parameter(Mandatory)][string] $Description
    )

    if ($MutationNodes.Count -eq 0) {
        throw "$Description no contiene mutantes."
    }
    $detectedStatuses = @('KILLED', 'TIMED_OUT', 'NON_VIABLE', 'MEMORY_ERROR', 'RUN_ERROR')
    $undetectedStatuses = @('SURVIVED', 'NO_COVERAGE')
    $detected = 0L
    $survived = 0L
    $noCoverage = 0L
    foreach ($mutation in $MutationNodes) {
        $status = [string]$mutation.GetAttribute('status')
        if ($status -in 'NOT_STARTED', 'STARTED' -or
            ($status -notin $detectedStatuses -and $status -notin $undetectedStatuses)) {
            throw "$Description contiene un estado PIT no aceptable: $status."
        }
        $reportedDetected = [string]$mutation.GetAttribute('detected')
        if ($reportedDetected -notin 'true', 'false') {
            throw "$Description contiene un atributo detected inválido."
        }
        $isDetected = $status -in $detectedStatuses
        if ([bool]::Parse($reportedDetected) -ne $isDetected) {
            throw "$Description contradice status=$status con detected=$reportedDetected."
        }
        if ($isDetected) { $detected++ }
        elseif ($status -eq 'SURVIVED') { $survived++ }
        else { $noCoverage++ }
    }

    $total = [int64]$MutationNodes.Count
    $covered = $detected + $survived
    return [pscustomobject]@{
        total = $total
        detected = $detected
        survived = $survived
        noCoverage = $noCoverage
        covered = $covered
        mutationScore = 100.0 * $detected / $total
        testStrength = if ($covered -eq 0) { 0.0 } else { 100.0 * $detected / $covered }
    }
}

function Require-MutationScores {
    param(
        [Parameter(Mandatory)] $Metrics,
        [Parameter(Mandatory)][double] $MinimumMutation,
        [Parameter(Mandatory)][double] $MinimumTestStrength,
        [Parameter(Mandatory)][string] $Description
    )

    if ([int64]$Metrics.total -le 0 -or [int64]$Metrics.covered -le 0) {
        throw "$Description no midió mutantes ejecutables y cubiertos."
    }
    if ([double]$Metrics.mutationScore -lt $MinimumMutation -or
        [double]$Metrics.testStrength -lt $MinimumTestStrength) {
        throw ("{0}: mutation={1:N2}% (mínimo {2}%), test-strength={3:N2}% " +
            "(mínimo {4}%)." -f $Description, $Metrics.mutationScore, $MinimumMutation,
            $Metrics.testStrength, $MinimumTestStrength)
    }
    Write-Host ("{0}: {1} mutantes, mutation={2:N2}%, test-strength={3:N2}%." -f
        $Description, $Metrics.total, $Metrics.mutationScore, $Metrics.testStrength)
}

function Require-CycloneDxBom {
    param([Parameter(Mandatory)][string] $RelativePath)

    $bom = Read-JsonArtifact $RelativePath
    if ($bom.bomFormat -ne 'CycloneDX') {
        throw "$RelativePath no declara bomFormat CycloneDX."
    }
    if (@($bom.components).Count -eq 0) {
        throw "$RelativePath no contiene componentes."
    }
}

function Require-Percentage {
    param(
        [Parameter(Mandatory)] $Metric,
        [Parameter(Mandatory)][double] $Minimum,
        [Parameter(Mandatory)][string] $Description
    )

    if ([int64]$Metric.total -le 0) {
        throw "$Description no midió elementos ejecutables."
    }
    if ([double]$Metric.pct -lt $Minimum) {
        throw "$Description obtuvo $($Metric.pct)% y requiere al menos $Minimum%."
    }
}

function Get-CoverageEntry {
    param(
        [Parameter(Mandatory)] $Summary,
        [Parameter(Mandatory)][string] $PathSuffix
    )

    $entry = $Summary.PSObject.Properties |
        Where-Object { ($_.Name -replace '\\', '/') -like "*$PathSuffix" } |
        Select-Object -First 1
    if ($null -eq $entry) {
        throw "El resumen de cobertura no contiene $PathSuffix."
    }
    return $entry.Value
}

switch ($Scope) {
    'BackendCoverage' {
        $jacoco = Read-XmlArtifact 'backend\target\site\jacoco\jacoco.xml'
        $jacocoRoot = $jacoco.DocumentElement
        $lineCounter = @($jacocoRoot.SelectNodes("counter[@type='LINE']"))
        if ($lineCounter.Count -ne 1 -or
            ([int64]$lineCounter[0].covered + [int64]$lineCounter[0].missed) -eq 0) {
            throw 'JaCoCo no informó líneas backend ejecutables.'
        }
        $packageNames = @($jacocoRoot.SelectNodes('package') |
            ForEach-Object { $_.GetAttribute('name') -replace '/', '.' })
        foreach ($pattern in 'gestudio.platform*', 'gestudio.tenancy*', 'gestudio.infra.seguridad*') {
            if (@($packageNames | Where-Object { $_ -like $pattern }).Count -eq 0) {
                throw "JaCoCo no informó paquetes que coincidan con la regla crítica $pattern."
            }
        }
        $classNames = @($jacocoRoot.SelectNodes('package/class') |
            ForEach-Object { $_.GetAttribute('name') -replace '/', '.' })
        foreach ($pattern in 'gestudio.infra.seguridad.SecurityConfigurations*',
            'gestudio.infra.seguridad.SecurityFilter*') {
            if (@($classNames | Where-Object { $_ -like $pattern }).Count -eq 0) {
                throw "JaCoCo no informó clases que coincidan con la regla de autorización $pattern."
            }
        }

        $surefireRoot = Join-Path $repoRoot 'backend\target\surefire-reports'
        $surefireReports = @(Get-ChildItem -LiteralPath $surefireRoot -Filter 'TEST-*.xml' -File -ErrorAction SilentlyContinue)
        if ($surefireReports.Count -eq 0) {
            throw 'Surefire no produjo suites XML.'
        }
        $executedTests = 0L
        foreach ($report in $surefireReports) {
            $suite = [xml](Get-Content -LiteralPath $report.FullName -Raw)
            $executedTests += [int64]$suite.DocumentElement.GetAttribute('tests')
        }
        if ($executedTests -eq 0) {
            throw 'Surefire produjo reportes, pero no ejecutó tests.'
        }

        $features = @(Read-JsonArtifact 'backend\target\cucumber-reports\control-plane.json')
        $scenarios = @($features | ForEach-Object { $_.elements } |
            Where-Object { $_.type -eq 'scenario' })
        if ($scenarios.Count -lt 6) {
            throw "Cucumber ejecutó $($scenarios.Count) escenarios; el contrato exige al menos 6."
        }
        $nonPassingSteps = @($scenarios | ForEach-Object { $_.steps } |
            Where-Object { $_.result.status -ne 'passed' })
        if ($nonPassingSteps.Count -gt 0) {
            throw "Cucumber informó $($nonPassingSteps.Count) pasos no aprobados."
        }
    }
    'BackendStatic' {
        $pmd = Read-XmlArtifact 'backend\target\pmd.xml'
        if ($pmd.DocumentElement.LocalName -ne 'pmd') {
            throw 'El reporte PMD no tiene la raíz esperada.'
        }
        $cpd = Read-XmlArtifact 'backend\target\cpd.xml'
        if ($cpd.DocumentElement.LocalName -ne 'pmd-cpd') {
            throw 'El reporte CPD no tiene la raíz esperada.'
        }
        $staticStatus = Read-JsonArtifact 'backend\target\pmd-baseline-status.json'
        if ([int] $staticStatus.schemaVersion -ne 1 -or -not [bool] $staticStatus.passed) {
            throw 'La política PMD baseline/diff no produjo estado PASS.'
        }
        if ([int64] $staticStatus.totalFindings -ne [int64] $staticStatus.baselineFindings -or
            [int64] $staticStatus.configurationErrors -ne 0 -or
            [int64] $staticStatus.suppressedViolations -ne 0 -or
            [int64] $staticStatus.sourceSuppressions -ne 0 -or
            [int64] $staticStatus.duplicateFindingGroups -ne 0 -or
            [int64] $staticStatus.globalRegressionCount -ne 0 -or
            [int64] $staticStatus.resolvedBaselineCount -ne 0 -or
            [int64] $staticStatus.diffRegressionCount -ne 0) {
            throw 'El estado PMD no demuestra baseline exacto y cero regresiones.'
        }
    }
    { $_ -in 'BackendMutationGlobal', 'BackendMutationCritical' } {
        $kind = if ($Scope -eq 'BackendMutationGlobal') { 'global' } else { 'critical' }
        if ([string]::IsNullOrWhiteSpace($MutationExecutionMarker)) {
            throw "La verificación PIT $kind requiere el marcador de la ejecución actual."
        }
        $execution = Read-MutationExecutionMarker -Path $MutationExecutionMarker `
            -ExpectedScope $kind
        $xmlRelativePath = "backend\target\pit-reports\$kind\mutations.xml"
        $htmlRelativePath = "backend\target\pit-reports\$kind\index.html"
        [void](Require-FreshArtifact -RelativePath $xmlRelativePath `
            -StartedAtUtc $execution.StartedAtUtc -CompletedAtUtc $execution.CompletedAtUtc)
        [void](Require-FreshArtifact -RelativePath $htmlRelativePath `
            -StartedAtUtc $execution.StartedAtUtc -CompletedAtUtc $execution.CompletedAtUtc)
        $mutations = Read-XmlArtifact $xmlRelativePath
        if ($mutations.DocumentElement.LocalName -ne 'mutations') {
            throw "El XML PIT $kind no tiene la raíz mutations esperada."
        }
        $mutationNodes = @($mutations.SelectNodes("//*[local-name()='mutation']"))
        $aggregateMinimumMutation = if ($kind -eq 'global') { 80 } else { 90 }
        $aggregateMinimumStrength = if ($kind -eq 'global') { 85 } else { 90 }
        $aggregate = Get-MutationMetrics -MutationNodes $mutationNodes `
            -Description "PIT $kind agregado"
        Require-MutationScores -Metrics $aggregate `
            -MinimumMutation $aggregateMinimumMutation `
            -MinimumTestStrength $aggregateMinimumStrength `
            -Description "PIT $kind agregado"

        if ($kind -eq 'critical') {
            $families = @(
                [pscustomobject]@{ Name = 'platform'; Pattern = 'gestudio.platform.*' }
                [pscustomobject]@{ Name = 'tenancy'; Pattern = 'gestudio.tenancy.*' }
                [pscustomobject]@{ Name = 'security'; Pattern = 'gestudio.infra.seguridad.*' }
                [pscustomobject]@{ Name = 'Usuario'; Pattern = 'gestudio.entidades.Usuario*' }
                [pscustomobject]@{ Name = 'ConfiguracionCors'; Pattern = 'gestudio.infra.configuracion.ConfiguracionCors*' }
                [pscustomobject]@{ Name = 'MultitenancyConfigurationGuard'; Pattern = 'gestudio.infra.configuracion.MultitenancyConfigurationGuard*' }
                [pscustomobject]@{ Name = 'TratadorDeErrores'; Pattern = 'gestudio.infra.errores.TratadorDeErrores*' }
            )
            foreach ($family in $families) {
                $familyNodes = @($mutationNodes | Where-Object {
                    $classNode = $_.SelectSingleNode("./*[local-name()='mutatedClass']")
                    $null -ne $classNode -and $classNode.InnerText -like $family.Pattern
                })
                $metrics = Get-MutationMetrics -MutationNodes $familyNodes `
                    -Description "PIT crítico $($family.Name)"
                Require-MutationScores -Metrics $metrics -MinimumMutation 90 `
                    -MinimumTestStrength 90 -Description "PIT crítico $($family.Name)"
            }
        }
    }
    'BackendSbom' {
        Require-CycloneDxBom 'backend\target\classes\META-INF\sbom\application.cdx.json'
    }
    'BackendDependencyAudit' {
        $html = Require-File 'backend\target\dependency-check-report.html'
        $report = Read-JsonArtifact 'backend\target\dependency-check-report.json'
        if ((Get-Item -LiteralPath $html).Length -lt 100) {
            throw 'El reporte HTML de Dependency-Check no contiene evidencia suficiente.'
        }
        if ($null -eq $report.reportSchema -or $null -eq $report.dependencies) {
            throw 'El reporte JSON de Dependency-Check no tiene la estructura esperada.'
        }
        if (@($report.dependencies).Count -eq 0) {
            throw 'Dependency-Check no informó dependencias analizadas.'
        }
    }
    'FrontendCoverage' {
        $coverageMap = Require-File 'frontend\coverage\release\coverage-final.json'
        $inventoryEvidence = Join-Path $repoRoot 'frontend\coverage\release\source-inventory.json'
        & node $frontendInventoryVerifier --coverage $coverageMap --output $inventoryEvidence
        if ($LASTEXITCODE -ne 0) {
            throw "El inventario fail-closed de cobertura frontend falló con código $LASTEXITCODE."
        }
        $summary = Read-JsonArtifact 'frontend\coverage\release\coverage-summary.json'
        Require-Percentage $summary.total.lines 85 'Cobertura frontend global de líneas'
        Require-Percentage $summary.total.branches 80 'Cobertura frontend global de branches'
        Require-Percentage $summary.total.statements 85 'Cobertura frontend global de statements'

        foreach ($suffix in 'src/platform/platformApi.ts',
            'src/platform/StepUpProvider.tsx',
            'src/platform/stepUpContext.ts',
            'src/api/authSession.ts',
            'src/api/axiosConfig.ts',
            'src/hooks/context/auth-context.ts',
            'src/hooks/context/authContext.tsx',
            'src/hooks/context/useAuth.ts',
            'src/rutas/ProtectedRoute.tsx') {
            $entry = Get-CoverageEntry $summary $suffix
            Require-Percentage $entry.lines 90 "Cobertura crítica de líneas para $suffix"
        }
    }
    'FrontendDiffCoverage' {
        $status = Read-JsonArtifact 'frontend\coverage\diff-coverage-status.json'
        $evidence = Read-JsonArtifact 'frontend\coverage\diff-coverage.json'
        if (-not [bool]$status.applicable) {
            $reason = [string]$status.reason
            if ([string]::IsNullOrWhiteSpace($reason) -or [string]$evidence.reason -ne $reason) {
                throw 'Diff coverage frontend no aplicable carece de una razón consistente.'
            }
            if ([bool]$evidence.applicable) {
                throw 'La evidencia de diff coverage frontend contradice su estado no aplicable.'
            }
            $statusFiles = @($status.changedSourceFiles | ForEach-Object { [string]$_ -replace '\\', '/' })
            $evidenceFiles = @($evidence.changedSourceFiles | ForEach-Object { [string]$_ -replace '\\', '/' })
            if (@(Compare-Object $statusFiles $evidenceFiles).Count -ne 0) {
                throw 'La evidencia de diff coverage frontend no conserva las fuentes modificadas del estado.'
            }
            if ($statusFiles.Count -eq 0) {
                if ($reason -ne 'NO_CHANGED_TYPESCRIPT_SOURCES') {
                    throw 'Diff coverage sin fuentes TypeScript usa una razón no reconocida.'
                }
                break
            }
            if ($reason -ne 'NO_EXECUTABLE_CHANGED_HUNKS') {
                throw 'Diff coverage con fuentes modificadas usa una razón no reconocida.'
            }
            $diffCoverageMap = Require-File 'frontend\coverage\diff\coverage-final.json'
            $diffStatusPath = Require-File 'frontend\coverage\diff-coverage-status.json'
            $diffInventoryEvidence = Join-Path $repoRoot 'frontend\coverage\diff\source-inventory.json'
            & node $frontendInventoryVerifier --coverage $diffCoverageMap --status $diffStatusPath `
                --output $diffInventoryEvidence
            if ($LASTEXITCODE -ne 0) {
                throw "El inventario fail-closed de diff coverage frontend falló con código $LASTEXITCODE."
            }
            $measured = @($evidence.files | ForEach-Object { [string]$_.path -replace '\\', '/' })
            foreach ($changedFile in $statusFiles) {
                if ($changedFile -notin $measured) {
                    throw "Diff coverage no clasificó la fuente no ejecutable modificada: $changedFile"
                }
            }
            foreach ($metricName in 'lines', 'branches', 'statements') {
                if ([int64]$evidence.metrics.$metricName.total -ne 0) {
                    throw "Diff coverage se declaró no aplicable con $metricName ejecutables."
                }
            }
            $executable = @($evidence.files | Measure-Object -Property executableChangedLines -Sum).Sum
            if ([int64]$executable -ne 0) {
                throw 'Diff coverage se declaró no aplicable con líneas ejecutables modificadas.'
            }
            break
        }
        if (@($status.changedSourceFiles).Count -eq 0) {
            throw 'Diff coverage frontend se declaró aplicable sin fuentes modificadas.'
        }
        $diffCoverageMap = Require-File 'frontend\coverage\diff\coverage-final.json'
        $diffStatusPath = Require-File 'frontend\coverage\diff-coverage-status.json'
        $diffInventoryEvidence = Join-Path $repoRoot 'frontend\coverage\diff\source-inventory.json'
        & node $frontendInventoryVerifier --coverage $diffCoverageMap --status $diffStatusPath `
            --output $diffInventoryEvidence
        if ($LASTEXITCODE -ne 0) {
            throw "El inventario fail-closed de diff coverage frontend falló con código $LASTEXITCODE."
        }
        if (-not [bool]$evidence.applicable -or [double]$evidence.minimum -ne 90) {
            throw 'La evidencia de diff coverage frontend no aplica el umbral contractual de 90%.'
        }
        $measured = @($evidence.files | ForEach-Object { [string]$_.path -replace '\\', '/' })
        foreach ($changedFile in @($status.changedSourceFiles)) {
            $relative = [string]$changedFile -replace '\\', '/'
            if (@($measured | Where-Object { $_ -eq $relative }).Count -eq 0) {
                throw "Diff coverage no midió la fuente modificada: $changedFile"
            }
        }
        foreach ($metricName in 'lines', 'branches', 'statements') {
            $metric = $evidence.metrics.$metricName
            if ([int64]$metric.total -eq 0) { continue }
            $coverageMetric = [pscustomobject]@{
                total = [int64]$metric.total
                pct = [double]$metric.percentage
            }
            Require-Percentage $coverageMetric 90 "Diff coverage frontend de $metricName"
        }
        $executable = @($evidence.files | Measure-Object -Property executableChangedLines -Sum).Sum
        if ([int64]$executable -eq 0) {
            throw 'Diff coverage frontend no informó ejecutables modificados medibles.'
        }
    }
    'FrontendDuplication' {
        $report = Read-JsonArtifact 'frontend\quality-reports\jscpd\jscpd-report.json'
        if ($null -eq $report.statistics -or $null -eq $report.statistics.total -or
            [int64]$report.statistics.total.sources -eq 0) {
            throw 'jscpd no informó fuentes analizadas.'
        }
        $package = Read-JsonArtifact 'frontend\package.json'
        $command = [string]$package.scripts.'quality:duplication'
        $requiredIgnore = '--ignore "**/*.test.ts,**/*.test.tsx,**/*.spec.ts,**/*.spec.tsx"'
        if (-not $command.Contains($requiredIgnore, [StringComparison]::Ordinal) -or
            $command -notmatch '(?:^|\s)--threshold\s+2(?:\s|$)') {
            throw 'El gate jscpd debe medir fuentes productivas con threshold 2% y excluir sólo tests/spec.'
        }
        if ([double]$report.statistics.total.percentage -gt 2.0) {
            throw "La duplicación productiva frontend excede 2%: $($report.statistics.total.percentage)%"
        }
        foreach ($clone in @($report.duplicates)) {
            foreach ($path in @([string]$clone.firstFile.name, [string]$clone.secondFile.name)) {
                if ($path -match '\.(?:test|spec)\.(?:ts|tsx)$') {
                    throw "El reporte productivo jscpd contiene un archivo de tests: $path"
                }
            }
        }
    }
    'FrontendSbom' {
        Require-CycloneDxBom 'frontend\frontend-sbom.cdx.json'
    }
}

Write-Host "Quality artifact verification ($Scope): PASS"
