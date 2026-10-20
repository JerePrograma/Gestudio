[CmdletBinding()]
param(
    [string]$OutputDirectory,
    [string]$PdfPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Manual.Common.ps1')

$repoRoot = Get-ManualRepositoryRoot
$manualSourceRoot = Join-Path $repoRoot 'docs\manual-usuarios'

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
$manifestPath = Join-Path $manualSourceRoot 'manifest.json'
$accountsPath = Join-Path $manualSourceRoot 'data\demo-accounts.json'

foreach ($requiredPath in @($PdfPath, $htmlPath, $metadataPath, $manifestPath, $accountsPath)) {
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
if ($htmlInfo.Length -lt 30000) {
    throw "El HTML es demasiado pequeño: $($htmlInfo.Length) bytes."
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$demoData = Get-Content -LiteralPath $accountsPath -Raw | ConvertFrom-Json
$metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json

if ([int]$manifest.version -lt 3) {
    throw 'El manifest debe usar la versión 3 o posterior.'
}

$items = @($manifest.items)
if ($items.Count -ne 40) {
    throw "El manifest debe contener exactamente 40 capítulos y contiene $($items.Count)."
}

$ids = @($items | ForEach-Object { [string]$_.id })
$orders = @($items | ForEach-Object { [int]$_.order })

if (@($ids | Sort-Object -Unique).Count -ne $ids.Count) {
    throw 'El manifest contiene IDs duplicados.'
}

if (@($orders | Sort-Object -Unique).Count -ne $orders.Count) {
    throw 'El manifest contiene órdenes duplicados.'
}

if (@(Compare-Object (1..40) ($orders | Sort-Object)).Count -ne 0) {
    throw 'El orden del manifest debe ser contiguo de 1 a 40.'
}

$expectedRoles = @(
    'DEMO_COMERCIAL'
    'SECRETARIA'
    'CAJA'
    'ADMINISTRADOR'
    'DIRECCION'
    'SUPERADMIN'
    'PLATFORM_SUPERADMIN'
)

if (@(Compare-Object $expectedRoles @($manifest.roles)).Count -ne 0) {
    throw 'manifest.roles no contiene exactamente los siete perfiles documentados.'
}

$allowedAudiences = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($audienceCode in @($expectedRoles) + @('TODOS', 'DEMOSTRACION_AVANZADA')) {
    [void]$allowedAudiences.Add([string]$audienceCode)
}

$accounts = @($demoData.accounts)
if ($accounts.Count -ne 9) {
    throw "demo-accounts.json debe contener exactamente nueve cuentas y contiene $($accounts.Count)."
}

$accountIds = @($accounts | ForEach-Object { [string]$_.id })
$usernames = @($accounts | ForEach-Object { [string]$_.username })
$passwords = @($accounts | ForEach-Object { [string]$_.password })

foreach ($collection in @($accountIds, $usernames, $passwords)) {
    if (@($collection | Where-Object { [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) {
        throw 'Las cuentas demo contienen identificadores, usuarios o contraseñas vacíos.'
    }
    if (@($collection | Sort-Object -Unique).Count -ne $collection.Count) {
        throw 'Las cuentas demo contienen identificadores, usuarios o contraseñas duplicados.'
    }
}

foreach ($account in $accounts) {
    foreach ($property in @('id', 'category', 'organization', 'profile', 'profileLabel', 'username', 'password', 'purpose', 'can', 'try', 'cannot')) {
        if (-not ($account.PSObject.Properties.Name -contains $property)) {
            throw "La cuenta '$($account.id)' no define '$property'."
        }
    }

    foreach ($listProperty in @('can', 'try', 'cannot')) {
        if (@($account.$listProperty).Count -lt 1) {
            throw "La cuenta '$($account.id)' debe incluir al menos una entrada en '$listProperty'."
        }
    }
}

$platformAccounts = @($accounts | Where-Object { [string]$_.profile -eq 'PLATFORM_SUPERADMIN' })
if ($platformAccounts.Count -ne 1) {
    throw 'Debe existir exactamente una cuenta PLATFORM_SUPERADMIN.'
}

$totpValues = @($accounts | ForEach-Object {
    if ($_.PSObject.Properties.Name -contains 'totpSecret' -and
        -not [string]::IsNullOrWhiteSpace([string]$_.totpSecret)) {
        [string]$_.totpSecret
    }
})

if ($totpValues.Count -ne 1 -or [string]$platformAccounts[0].totpSecret -ne [string]$totpValues[0]) {
    throw 'La única clave TOTP demo debe pertenecer a PLATFORM_SUPERADMIN.'
}

$unknownAccountProfiles = @($accounts | Where-Object { [string]$_.profile -notin $expectedRoles })
if ($unknownAccountProfiles.Count -gt 0) {
    throw "demo-accounts.json contiene perfiles desconocidos: $(@($unknownAccountProfiles.profile) -join ', ')."
}

$matrixColumns = @($demoData.roleMatrix.columns)
$matrixColumnCodes = @($matrixColumns | ForEach-Object { [string]$_.code })
if (@(Compare-Object $expectedRoles $matrixColumnCodes).Count -ne 0) {
    throw 'La matriz demo no contiene exactamente los siete perfiles documentados.'
}

foreach ($column in $matrixColumns) {
    if ([string]::IsNullOrWhiteSpace([string]$column.label)) {
        throw "La columna '$($column.code)' de la matriz no tiene una etiqueta legible."
    }
}

$matrixStates = @('manage', 'read', 'locked', 'na')
$matrixRows = @($demoData.roleMatrix.rows)
if ($matrixRows.Count -lt 1) {
    throw 'La matriz demo no contiene funciones para comparar.'
}

foreach ($row in $matrixRows) {
    if ([string]::IsNullOrWhiteSpace([string]$row.label)) {
        throw 'La matriz demo contiene una fila sin etiqueta.'
    }

    $rowCodes = @($row.values.PSObject.Properties.Name)
    if (@(Compare-Object $expectedRoles $rowCodes).Count -ne 0) {
        throw "La fila '$($row.label)' no contiene exactamente los siete perfiles."
    }

    foreach ($roleCode in $expectedRoles) {
        if ([string]$row.values.$roleCode -notin $matrixStates) {
            throw "La fila '$($row.label)' contiene un estado inválido para '$roleCode'."
        }
    }
}

$allowedExternalLinks = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
[void]$allowedExternalLinks.Add([string]$demoData.publicUrl)
[void]$allowedExternalLinks.Add([string]$demoData.platformUrl)

foreach ($allowedUrl in $allowedExternalLinks) {
    $uri = $null
    if (-not [uri]::TryCreate($allowedUrl, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -ne 'https' -or
        $uri.Host -ne 'gestudio-demo-jere-287b8c90.pages.dev') {
        throw "URL demo no autorizada en demo-accounts.json: $allowedUrl"
    }
}

function Get-ItemScreenshots {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Item)

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
    param([Parameter(Mandatory)][string]$Path)

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

$manifestScreenshotNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$accountIdSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($accountId in $accountIds) {
    [void]$accountIdSet.Add($accountId)
}

foreach ($item in $items) {
    foreach ($property in @('id', 'order', 'title', 'audience', 'captureAs', 'content', 'required')) {
        if (-not ($item.PSObject.Properties.Name -contains $property)) {
            throw "El capítulo de orden $($item.order) no define '$property'."
        }
    }

    foreach ($property in @('id', 'title', 'content')) {
        if ([string]::IsNullOrWhiteSpace([string]$item.$property)) {
            throw "El capítulo de orden $($item.order) tiene '$property' vacío."
        }
    }

    if ([string]$item.id -notmatch '^[a-z0-9-]+$') {
        throw "ID inválido en manifest: $($item.id)"
    }

    $itemAudiences = @($item.audience | ForEach-Object { [string]$_ })
    if ($itemAudiences.Count -lt 1) {
        throw "El capítulo '$($item.id)' debe declarar al menos una audiencia."
    }

    foreach ($audienceCode in $itemAudiences) {
        if ([string]::IsNullOrWhiteSpace($audienceCode) -or -not $allowedAudiences.Contains($audienceCode)) {
            throw "El capítulo '$($item.id)' declara una audiencia desconocida: $audienceCode"
        }
    }

    $captureAs = [string]$item.captureAs
    if (-not [string]::IsNullOrWhiteSpace($captureAs) -and -not $accountIdSet.Contains($captureAs)) {
        throw "El capítulo '$($item.id)' declara una cuenta captureAs desconocida: $captureAs"
    }

    $route = if ($item.PSObject.Properties.Name -contains 'route') { [string]$item.route } else { '' }
    $flow = if ($item.PSObject.Properties.Name -contains 'flow') { [string]$item.flow } else { '' }
    if ([string]::IsNullOrWhiteSpace($route) -and [string]::IsNullOrWhiteSpace($flow)) {
        throw "El capítulo '$($item.id)' debe declarar route o flow."
    }

    $contentPath = [IO.Path]::GetFullPath((Join-Path $manualSourceRoot ([string]$item.content)))
    if (-not (Test-ManualPathInside -Parent $manualSourceRoot -Candidate $contentPath)) {
        throw "Ruta de contenido fuera de docs/manual-usuarios: $($item.content)"
    }

    if (-not (Test-Path -LiteralPath $contentPath -PathType Leaf)) {
        throw "No existe el contenido: $($item.content)"
    }

    foreach ($screenshotName in @(Get-ItemScreenshots -Item $item)) {
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

if ($manifestScreenshotNames.Count -ne 36) {
    throw "El manifest debe declarar exactamente 36 capturas y declara $($manifestScreenshotNames.Count)."
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
    'applicationUrl'
    'viewport'
    'locale'
    'timezone'
    'roles'
    'demoAccountCount'
    'captureSource'
    'generalCaptureProfile'
    'capturedAccountCount'
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

if ([string]$metadata.applicationUrl -ne [string]$demoData.publicUrl) {
    throw 'metadata.applicationUrl no coincide con la URL pública autorizada.'
}

if ([int]$metadata.demoAccountCount -ne 9) {
    throw 'metadata.demoAccountCount debe ser 9.'
}

if ([string]$metadata.captureSource -notin @('PublicDemo', 'LocalMultitenant') -or
    [string]$metadata.generalCaptureProfile -notin @('DEMO_COMERCIAL', 'SECRETARIA')) {
    throw 'La metadata no identifica una fuente y un perfil de captura reconocidos.'
}
$expectedCapturedAccounts = if ([string]$metadata.generalCaptureProfile -eq 'SECRETARIA') { 8 } else { 9 }
if ([int]$metadata.capturedAccountCount -ne $expectedCapturedAccounts -or
    ([string]$metadata.captureSource -eq 'PublicDemo' -and $expectedCapturedAccounts -ne 9)) {
    throw 'La cantidad de cuentas capturadas no corresponde al perfil general y la fuente declarados.'
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

if (@(Compare-Object $expectedRoles @($metadata.roles)).Count -ne 0) {
    throw 'metadata.roles no contiene exactamente los siete perfiles documentados.'
}

if ([int]$metadata.pageCount -lt 40) {
    throw "Cantidad de páginas insuficiente para 40 capítulos: $($metadata.pageCount)."
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
$metadataText = Get-Content -LiteralPath $metadataPath -Raw

if ($htmlText -notmatch '(?is)^\s*<!doctype\s+html>') {
    throw 'El HTML no comienza con un doctype válido.'
}

if ($htmlText -notmatch '(?is)<html\s+lang=["'']es-AR["'']') {
    throw 'El HTML no declara lang="es-AR".'
}

if ($htmlText -match '(?is)<script(?:\s|>)') {
    throw 'El HTML generado no debe contener scripts.'
}

if ($htmlText -match '(?is)<(?:link|iframe|object|embed)(?:\s|>)') {
    throw 'El HTML contiene un recurso o documento externo no permitido.'
}

if ($htmlText -match '(?is)@import\s+|url\s*\(\s*["'']?https?://') {
    throw 'El CSS contiene una dependencia web externa.'
}

$sourceMatches = [regex]::Matches($htmlText, '(?is)\b(?:src|srcset)\s*=\s*["''](?<value>[^"'']+)["'']')
foreach ($match in $sourceMatches) {
    $value = [Net.WebUtility]::HtmlDecode($match.Groups['value'].Value)
    if (-not $value.StartsWith('data:image/png;base64,', [StringComparison]::OrdinalIgnoreCase)) {
        throw "El HTML contiene un recurso no embebido: $value"
    }
}

$hrefMatches = [regex]::Matches($htmlText, '(?is)<a\b[^>]*\bhref\s*=\s*["''](?<href>[^"'']+)["'']')
$externalLinksFound = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$fragmentLinks = [Collections.Generic.List[string]]::new()

foreach ($match in $hrefMatches) {
    $href = [Net.WebUtility]::HtmlDecode($match.Groups['href'].Value)
    if ($href.StartsWith('#')) {
        $fragmentLinks.Add($href.Substring(1))
        continue
    }

    if ($href -match '^https://') {
        if (-not $allowedExternalLinks.Contains($href)) {
            throw "Enlace web no autorizado en el manual: $href"
        }
        [void]$externalLinksFound.Add($href)
        continue
    }

    throw "Enlace no permitido en el manual offline: $href"
}

foreach ($allowedUrl in $allowedExternalLinks) {
    if (-not $externalLinksFound.Contains($allowedUrl)) {
        throw "Falta el enlace autorizado en el manual: $allowedUrl"
    }
}

$idMatches = [regex]::Matches($htmlText, '(?is)\bid\s*=\s*["''](?<id>[a-zA-Z0-9_-]+)["'']')
$htmlIds = @($idMatches | ForEach-Object { $_.Groups['id'].Value })
if (@($htmlIds | Sort-Object -Unique).Count -ne $htmlIds.Count) {
    $duplicates = @($htmlIds | Group-Object | Where-Object Count -gt 1 | Select-Object -ExpandProperty Name)
    throw "El HTML contiene IDs duplicados: $($duplicates -join ', ')."
}

$htmlIdSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($htmlId in $htmlIds) {
    [void]$htmlIdSet.Add($htmlId)
}

foreach ($fragment in $fragmentLinks) {
    if ([string]::IsNullOrWhiteSpace($fragment) -or -not $htmlIdSet.Contains($fragment)) {
        throw "Enlace interno roto: #$fragment"
    }
}

foreach ($expectedId in @('contenido', 'indice') + $ids) {
    if (-not $htmlIdSet.Contains([string]$expectedId)) {
        throw "Falta el destino interno esperado: #$expectedId"
    }
}

$sectionMatches = [regex]::Matches($htmlText, '(?is)<section\s+id=["''](?<id>[a-z0-9-]+)["'']\s+class=["'']manual-section["'']')
if ($sectionMatches.Count -ne 40) {
    throw "El HTML debe contener exactamente 40 capítulos y contiene $($sectionMatches.Count)."
}

if ($htmlText -match '\{\{[A-Z0-9_]+\}\}') {
    throw 'El HTML contiene placeholders sin resolver.'
}

foreach ($requiredGeneratedId in @('demo-credentials', 'demo-profile-cards', 'demo-role-matrix')) {
    if (-not $htmlIdSet.Contains($requiredGeneratedId)) {
        throw "Falta el bloque generado #$requiredGeneratedId."
    }
}

if ($htmlText -match '(?i)>\s*Ruta\s*:') {
    throw 'El manual muestra una ruta técnica interna.'
}

$sanitizedHtml = [regex]::Replace(
    $htmlText,
    'data:image/png;base64,[A-Za-z0-9+/=]+',
    '[IMAGEN]',
    [Text.RegularExpressions.RegexOptions]::IgnoreCase
)
$scanText = $sanitizedHtml + [Environment]::NewLine + $metadataText

$forbiddenPatterns = [ordered]@{
    'proxy token' = '(?i)proxy\s*token|publicDemo\.proxyToken'
    'JWT' = '(?i)\bJWT\b|JWT_SECRET'
    'códigos de recuperación' = '(?i)recovery[\s_-]*codes?|c[oó]digos?\s+de\s+recuperaci[oó]n'
    'credenciales de base de datos' = '(?i)jdbc:postgresql|postgres(?:ql)?://|POSTGRES_PASSWORD|DB_PASSWORD|PGPASSWORD|DATABASE_URL|connection\s+string|cadena\s+de\s+conexi[oó]n'
    'UUID interno' = '(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b'
    'localhost' = '(?i)\blocalhost\b|127\.0\.0\.1|\[?::1\]?'
    'AppData' = '(?i)\bAppData\b'
    'ruta local de Windows' = '(?i)\b[A-Z]:[\\/]'
    'archivo local' = '(?i)\bfile://'
    'cabecera de autorización' = '(?i)\bAuthorization\b|\bBearer\s+'
    'token de sesión' = '(?i)\baccess_token\b|\brefresh_token\b|\btoken(?:s)?\b'
    'cookie' = '(?i)\bcookies?\b|gestudio_demo_refresh'
    'ruta de servicio' = '(?i)/api/|\bendpoint\b|\bbackend\b'
}

foreach ($entry in $forbiddenPatterns.GetEnumerator()) {
    if ([regex]::IsMatch($scanText, [string]$entry.Value)) {
        throw "Se encontró contenido prohibido: $($entry.Key)."
    }
}

$authorizedPasswordSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
for ($accountIndex = 0; $accountIndex -lt $accounts.Count; $accountIndex++) {
    $password = [string]$passwords[$accountIndex]
    [void]$authorizedPasswordSet.Add($password)
    if ($sanitizedHtml.IndexOf($password, [StringComparison]::Ordinal) -lt 0) {
        throw "Falta en el manual la contraseña autorizada de una cuenta demo: $($accounts[$accountIndex].username)"
    }
}

$passwordMatches = [regex]::Matches($sanitizedHtml, 'Aa9![A-Za-z0-9]{20,}')
$visiblePasswordSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($match in $passwordMatches) {
    [void]$visiblePasswordSet.Add($match.Value)
}

if ($visiblePasswordSet.Count -ne $authorizedPasswordSet.Count) {
    throw 'La cantidad de contraseñas demo visibles no coincide con la fuente autorizada.'
}

foreach ($visiblePassword in $visiblePasswordSet) {
    if (-not $authorizedPasswordSet.Contains($visiblePassword)) {
        throw 'El manual contiene una contraseña que no está autorizada por demo-accounts.json.'
    }
}

$authorizedTotp = [string]$totpValues[0]
if ($sanitizedHtml.IndexOf($authorizedTotp, [StringComparison]::Ordinal) -lt 0) {
    throw 'Falta la clave TOTP demo autorizada en el manual.'
}

$totpCandidateMatches = [regex]::Matches($sanitizedHtml, '(?<![A-Z2-7])[A-Z2-7]{32,}(?![A-Z2-7])')
$visibleTotpSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($match in $totpCandidateMatches) {
    [void]$visibleTotpSet.Add($match.Value)
}

if ($visibleTotpSet.Count -ne 1 -or -not $visibleTotpSet.Contains($authorizedTotp)) {
    throw 'El manual contiene una clave TOTP no autorizada o no contiene exactamente la clave demo prevista.'
}

if ($metadataText.IndexOf($authorizedTotp, [StringComparison]::Ordinal) -ge 0 -or
    @($passwords | Where-Object { $metadataText.Contains($_) }).Count -gt 0) {
    throw 'La metadata no debe incluir contraseñas ni la clave TOTP demo.'
}

$ignoredSamples = @(
    'artifacts/manual/Manual_Gestudio_Usuarios_Nuevos.pdf'
    'artifacts/manual/manual.html'
    'artifacts/manual/metadata.json'
    'artifacts/manual/screenshots/01-login-academia.png'
    'docs/manual-usuarios/screenshots/01-login-academia.png'
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

Write-Host 'Validación estructural aprobada para 40 capítulos y 36 capturas.'
Write-Host 'Los enlaces, recursos offline y secretos autorizados coinciden con el contrato del manual.'
Write-Host 'La revisión visual humana del HTML y del PDF sigue siendo obligatoria.'
