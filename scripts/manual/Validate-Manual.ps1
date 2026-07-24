[CmdletBinding()]
param(
    [string]$OutputDirectory,
    [string]$PdfPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Manual.Common.ps1')

$repoRoot = Get-ManualRepositoryRoot

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    if (-not [string]::IsNullOrWhiteSpace($PdfPath)) {
        $OutputDirectory = Split-Path -Parent ([IO.Path]::GetFullPath($PdfPath))
    }
    else {
        $OutputDirectory = Join-Path $repoRoot 'artifacts\manual'
    }
}
else {
    $OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
}

if ([string]::IsNullOrWhiteSpace($PdfPath)) {
    $PdfPath = Join-Path $OutputDirectory 'Manual_Gestudio_Usuarios_Nuevos.pdf'
}
else {
    $PdfPath = [IO.Path]::GetFullPath($PdfPath)
}

$htmlPath = Join-Path $OutputDirectory 'manual.html'
$metadataPath = Join-Path $OutputDirectory 'metadata.json'
$screenshotDirectory = Join-Path $OutputDirectory 'screenshots'
$manifestPath = Join-Path $repoRoot 'docs\manual-usuarios\manifest.json'

foreach ($requiredPath in @($PdfPath, $htmlPath, $metadataPath, $manifestPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "No existe el archivo requerido: $requiredPath"
    }
}

if (-not (Test-Path -LiteralPath $screenshotDirectory -PathType Container)) {
    throw "No existe el directorio de capturas: $screenshotDirectory"
}

$pdfBytes = [IO.File]::ReadAllBytes($PdfPath)
if ($pdfBytes.Length -lt 50000) {
    throw "El PDF es demasiado pequeño: $($pdfBytes.Length) bytes."
}

if ([Text.Encoding]::ASCII.GetString($pdfBytes, 0, 4) -ne '%PDF') {
    throw 'La firma del archivo no corresponde a PDF.'
}

$htmlInfo = Get-Item -LiteralPath $htmlPath
if ($htmlInfo.Length -lt 20000) {
    throw "El HTML es demasiado pequeño: $($htmlInfo.Length) bytes."
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json

if ($null -eq $manifest.items -or @($manifest.items).Count -lt 20) {
    throw 'El manifest debe contener al menos 20 secciones.'
}

$items = @($manifest.items)
$ids = @($items | ForEach-Object { [string]$_.id })
$orders = @($items | ForEach-Object { [int]$_.order })

if (@($ids | Sort-Object -Unique).Count -ne $ids.Count) {
    throw 'El manifest contiene IDs duplicados.'
}

if (@($orders | Sort-Object -Unique).Count -ne $orders.Count) {
    throw 'El manifest contiene órdenes duplicados.'
}

if (($orders | Measure-Object -Minimum).Minimum -ne 1) {
    throw 'El orden del manifest debe comenzar en 1.'
}

$expectedOrders = 1..$items.Count
if (@(Compare-Object $expectedOrders ($orders | Sort-Object)).Count -ne 0) {
    throw 'El orden del manifest debe ser contiguo.'
}

function Get-ItemScreenshots {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Item
    )

    $names = [Collections.Generic.List[string]]::new()

    if ($Item.PSObject.Properties.Name -contains 'screenshot') {
        $singleName = [string]$Item.screenshot
        if (-not [string]::IsNullOrWhiteSpace($singleName)) {
            $names.Add($singleName)
        }
    }

    if ($Item.PSObject.Properties.Name -contains 'screenshots' -and $null -ne $Item.screenshots) {
        foreach ($name in @($Item.screenshots)) {
            $text = [string]$name
            if (-not [string]::IsNullOrWhiteSpace($text) -and -not $names.Contains($text)) {
                $names.Add($text)
            }
        }
    }

    return @($names)
}

function Get-PngDimensions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $bytes = [IO.File]::ReadAllBytes($Path)
    $signature = @(137, 80, 78, 71, 13, 10, 26, 10)

    if ($bytes.Length -lt 24) {
        throw "PNG vacío o incompleto: $Path"
    }

    for ($index = 0; $index -lt $signature.Count; $index++) {
        if ($bytes[$index] -ne $signature[$index]) {
            throw "Firma PNG inválida: $Path"
        }
    }

    $width = ([uint32]$bytes[16] -shl 24) -bor ([uint32]$bytes[17] -shl 16) -bor ([uint32]$bytes[18] -shl 8) -bor [uint32]$bytes[19]
    $height = ([uint32]$bytes[20] -shl 24) -bor ([uint32]$bytes[21] -shl 16) -bor ([uint32]$bytes[22] -shl 8) -bor [uint32]$bytes[23]

    return [pscustomobject]@{
        Width = [uint32]$width
        Height = [uint32]$height
    }
}

$manifestScreenshotNames = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase
)
$manualSourceRoot = Join-Path $repoRoot 'docs\manual-usuarios'

foreach ($item in $items) {
    foreach ($property in @('id', 'order', 'title', 'role', 'content', 'required')) {
        if (-not ($item.PSObject.Properties.Name -contains $property)) {
            throw "La sección de orden $($item.order) no define '$property'."
        }
    }

    foreach ($property in @('id', 'title', 'role', 'content')) {
        if ([string]::IsNullOrWhiteSpace([string]$item.$property)) {
            throw "La sección de orden $($item.order) tiene '$property' vacío."
        }
    }

    if ([string]$item.id -notmatch '^[a-z0-9-]+$') {
        throw "ID inválido en manifest: $($item.id)"
    }

    $route = if ($item.PSObject.Properties.Name -contains 'route') { [string]$item.route } else { '' }
    $flow = if ($item.PSObject.Properties.Name -contains 'flow') { [string]$item.flow } else { '' }
    if ([string]::IsNullOrWhiteSpace($route) -and [string]::IsNullOrWhiteSpace($flow)) {
        throw "La sección '$($item.id)' debe declarar route o flow."
    }

    $contentPath = [IO.Path]::GetFullPath((Join-Path $manualSourceRoot ([string]$item.content)))
    if (-not (Test-ManualPathInside -Parent $manualSourceRoot -Candidate $contentPath)) {
        throw "Ruta de contenido fuera de docs/manual-usuarios: $($item.content)"
    }

    if (-not (Test-Path -LiteralPath $contentPath -PathType Leaf)) {
        throw "No existe el contenido: $($item.content)"
    }

    $itemScreenshots = @(Get-ItemScreenshots -Item $item)
    foreach ($screenshotName in $itemScreenshots) {
        if ([IO.Path]::GetFileName($screenshotName) -ne $screenshotName -or
            $screenshotName -notmatch '^[0-9]{2}-[a-z0-9-]+\.png$') {
            throw "Nombre de captura inválido: $screenshotName"
        }

        if (-not $manifestScreenshotNames.Add($screenshotName)) {
            throw "La captura está declarada más de una vez en el manifest: $screenshotName"
        }

        $screenshotPath = Join-Path $screenshotDirectory $screenshotName
        if (-not (Test-Path -LiteralPath $screenshotPath -PathType Leaf)) {
            if ([bool]$item.required) {
                throw "Falta la captura requerida: $screenshotName"
            }

            continue
        }

        $screenshotInfo = Get-Item -LiteralPath $screenshotPath
        if ($screenshotInfo.Length -lt 10000) {
            throw "Captura vacía o demasiado pequeña: $screenshotName"
        }

        $dimensions = Get-PngDimensions -Path $screenshotPath
        if ($dimensions.Width -ne 1440 -or $dimensions.Height -lt 900) {
            throw "Dimensiones inesperadas para ${screenshotName}: $($dimensions.Width)x$($dimensions.Height)."
        }
    }
}

$actualScreenshots = @(Get-ChildItem -LiteralPath $screenshotDirectory -Filter '*.png' -File)
$unexpectedScreenshotEntries = @(
    Get-ChildItem -LiteralPath $screenshotDirectory |
        Where-Object { $_.PSIsContainer -or $_.Extension -ne '.png' } |
        Select-Object -ExpandProperty Name
)

if ($unexpectedScreenshotEntries.Count -gt 0) {
    throw "Existen entradas inesperadas en screenshots: $($unexpectedScreenshotEntries -join ', ')."
}

if ($actualScreenshots.Count -ne $manifestScreenshotNames.Count) {
    $unreferenced = @(
        $actualScreenshots |
            Where-Object { -not $manifestScreenshotNames.Contains($_.Name) } |
            Select-Object -ExpandProperty Name
    )

    if ($unreferenced.Count -gt 0) {
        throw "Existen capturas no declaradas en manifest: $($unreferenced -join ', ')."
    }

    throw 'La cantidad de capturas no coincide con el manifest.'
}

$requiredMetadata = @(
    'generatedAtUtc'
    'sourceCommit'
    'sourceBranch'
    'baseUrl'
    'backendUrl'
    'viewport'
    'locale'
    'timezone'
    'roles'
    'screenshotCount'
    'screenshotSha256'
    'pageCount'
    'powershellVersion'
    'nodeVersion'
    'npmVersion'
    'playwrightVersion'
    'applicationStartedByGenerator'
    'pdfFileName'
)

foreach ($property in $requiredMetadata) {
    if (-not ($metadata.PSObject.Properties.Name -contains $property)) {
        throw "Falta metadata.$property."
    }
}

if ([int]$metadata.screenshotCount -ne $actualScreenshots.Count) {
    throw 'metadata.screenshotCount no coincide con las capturas.'
}

if ($null -eq $metadata.screenshotSha256) {
    throw 'metadata.screenshotSha256 no puede ser nulo.'
}

foreach ($file in $actualScreenshots) {
    $hashProperty = @(
        $metadata.screenshotSha256.PSObject.Properties |
            Where-Object { $_.Name -eq $file.Name }
    ) | Select-Object -First 1

    if ($null -eq $hashProperty) {
        throw "Falta el hash SHA-256 de $($file.Name) en metadata."
    }

    $actualHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    if ([string]$hashProperty.Value -ne $actualHash) {
        throw "El hash SHA-256 de $($file.Name) no coincide con metadata."
    }
}

$expectedRoles = @('SUPERADMIN', 'DIRECCION', 'ADMINISTRADOR', 'SECRETARIA', 'CAJA')
if (@(Compare-Object $expectedRoles @($metadata.roles)).Count -ne 0) {
    throw 'metadata.roles no contiene exactamente los cinco roles demo.'
}

if ([int]$metadata.pageCount -lt 20) {
    throw "Cantidad de páginas insuficiente: $($metadata.pageCount)."
}

if ([string]$metadata.pdfFileName -ne [IO.Path]::GetFileName($PdfPath)) {
    throw 'metadata.pdfFileName no coincide con el PDF.'
}

$allowedRootFiles = @(
    'Manual_Gestudio_Usuarios_Nuevos.pdf'
    'manual.html'
    'metadata.json'
)

$unexpectedRootFiles = @(
    Get-ChildItem -LiteralPath $OutputDirectory -File |
        Where-Object { $_.Name -notin $allowedRootFiles } |
        Select-Object -ExpandProperty Name
)

if ($unexpectedRootFiles.Count -gt 0) {
    throw "Existen archivos inesperados en artifacts/manual: $($unexpectedRootFiles -join ', ')."
}

$unexpectedDirectories = @(
    Get-ChildItem -LiteralPath $OutputDirectory -Directory |
        Where-Object { $_.Name -ne 'screenshots' } |
        Select-Object -ExpandProperty Name
)

if ($unexpectedDirectories.Count -gt 0) {
    throw "Existen directorios inesperados en artifacts/manual: $($unexpectedDirectories -join ', ')."
}

$htmlText = Get-Content -LiteralPath $htmlPath -Raw
if ($htmlText -match '(?i)(?:src|href)\s*=\s*["'']https?://') {
    throw 'El HTML contiene recursos web externos.'
}

if ($htmlText -match '(?i)<script(?:\s|>)') {
    throw 'El HTML generado no debe contener scripts.'
}

$metadataText = Get-Content -LiteralPath $metadataPath -Raw
$pdfText = [Text.Encoding]::ASCII.GetString($pdfBytes)
$scanText = $htmlText + "`n" + $metadataText + "`n" + $pdfText

foreach ($marker in @(
    'Authorization'
    'Bearer '
    'JWT_SECRET'
    'PASSWORD='
    'access_token'
    'refresh_token'
    'gestudio_demo_refresh'
)) {
    if ($scanText.IndexOf($marker, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "Se encontró un marcador sensible prohibido: $marker"
    }
}

foreach ($entry in $script:ManualDemoCredentialVariables.GetEnumerator()) {
    $secret = [Environment]::GetEnvironmentVariable($entry.Value, 'Process')
    if (-not [string]::IsNullOrEmpty($secret) -and $scanText.Contains($secret)) {
        throw "Se encontró el valor sensible de $($entry.Value) en un artefacto textual."
    }
}

$ignoredSamples = @(
    'artifacts/manual/Manual_Gestudio_Usuarios_Nuevos.pdf'
    'artifacts/manual/manual.html'
    'artifacts/manual/metadata.json'
    'artifacts/manual/screenshots/01-login.png'
    'docs/manual-usuarios/screenshots/01-login.png'
    'docs/manual-usuarios/.tmp/probe.txt'
    'playwright-report/index.html'
    'test-results/probe.txt'
)

foreach ($sample in $ignoredSamples) {
    $ignoreResult = Invoke-ManualNativeCommand `
        -FilePath 'git' `
        -Arguments @('-C', $repoRoot, 'check-ignore', '--no-index', '-q', '--', $sample) `
        -AllowFailure

    if ($ignoreResult.ExitCode -ne 0) {
        throw "La ruta generada no está ignorada por Git: $sample"
    }
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
    throw 'Hay artefactos generados versionados accidentalmente.'
}

Write-Host 'Validación estructural aprobada.'
Write-Host 'No se realizó una revisión visual humana del PDF; esa revisión sigue siendo obligatoria.'
