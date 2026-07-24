[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://localhost:18081',
    [string]$BackendUrl = 'http://localhost:18080',
    [Parameter(Mandatory)]
    [string]$OutputDirectory,
    [switch]$ApplicationStartedByGenerator
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Manual.Common.ps1')

$repoRoot = Get-ManualRepositoryRoot
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)

$manifestPath = Join-Path $repoRoot 'docs\manual-usuarios\manifest.json'
$templatePath = Join-Path $repoRoot 'docs\manual-usuarios\templates\manual.html'
$cssPath = Join-Path $repoRoot 'docs\manual-usuarios\templates\manual.css'
$flowPath = Join-Path $PSScriptRoot 'flows\render-manual.cjs'
$screenshotDirectory = Join-Path $OutputDirectory 'screenshots'

foreach ($path in @($manifestPath, $templatePath, $cssPath, $flowPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "No existe el archivo requerido: $path"
    }
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$template = Get-Content -LiteralPath $templatePath -Raw
$css = Get-Content -LiteralPath $cssPath -Raw

function ConvertTo-HtmlText {
    param([AllowNull()][object]$Value)

    return [Net.WebUtility]::HtmlEncode([string]$Value)
}

function Get-ManifestScreenshots {
    param([Parameter(Mandatory)][object]$Item)

    $names = [Collections.Generic.List[string]]::new()

    if ($null -ne $Item.screenshot -and -not [string]::IsNullOrWhiteSpace([string]$Item.screenshot)) {
        $names.Add([string]$Item.screenshot)
    }

    if ($Item.PSObject.Properties.Name -contains 'screenshots' -and $null -ne $Item.screenshots) {
        foreach ($name in @($Item.screenshots)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$name) -and -not $names.Contains([string]$name)) {
                $names.Add([string]$name)
            }
        }
    }

    return @($names)
}

$orderedItems = @($manifest.items | Sort-Object order)
$indexEntries = [Collections.Generic.List[string]]::new()
$sections = [Collections.Generic.List[string]]::new()

foreach ($item in $orderedItems) {
    $contentPath = Join-Path (Join-Path $repoRoot 'docs\manual-usuarios') ([string]$item.content)

    if (-not (Test-Path -LiteralPath $contentPath -PathType Leaf)) {
        throw "No existe el contenido declarado para '$($item.id)': $contentPath"
    }

    $content = Get-Content -LiteralPath $contentPath -Raw
    $itemId = ConvertTo-HtmlText $item.id
    $title = ConvertTo-HtmlText $item.title
    $role = ConvertTo-HtmlText $item.role
    $routeOrFlow = if ($null -ne $item.route -and -not [string]::IsNullOrWhiteSpace([string]$item.route)) {
        "Ruta: $(ConvertTo-HtmlText $item.route)"
    }
    elseif ($null -ne $item.flow -and -not [string]::IsNullOrWhiteSpace([string]$item.flow)) {
        "Flujo: $(ConvertTo-HtmlText $item.flow)"
    }
    else {
        'Referencia operativa'
    }

    $indexEntries.Add("<li><a href='#$itemId'><span>$($item.order.ToString('00'))</span>$title</a></li>")

    $figures = [Collections.Generic.List[string]]::new()
    foreach ($screenshotName in Get-ManifestScreenshots -Item $item) {
        if ([IO.Path]::GetFileName($screenshotName) -ne $screenshotName) {
            throw "Nombre de captura inválido en manifest: $screenshotName"
        }

        $screenshotPath = Join-Path $screenshotDirectory $screenshotName
        if (-not (Test-Path -LiteralPath $screenshotPath -PathType Leaf)) {
            if ([bool]$item.required) {
                throw "Falta la captura requerida: $screenshotName"
            }

            continue
        }

        $base64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($screenshotPath))
        $caption = ConvertTo-HtmlText ([IO.Path]::GetFileNameWithoutExtension($screenshotName).Replace('-', ' '))
        $figures.Add("<figure class='screen-figure'><img class='screen' src='data:image/png;base64,$base64' alt='Captura real: $title'><figcaption>$caption</figcaption></figure>")
    }

    $sectionClass = if ($item.id -eq 'portada') { 'manual-section cover-section' } else { 'manual-section' }
    $sections.Add(@"
<section id='$itemId' class='$sectionClass'>
  <div class='section-meta'><span>$role</span><span>$routeOrFlow</span></div>
  <p class='section-number'>$($item.order.ToString('00'))</p>
  <h2>$title</h2>
  $content
  $($figures -join [Environment]::NewLine)
</section>
"@)
}

$generatedAt = [DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss ''UTC''')
$html = $template.Replace('{{STYLE}}', $css)
$html = $html.Replace('{{GENERATED_AT}}', (ConvertTo-HtmlText $generatedAt))
$html = $html.Replace('{{INDEX}}', ($indexEntries -join [Environment]::NewLine))
$html = $html.Replace('{{BODY}}', ($sections -join [Environment]::NewLine))

$htmlPath = Join-Path $OutputDirectory 'manual.html'
$pdfPath = Join-Path $OutputDirectory 'Manual_Gestudio_Usuarios_Nuevos.pdf'
$metadataPath = Join-Path $OutputDirectory 'metadata.json'

[IO.File]::WriteAllText($htmlPath, $html, (New-Object Text.UTF8Encoding($false)))

$previousEnvironment = @{
    MANUAL_HTML_PATH = [Environment]::GetEnvironmentVariable('MANUAL_HTML_PATH', 'Process')
    MANUAL_PDF_PATH = [Environment]::GetEnvironmentVariable('MANUAL_PDF_PATH', 'Process')
}

try {
    [Environment]::SetEnvironmentVariable('MANUAL_HTML_PATH', $htmlPath, 'Process')
    [Environment]::SetEnvironmentVariable('MANUAL_PDF_PATH', $pdfPath, 'Process')

    Invoke-ManualNativeCommand `
        -FilePath 'npx' `
        -Arguments @('--yes', '-p', 'playwright@1.54.1', 'node', $flowPath) | Out-Null
}
finally {
    foreach ($entry in $previousEnvironment.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process')
    }
}

if (-not (Test-Path -LiteralPath $pdfPath -PathType Leaf)) {
    throw 'Playwright no produjo el PDF esperado.'
}

$pdfBytes = [IO.File]::ReadAllBytes($pdfPath)
$pdfText = [Text.Encoding]::ASCII.GetString($pdfBytes)
$pageCount = [regex]::Matches($pdfText, '/Type\s*/Page(?!s)\b').Count

if ($pageCount -lt 1) {
    throw 'No se pudo determinar una cantidad de páginas válida en el PDF.'
}

$sourceCommit = (Invoke-ManualNativeCommand `
    -FilePath 'git' `
    -Arguments @('-C', $repoRoot, 'rev-parse', 'HEAD') `
    -CaptureOutput).Output

$sourceBranch = (Invoke-ManualNativeCommand `
    -FilePath 'git' `
    -Arguments @('-C', $repoRoot, 'branch', '--show-current') `
    -CaptureOutput).Output

$nodeVersion = (Invoke-ManualNativeCommand -FilePath 'node' -Arguments @('--version') -CaptureOutput).Output
$npmVersion = (Invoke-ManualNativeCommand -FilePath 'npm' -Arguments @('--version') -CaptureOutput).Output
$playwrightVersion = (Invoke-ManualNativeCommand -FilePath 'npx' -Arguments @('--yes', 'playwright@1.54.1', '--version') -CaptureOutput).Output

$screenshotFiles = @(Get-ChildItem -LiteralPath $screenshotDirectory -Filter '*.png' -File | Sort-Object Name)
$screenshotHashes = [ordered]@{}
foreach ($file in $screenshotFiles) {
    $screenshotHashes[$file.Name] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
}

$roles = if ($manifest.PSObject.Properties.Name -contains 'roles') {
    @($manifest.roles)
}
else {
    @(
        $manifest.items.role |
            Where-Object { $_ -and $_ -ne 'ANONYMOUS' -and $_ -ne 'TODOS' } |
            Sort-Object -Unique
    )
}

$metadata = [ordered]@{
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    sourceCommit = $sourceCommit
    sourceBranch = $sourceBranch
    baseUrl = $BaseUrl
    backendUrl = $BackendUrl
    viewport = '1440x1000'
    locale = 'es-AR'
    timezone = 'America/Argentina/Buenos_Aires'
    roles = @($roles)
    screenshotCount = $screenshotFiles.Count
    screenshotSha256 = $screenshotHashes
    pageCount = $pageCount
    powershellVersion = $PSVersionTable.PSVersion.ToString()
    nodeVersion = $nodeVersion
    npmVersion = $npmVersion
    playwrightVersion = $playwrightVersion
    applicationStartedByGenerator = [bool]$ApplicationStartedByGenerator
    pdfFileName = 'Manual_Gestudio_Usuarios_Nuevos.pdf'
}

[IO.File]::WriteAllText(
    $metadataPath,
    ($metadata | ConvertTo-Json -Depth 8),
    (New-Object Text.UTF8Encoding($false))
)

Write-Host "HTML generado: $htmlPath"
Write-Host "PDF generado: $pdfPath"
Write-Host "Páginas detectadas estructuralmente: $pageCount"
