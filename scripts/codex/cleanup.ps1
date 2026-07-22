$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$rootPrefix = $repoRoot.TrimEnd('\') + '\'
$temporaryPaths = @(
    (Join-Path $repoRoot ".cache\tmp"),
    (Join-Path $repoRoot "frontend\.vite")
)

foreach ($path in $temporaryPaths) {
    $absolutePath = [IO.Path]::GetFullPath($path)
    if (-not $absolutePath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "La ruta de limpieza está fuera del worktree: $absolutePath"
    }
    if (Test-Path -LiteralPath $absolutePath) {
        Remove-Item -LiteralPath $absolutePath -Recurse -Force
        Write-Host "Eliminado: $absolutePath"
    }
}

Write-Host "Limpieza finalizada. target, node_modules, contenedores y volúmenes no fueron modificados."
