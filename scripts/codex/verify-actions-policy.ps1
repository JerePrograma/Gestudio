[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$workflowRoot = Join-Path $repoRoot '.github\workflows'
$violations = [Collections.Generic.List[string]]::new()
$immutable = '^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+(?:/[a-zA-Z0-9_.-]+)*@[0-9a-f]{40}(?:\s+#.*)?$'

foreach ($workflow in Get-ChildItem -LiteralPath $workflowRoot -File |
        Where-Object { $_.Extension -in '.yml', '.yaml' } |
        Sort-Object Name) {
    $lines = Get-Content -LiteralPath $workflow.FullName
    $topLevelPermissions = @($lines | Where-Object { $_ -match '^permissions:\s*$' })
    if ($topLevelPermissions.Count -ne 1) {
        $violations.Add("$($workflow.Name): falta permissions top-level explícito")
    }
    if ($lines | Where-Object { $_ -match '^\s*permissions:\s*(write-all|\{.*write.*\})\s*$' }) {
        $violations.Add("$($workflow.Name): permissions de escritura globales no permitidos")
    }
    if ($lines | Where-Object { $_ -match '^\s{2}[a-z-]+:\s*write\s*$' }) {
        $violations.Add("$($workflow.Name): permissions top-level de escritura no permitidos")
    }
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match '^\s*-?\s*uses:\s*(?<reference>\S.*)$') {
            $reference = $Matches.reference.Trim()
            if ($reference.StartsWith('./')) { continue }
            if ($reference -notmatch $immutable) {
                $violations.Add("$($workflow.Name):$($index + 1): action no pinneada a SHA: $reference")
            }
        }
        foreach ($match in [regex]::Matches($lines[$index], '(?<path>\./scripts/[A-Za-z0-9_./-]+\.ps1)')) {
            $relativePath = $match.Groups['path'].Value.Substring(2).Replace(
                '/', [IO.Path]::DirectorySeparatorChar)
            $scriptPath = Join-Path $repoRoot $relativePath
            if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
                $violations.Add("$($workflow.Name):$($index + 1): script local inexistente: $($match.Groups['path'].Value)")
            }
        }
    }
}

if ($violations.Count -gt 0) {
    $violations | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    throw "La política de GitHub Actions detectó $($violations.Count) violaciones."
}

Write-Host 'GitHub Actions policy: PASS (permissions explícitos y referencias SHA inmutables).'
