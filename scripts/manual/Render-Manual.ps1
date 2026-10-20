[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://localhost:18081',
    [string]$BackendUrl = 'http://localhost:18080',
    [Parameter(Mandatory)]
    [string]$OutputDirectory,
    [switch]$ApplicationStartedByGenerator,
    [ValidateSet('PublicDemo', 'LocalMultitenant')]
    [string]$CaptureSource = 'PublicDemo',
    [ValidateSet('DEMO_COMERCIAL', 'SECRETARIA')]
    [string]$GeneralCaptureProfile = 'DEMO_COMERCIAL',
    [ValidateRange(8, 9)]
    [int]$CapturedAccountCount = 9
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Manual.Common.ps1')

$repoRoot = Get-ManualRepositoryRoot
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)

$manualRoot = Join-Path $repoRoot 'docs\manual-usuarios'
$manifestPath = Join-Path $manualRoot 'manifest.json'
$accountsPath = Join-Path $manualRoot 'data\demo-accounts.json'
$templatePath = Join-Path $manualRoot 'templates\manual.html'
$cssPath = Join-Path $manualRoot 'templates\manual.css'
$flowPath = Join-Path $PSScriptRoot 'flows\render-manual.cjs'
$screenshotDirectory = Join-Path $OutputDirectory 'screenshots'

foreach ($path in @($manifestPath, $accountsPath, $templatePath, $cssPath, $flowPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "No existe el archivo requerido: $path"
    }
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$demoData = Get-Content -LiteralPath $accountsPath -Raw | ConvertFrom-Json
$template = Get-Content -LiteralPath $templatePath -Raw
$css = Get-Content -LiteralPath $cssPath -Raw

if (@($demoData.accounts).Count -ne 9) {
    throw 'demo-accounts.json debe contener exactamente las nueve cuentas autorizadas.'
}

function ConvertTo-HtmlText {
    param([AllowNull()][object]$Value)

    return [Net.WebUtility]::HtmlEncode([string]$Value)
}

function ConvertTo-HtmlList {
    param(
        [AllowNull()][object[]]$Values,
        [ValidateSet('ul', 'ol')]
        [string]$Tag = 'ul',
        [string]$ClassName = ''
    )

    $items = @($Values | ForEach-Object {
        "<li>$(ConvertTo-HtmlText $_)</li>"
    }) -join [Environment]::NewLine
    $classAttribute = if ([string]::IsNullOrWhiteSpace($ClassName)) { '' } else {
        " class='$(ConvertTo-HtmlText $ClassName)'"
    }

    return "<$Tag$classAttribute>$items</$Tag>"
}

function Get-DemoAccountUrl {
    param([Parameter(Mandatory)][object]$Account)

    if ([string]$Account.category -eq 'PLATFORM') {
        return [string]$demoData.platformUrl
    }

    return [string]$demoData.publicUrl
}

function New-CredentialDetailsHtml {
    param([Parameter(Mandatory)][object]$Account)

    $rows = [Collections.Generic.List[string]]::new()
    $url = Get-DemoAccountUrl -Account $Account
    $rows.Add("<div class='credential-row'><span class='credential-label'>Organización</span><span>$(ConvertTo-HtmlText $Account.organization)</span></div>")
    $rows.Add("<div class='credential-row'><span class='credential-label'>Perfil</span><span>$(ConvertTo-HtmlText $Account.profile)</span></div>")
    $rows.Add("<div class='credential-row'><span class='credential-label'>Dirección</span><a href='$(ConvertTo-HtmlText $url)'>$(ConvertTo-HtmlText $url)</a></div>")
    $rows.Add("<div class='credential-row'><span class='credential-label'>Usuario</span><code class='credential-value'>$(ConvertTo-HtmlText $Account.username)</code></div>")
    $rows.Add("<div class='credential-row'><span class='credential-label'>Contraseña</span><code class='credential-value'>$(ConvertTo-HtmlText $Account.password)</code></div>")

    if ($Account.PSObject.Properties.Name -contains 'totpSecret' -and
        -not [string]::IsNullOrWhiteSpace([string]$Account.totpSecret)) {
        $rows.Add("<div class='credential-row'><span class='credential-label'>Clave TOTP demo</span><code class='credential-value'>$(ConvertTo-HtmlText $Account.totpSecret)</code></div>")
    }

    return "<div class='credential-list'>$($rows -join [Environment]::NewLine)</div>"
}

function New-DemoCredentialsHtml {
    $cards = [Collections.Generic.List[string]]::new()

    foreach ($account in @($demoData.accounts)) {
        $classes = [Collections.Generic.List[string]]::new()
        $classes.Add('credential-card')
        if ([bool]$account.recommended) {
            $classes.Add('recommended')
        }
        if ([string]$account.category -eq 'PLATFORM') {
            $classes.Add('platform-account')
        }

        $badge = if ([bool]$account.recommended) { 'RECOMENDADA PARA EMPEZAR' } elseif ([string]$account.category -eq 'PLATFORM') {
            'INGRESO SEPARADO'
        } else {
            'CUENTA DEMO'
        }

        $cards.Add(@"
<article class='$($classes -join ' ')'>
  <p class='card-kicker'>$(ConvertTo-HtmlText $badge)</p>
  <h3>$(ConvertTo-HtmlText $account.profileLabel)</h3>
  <p>$(ConvertTo-HtmlText $account.purpose)</p>
  $(New-CredentialDetailsHtml -Account $account)
</article>
"@)
    }

    $publicUrl = ConvertTo-HtmlText $demoData.publicUrl
    $platformUrl = ConvertTo-HtmlText $demoData.platformUrl

    return @"
<div id='demo-credentials'>
  <div class='notice success'>
    <strong>Estas cuentas pertenecen únicamente a la demo.</strong>
    Podés abrir <a href='$publicUrl'>la demo de academias</a>. La cuenta de plataforma utiliza <a href='$platformUrl'>un ingreso separado</a>.
  </div>
  <div class='credentials-grid'>
    $($cards -join [Environment]::NewLine)
  </div>
</div>
"@
}

function New-DemoProfileCardsHtml {
    $cards = [Collections.Generic.List[string]]::new()

    foreach ($account in @($demoData.accounts)) {
        $classes = if ([string]$account.category -eq 'PLATFORM') { 'profile-card platform-account' } else { 'profile-card' }
        $recommended = if ([bool]$account.recommended) {
            "<p class='card-kicker'>RECOMENDADA PARA EMPEZAR</p>"
        } else {
            "<p class='card-kicker'>$(ConvertTo-HtmlText $account.profile)</p>"
        }

        $cards.Add(@"
<article class='$classes' id='perfil-$(ConvertTo-HtmlText $account.id)'>
  $recommended
  <h3>$(ConvertTo-HtmlText $account.profileLabel)</h3>
  <p class='profile-purpose'><strong>Para qué sirve:</strong> $(ConvertTo-HtmlText $account.purpose)</p>
  $(New-CredentialDetailsHtml -Account $account)
  <h4>Qué puede ver y hacer</h4>
  $(ConvertTo-HtmlList -Values @($account.can) -Tag ul)
  <h4>Qué conviene probar</h4>
  $(ConvertTo-HtmlList -Values @($account.try) -Tag ol -ClassName 'steps')
  <h4>Qué no debería poder hacer</h4>
  $(ConvertTo-HtmlList -Values @($account.cannot) -Tag ul -ClassName 'cannot-list')
</article>
"@)
    }

    return "<div id='demo-profile-cards' class='profile-card-grid'>$($cards -join [Environment]::NewLine)</div>"
}

function Get-MatrixStateHtml {
    param([AllowNull()][object]$Value)

    switch ([string]$Value) {
        'manage' { return "<span class='matrix-state manage' title='Puede gestionar'>✓ Gestiona</span>" }
        'read' { return "<span class='matrix-state read' title='Puede consultar'>✓ Consulta</span>" }
        'locked' { return "<span class='matrix-state locked' title='Requiere otro perfil'>🔒 Otro perfil</span>" }
        'na' { return "<span class='matrix-state na' title='No corresponde'>—</span>" }
        default { throw "Estado desconocido en la matriz demo: '$Value'." }
    }
}

function New-DemoRoleMatrixHtml {
    $columns = @($demoData.roleMatrix.columns)
    $rows = @($demoData.roleMatrix.rows)

    $headCells = @($columns | ForEach-Object {
        "<th scope='col'>$(ConvertTo-HtmlText $_.label)</th>"
    }) -join [Environment]::NewLine

    $bodyRows = [Collections.Generic.List[string]]::new()
    foreach ($row in $rows) {
        $cells = [Collections.Generic.List[string]]::new()
        foreach ($column in $columns) {
            $property = @($row.values.PSObject.Properties | Where-Object { $_.Name -eq [string]$column.code }) | Select-Object -First 1
            if ($null -eq $property) {
                throw "La fila '$($row.label)' no define el perfil '$($column.code)'."
            }
            $cells.Add("<td>$(Get-MatrixStateHtml -Value $property.Value)</td>")
        }

        $bodyRows.Add("<tr><th scope='row'>$(ConvertTo-HtmlText $row.label)</th>$($cells -join [Environment]::NewLine)</tr>")
    }

    return @"
<div id='demo-role-matrix'>
  <div class='notice info'>
    <strong>Cómo leer la tabla.</strong>
    “Gestiona” incluye las acciones habilitadas para ese perfil; “Consulta” es acceso de lectura; el candado indica que hace falta otro perfil y el guion indica que esa tarea no corresponde.
  </div>
  <div class='table-scroll' tabindex='0' aria-label='Matriz de perfiles demo'>
    <table class='role-matrix'>
      <thead><tr><th scope='col'>Función</th>$headCells</tr></thead>
      <tbody>$($bodyRows -join [Environment]::NewLine)</tbody>
    </table>
  </div>
</div>
"@
}

function Get-ManifestScreenshots {
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

$script:ScreenshotCaptions = [ordered]@{
    '01-login-academia.png' = 'Pantalla de ingreso a una academia.'
    '02-panel-presentacion.png' = 'Panel de la cuenta recomendada para la primera visita.'
    '03-alumnos-alpha.png' = 'Listado de alumnos ficticios de Escuela Danza Marcos Paz.'
    '04-profesores-alpha.png' = 'Listado de profesores de la academia demo.'
    '05-salones-alpha.png' = 'Salones disponibles para organizar las clases.'
    '06-disciplinas-alpha.png' = 'Disciplinas configuradas en Escuela Danza Marcos Paz.'
    '07-horarios-disciplina.png' = 'Días y horarios asociados a una disciplina.'
    '08-inscripciones-alpha.png' = 'Consulta de inscripciones de alumnos.'
    '09-tarifas-alpha.png' = 'Historial de tarifas de una disciplina.'
    '10-condiciones-economicas-alpha.png' = 'Condiciones económicas asociadas a una inscripción.'
    '11-cargos-cobranza.png' = 'Selección de cargos pendientes durante una cobranza.'
    '12-pagos-alpha.png' = 'Historial de pagos y acceso a recibos.'
    '13-caja-alpha.png' = 'Resumen y movimientos de Caja.'
    '14-egresos-alpha.png' = 'Listado de egresos de la academia.'
    '15-bonificaciones-alpha.png' = 'Catálogo de bonificaciones.'
    '16-recargos-alpha.png' = 'Catálogo de recargos.'
    '17-metodos-pago-alpha.png' = 'Métodos de pago aceptados por la academia.'
    '18-conceptos-alpha.png' = 'Conceptos usados para ordenar cargos y productos.'
    '19-stock-alpha.png' = 'Productos y existencias de stock.'
    '20-asistencias-alpha.png' = 'Registro diario de asistencias.'
    '21-reporte-disciplina-alpha.png' = 'Reporte de alumnos por disciplina.'
    '22-reporte-mensualidades-alpha.png' = 'Reporte de mensualidades y estado de cobro.'
    '23-usuarios-alpha.png' = 'Usuarios de Escuela Danza Marcos Paz.'
    '24-roles-alpha.png' = 'Roles y permisos de la academia.'
    '25-panel-secretaria.png' = 'Panel visible para Secretaría.'
    '26-panel-caja.png' = 'Panel visible para Caja.'
    '27-panel-administracion.png' = 'Panel visible para Administración.'
    '28-panel-direccion.png' = 'Panel visible para Dirección.'
    '29-panel-superadmin.png' = 'Panel visible para Superadmin de la academia.'
    '30-alumnos-beta.png' = 'Alumnos ficticios visibles únicamente en Escuela Beta Demo.'
    '31-acceso-no-autorizado.png' = 'Mensaje mostrado cuando el perfil no tiene permiso.'
    '32-login-plataforma.png' = 'Ingreso separado para administración de plataforma.'
    '33-organizaciones-plataforma.png' = 'Listado de organizaciones administradas por la plataforma.'
    '34-detalle-alpha-plataforma.png' = 'Detalle de Escuela Danza Marcos Paz desde la plataforma.'
    '35-administradores-plataforma.png' = 'Administradores habilitados en la plataforma.'
    '36-auditoria-plataforma.png' = 'Historial de acciones sensibles de la plataforma.'
}

if ($CaptureSource -eq 'LocalMultitenant' -and $GeneralCaptureProfile -eq 'SECRETARIA') {
    $script:ScreenshotCaptions['02-panel-presentacion.png'] = 'Panel de Secretaría en el fixture local de demostración.'
}

function Get-ScreenshotCaption {
    param([Parameter(Mandatory)][string]$ScreenshotName)

    if ($script:ScreenshotCaptions.Contains($ScreenshotName)) {
        return [string]$script:ScreenshotCaptions[$ScreenshotName]
    }

    $fallback = [IO.Path]::GetFileNameWithoutExtension($ScreenshotName) -replace '^[0-9]{2}-', '' -replace '-', ' '
    return "Pantalla de Gestudio: $fallback."
}

$audienceLabels = @{
    'TODOS' = 'Todas las personas'
    'DEMO_COMERCIAL' = 'Demo comercial'
    'SECRETARIA' = 'Secretaría'
    'CAJA' = 'Caja'
    'ADMINISTRADOR' = 'Administración'
    'DIRECCION' = 'Dirección'
    'SUPERADMIN' = 'Superadmin de academia'
    'PLATFORM_SUPERADMIN' = 'Administrador de plataforma'
    'DEMOSTRACION_AVANZADA' = 'Demostración avanzada'
}

function Get-AudienceText {
    param([Parameter(Mandatory)][object]$Item)

    $values = if ($Item.PSObject.Properties.Name -contains 'audience') { @($Item.audience) } else { @('TODOS') }
    $labels = @($values | ForEach-Object {
        $value = [string]$_
        if ($audienceLabels.ContainsKey($value)) { $audienceLabels[$value] } else { $value }
    })

    return $labels -join ' · '
}

$demoCredentialsHtml = New-DemoCredentialsHtml
$demoProfileCardsHtml = New-DemoProfileCardsHtml
$demoRoleMatrixHtml = New-DemoRoleMatrixHtml

$orderedItems = @($manifest.items | Sort-Object order)
$indexEntries = [Collections.Generic.List[string]]::new()
$sections = [Collections.Generic.List[string]]::new()

foreach ($item in $orderedItems) {
    $contentPath = Join-Path $manualRoot ([string]$item.content)

    if (-not (Test-Path -LiteralPath $contentPath -PathType Leaf)) {
        throw "No existe el contenido declarado para '$($item.id)': $contentPath"
    }

    $content = Get-Content -LiteralPath $contentPath -Raw
    $content = $content.Replace('{{DEMO_CREDENTIALS}}', $demoCredentialsHtml)
    $content = $content.Replace('{{DEMO_PROFILE_CARDS}}', $demoProfileCardsHtml)
    $content = $content.Replace('{{DEMO_ROLE_MATRIX}}', $demoRoleMatrixHtml)

    $itemId = ConvertTo-HtmlText $item.id
    $headingId = "titulo-$itemId"
    $title = ConvertTo-HtmlText $item.title
    $audience = ConvertTo-HtmlText (Get-AudienceText -Item $item)

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
        $caption = ConvertTo-HtmlText (Get-ScreenshotCaption -ScreenshotName $screenshotName)
        $alt = ConvertTo-HtmlText "Pantalla de Gestudio. $caption"
        $figures.Add("<figure class='screen-figure'><img class='screen' src='data:image/png;base64,$base64' alt='$alt'><figcaption>$caption</figcaption></figure>")
    }

    $sections.Add(@"
<section id='$itemId' class='manual-section' aria-labelledby='$headingId'>
  <header class='section-heading'>
    <div class='section-meta'><span class='section-meta-label'>Quién suele usarlo</span><span>$audience</span></div>
    <p class='section-number'>Capítulo $($item.order.ToString('00'))</p>
    <h2 id='$headingId'>$title</h2>
  </header>
  $content
  $($figures -join [Environment]::NewLine)
  <a class='back-to-index' href='#indice'>Volver al índice</a>
</section>
"@)
}

$generatedAtDisplay = (Get-Date).ToString('dd/MM/yyyy')
$html = $template.Replace('{{STYLE}}', $css)
$html = $html.Replace('{{GENERATED_AT}}', (ConvertTo-HtmlText $generatedAtDisplay))
$html = $html.Replace('{{PUBLIC_DEMO_URL}}', (ConvertTo-HtmlText $demoData.publicUrl))
$captureNote = if ($CaptureSource -eq 'LocalMultitenant') {
    $profileLabel = if ($GeneralCaptureProfile -eq 'SECRETARIA') { 'Secretaría' } else { 'Demo comercial' }
    "<aside class='notice info'><strong>Origen de las capturas</strong>Las pantallas de este ejemplar se capturaron en una demo local con datos ficticios. El recorrido general usa el perfil $(ConvertTo-HtmlText $profileLabel). Las credenciales publicadas corresponden exclusivamente a la demo pública; las credenciales locales permanecen privadas.</aside>"
} else { '' }
$html = $html.Replace('{{CAPTURE_NOTE}}', $captureNote)
$html = $html.Replace('{{INDEX}}', ($indexEntries -join [Environment]::NewLine))
$html = $html.Replace('{{BODY}}', ($sections -join [Environment]::NewLine))

$htmlPath = Join-Path $OutputDirectory 'manual.html'
$pdfPath = Join-Path $OutputDirectory 'Manual_Gestudio_Usuarios_Nuevos.pdf'
$metadataPath = Join-Path $OutputDirectory 'metadata.json'

[IO.File]::WriteAllText($htmlPath, $html, (New-Object Text.UTF8Encoding($false)))

$previousEnvironment = @{
    MANUAL_HTML_PATH = [Environment]::GetEnvironmentVariable('MANUAL_HTML_PATH', 'Process')
    MANUAL_PDF_PATH = [Environment]::GetEnvironmentVariable('MANUAL_PDF_PATH', 'Process')
    NODE_PATH = [Environment]::GetEnvironmentVariable('NODE_PATH', 'Process')
}

try {
    [Environment]::SetEnvironmentVariable('MANUAL_HTML_PATH', $htmlPath, 'Process')
    [Environment]::SetEnvironmentVariable('MANUAL_PDF_PATH', $pdfPath, 'Process')
    $playwrightRuntime = Resolve-ManualPlaywrightRuntime
    Set-ManualNodePathForRuntime `
        -NodeModules $playwrightRuntime.NodeModules `
        -PreviousNodePath $previousEnvironment.NODE_PATH

    Invoke-ManualNativeCommand `
        -FilePath 'node' `
        -Arguments @($flowPath) | Out-Null
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
$playwrightVersion = "Version $($playwrightRuntime.Version)"

$screenshotFiles = @(Get-ChildItem -LiteralPath $screenshotDirectory -Filter '*.png' -File | Sort-Object Name)
$screenshotHashes = [ordered]@{}
foreach ($file in $screenshotFiles) {
    $screenshotHashes[$file.Name] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
}

$metadata = [ordered]@{
    generatedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
    sourceCommit = $sourceCommit
    sourceBranch = $sourceBranch
    applicationUrl = [string]$demoData.publicUrl
    viewport = '1440x1000'
    locale = 'es-AR'
    timezone = 'America/Argentina/Buenos_Aires'
    roles = @($manifest.roles)
    demoAccountCount = @($demoData.accounts).Count
    captureSource = $CaptureSource
    generalCaptureProfile = $GeneralCaptureProfile
    capturedAccountCount = $CapturedAccountCount
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
