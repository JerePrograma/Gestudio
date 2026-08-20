[CmdletBinding()]
param(
    [string] $Repository = 'C:\laburo\Gestudio',
    [string] $DocumentRelativePath = 'GESTUDIO_RELEVAMIENTO_TECNICO_CONTINUIDAD.md',
    [switch] $Fetch,

    [ValidateSet('PARTIAL', 'BLOCKED', 'FAIL', 'IN_PROGRESS', 'PASS')]
    [string] $ReleaseReadiness = 'PARTIAL',

    [ValidateSet('INFO', 'PASS', 'FAIL', 'BLOCKED', 'PARTIAL', 'NOT_EXECUTED')]
    [string] $EventStatus = 'INFO',

    [string] $Event = '',
    [string] $CommandText = '',
    [string] $Result = '',
    [string] $NextAction = '',
    [string] $CiEvidence = '',
    [switch] $ConfirmReleasePass
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$ExpectedOriginFragment = 'JerePrograma/Gestudio'
$CurrentStart = '<!-- AUTO:CURRENT:START -->'
$CurrentEnd = '<!-- AUTO:CURRENT:END -->'
$EventsStart = '<!-- AUTO:EVENTS:START -->'
$EventsEnd = '<!-- AUTO:EVENTS:END -->'
$HistoryStart = '<!-- AUTO:HISTORY:START -->'
$HistoryEnd = '<!-- AUTO:HISTORY:END -->'

function Invoke-Git {
    param(
        [Parameter(Mandatory)]
        [string[]] $Arguments,
        [switch] $AllowFailure
    )

    $RawOutput = @(& git @Arguments 2>&1)
    $ExitCode = $LASTEXITCODE
    $Output = @($RawOutput | ForEach-Object { $_.ToString() })

    if (-not $AllowFailure -and $ExitCode -ne 0) {
        throw (@(
            "Falló: git $($Arguments -join ' ')"
            "Exit code: $ExitCode"
            ($Output -join "`n")
        ) -join "`n")
    }

    [pscustomobject]@{
        Output   = $Output
        Text     = $Output -join "`n"
        ExitCode = $ExitCode
    }
}

function ConvertTo-MarkdownCell {
    param([AllowEmptyString()][string] $Value)

    if ($null -eq $Value) {
        return ''
    }

    $Escaped = $Value.Replace('|', '\|')
    $Escaped = $Escaped.Replace("`r", '')
    $Escaped = $Escaped.Replace("`n", '<br>')
    return $Escaped
}

function Read-MarkedSection {
    param(
        [Parameter(Mandatory)][string] $Text,
        [Parameter(Mandatory)][string] $StartMarker,
        [Parameter(Mandatory)][string] $EndMarker
    )

    $StartIndex = $Text.IndexOf($StartMarker, [StringComparison]::Ordinal)

    if ($StartIndex -lt 0) {
        throw "No se encontró el marcador: $StartMarker"
    }

    $BodyStart = $StartIndex + $StartMarker.Length
    $EndIndex = $Text.IndexOf($EndMarker, $BodyStart, [StringComparison]::Ordinal)

    if ($EndIndex -lt 0) {
        throw "No se encontró el marcador: $EndMarker"
    }

    return $Text.Substring($BodyStart, $EndIndex - $BodyStart).Trim()
}

function Replace-MarkedSection {
    param(
        [Parameter(Mandatory)][string] $Text,
        [Parameter(Mandatory)][string] $StartMarker,
        [Parameter(Mandatory)][string] $EndMarker,
        [Parameter(Mandatory)][AllowEmptyString()][string] $Body
    )

    $StartIndex = $Text.IndexOf($StartMarker, [StringComparison]::Ordinal)

    if ($StartIndex -lt 0) {
        throw "No se encontró el marcador: $StartMarker"
    }

    $BodyStart = $StartIndex + $StartMarker.Length
    $EndIndex = $Text.IndexOf($EndMarker, $BodyStart, [StringComparison]::Ordinal)

    if ($EndIndex -lt 0) {
        throw "No se encontró el marcador: $EndMarker"
    }

    $Prefix = $Text.Substring(0, $BodyStart)
    $Suffix = $Text.Substring($EndIndex)
    return $Prefix + "`n" + $Body.Trim() + "`n" + $Suffix
}

function Write-Utf8NoBomAtomic {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][AllowEmptyString()][string] $Content
    )

    $Parent = Split-Path -Parent $Path
    $TemporaryPath = Join-Path $Parent ('.' + [IO.Path]::GetFileName($Path) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
    $Encoding = [Text.UTF8Encoding]::new($false)
    $Normalized = ($Content -replace "`r`n", "`n").TrimEnd() + "`n"

    try {
        [IO.File]::WriteAllText($TemporaryPath, $Normalized, $Encoding)
        Move-Item -LiteralPath $TemporaryPath -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $TemporaryPath) {
            Remove-Item -LiteralPath $TemporaryPath -Force
        }
    }
}

if (-not (Test-Path -LiteralPath $Repository -PathType Container)) {
    throw "No existe el repositorio: $Repository"
}

$Repository = [IO.Path]::GetFullPath($Repository).TrimEnd([char[]] @('\', '/'))
Set-Location -LiteralPath $Repository

$Root = (Invoke-Git -Arguments @('rev-parse', '--show-toplevel')).Text.Trim()
$Root = [IO.Path]::GetFullPath($Root).TrimEnd([char[]] @('\', '/'))

if (-not [StringComparer]::OrdinalIgnoreCase.Equals($Repository, $Root)) {
    throw "Checkout inesperado: $Root"
}

$OriginUrl = (Invoke-Git -Arguments @('remote', 'get-url', 'origin')).Text.Trim()

if ($OriginUrl -notlike "*$ExpectedOriginFragment*") {
    throw "origin inesperado: $OriginUrl"
}

$Branch = (Invoke-Git -Arguments @('branch', '--show-current')).Text.Trim()

if ($Branch -ne 'main') {
    throw "La rama activa debe ser main. Detectada: $Branch"
}

if ($Fetch) {
    Invoke-Git -Arguments @('fetch', 'origin', '--prune') | Out-Null
}

$Head = (Invoke-Git -Arguments @('rev-parse', 'HEAD')).Text.Trim()
$OriginResult = Invoke-Git -Arguments @('rev-parse', 'origin/main') -AllowFailure
$OriginMain = if ($OriginResult.ExitCode -eq 0) { $OriginResult.Text.Trim() } else { 'NO_DISPONIBLE' }

$DivergenceResult = Invoke-Git -Arguments @('rev-list', '--left-right', '--count', 'HEAD...origin/main') -AllowFailure
$Ahead = '?'
$Behind = '?'

if ($DivergenceResult.ExitCode -eq 0) {
    $DivergenceParts = @($DivergenceResult.Text.Trim() -split '\s+')

    if ($DivergenceParts.Count -ge 2) {
        $Ahead = $DivergenceParts[0]
        $Behind = $DivergenceParts[1]
    }
}

$Status = @((Invoke-Git -Arguments @('status', '--porcelain=v1', '--untracked-files=all')).Output | Where-Object { $_ })
$Unstaged = @((Invoke-Git -Arguments @('diff', '--name-only')).Output | Where-Object { $_ })
$Staged = @((Invoke-Git -Arguments @('diff', '--cached', '--name-only')).Output | Where-Object { $_ })
$Untracked = @((Invoke-Git -Arguments @('ls-files', '--others', '--exclude-standard')).Output | Where-Object { $_ })
$TrackedNameStatus = @((Invoke-Git -Arguments @('diff', '--name-status')).Output | Where-Object { $_ })
$CachedNameStatus = @((Invoke-Git -Arguments @('diff', '--cached', '--name-status')).Output | Where-Object { $_ })
$DiffStat = @((Invoke-Git -Arguments @('diff', '--stat')).Output | Where-Object { $_ })
$DiffCheck = Invoke-Git -Arguments @('diff', '--check') -AllowFailure
$CachedDiffCheck = Invoke-Git -Arguments @('diff', '--cached', '--check') -AllowFailure
$DiffCheckPassed = $DiffCheck.ExitCode -eq 0 -and $CachedDiffCheck.ExitCode -eq 0

$DockerReady = $false
$DockerState = 'NO_DISPONIBLE'
$ProtectedDemo = @('NO_VERIFICABLE: Docker Engine no está disponible.')
$DockerCommand = Get-Command -Name docker -ErrorAction SilentlyContinue

if ($null -ne $DockerCommand) {
    $DockerRaw = @(& docker version --format '{{.Server.Version}}' 2>&1)
    $DockerExitCode = $LASTEXITCODE
    $DockerOutput = @($DockerRaw | ForEach-Object { $_.ToString() })

    if ($DockerExitCode -eq 0 -and $DockerOutput.Count -gt 0) {
        $DockerReady = $true
        $DockerState = 'AVAILABLE server=' + ($DockerOutput -join ' ')
        $DemoRaw = @(& docker ps -a --filter 'name=gestudio-remote-demo' --format '{{.ID}}|{{.Names}}|{{.Image}}|{{.Status}}|{{.Ports}}' 2>&1)
        $DemoExitCode = $LASTEXITCODE
        $ProtectedDemo = @($DemoRaw | ForEach-Object { $_.ToString() })

        if ($DemoExitCode -ne 0) {
            $ProtectedDemo = @('NO_VERIFICABLE: falló docker ps read-only.')
        }
    }
    else {
        $DockerState = 'BLOCKED: ' + ($DockerOutput -join ' ')
    }
}

$DockerServiceState = try {
    $Service = Get-CimInstance -ClassName Win32_Service -Filter "Name='com.docker.service'" -ErrorAction Stop

    if ($null -eq $Service) {
        'NO_ENCONTRADO'
    }
    else {
        "State=$($Service.State); StartMode=$($Service.StartMode)"
    }
}
catch {
    "NO_VERIFICABLE: $($_.Exception.Message)"
}

if ($ReleaseReadiness -eq 'PASS') {
    if (-not $ConfirmReleasePass) {
        throw 'RELEASE_READINESS=PASS exige -ConfirmReleasePass.'
    }

    if ($Head -ne $OriginMain) {
        throw 'RELEASE_READINESS=PASS exige HEAD == origin/main.'
    }

    if ($Status.Count -gt 0) {
        throw 'RELEASE_READINESS=PASS exige árbol limpio.'
    }

    if ([string]::IsNullOrWhiteSpace($CiEvidence)) {
        throw 'RELEASE_READINESS=PASS exige -CiEvidence con la verificación del SHA publicado.'
    }
}

$Timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffK')
$HeadShort = $Head.Substring(0, [Math]::Min(12, $Head.Length))

$AutomaticNextAction = if ($Staged.Count -gt 0) {
    'Revisar el índice antes de continuar.'
}
elseif ($OriginMain -ne 'NO_DISPONIBLE' -and $Head -ne $OriginMain) {
    'Resolver la divergencia Git sin descartar ni reescribir trabajo.'
}
elseif ($Status.Count -gt 0) {
    'Congelar ediciones y renovar los gates invalidados.'
}
elseif (-not $DockerReady) {
    'Habilitar Docker manualmente y proteger la demo antes de los gates PostgreSQL.'
}
else {
    'Ejecutar y registrar los gates pendientes sobre este mismo SHA.'
}

$Warnings = [Collections.Generic.List[string]]::new()

if ($Status.Count -gt 0) { $Warnings.Add('El árbol contiene cambios.') }
if ($Staged.Count -gt 0) { $Warnings.Add('Existen cambios staged.') }
if ($OriginMain -eq 'NO_DISPONIBLE') { $Warnings.Add('origin/main no pudo verificarse.') }
elseif ($Head -ne $OriginMain) { $Warnings.Add("HEAD difiere de origin/main: ahead=$Ahead, behind=$Behind.") }
if (-not $DockerReady) { $Warnings.Add('Docker, PostgreSQL, Testcontainers y E2E siguen bloqueados.') }
if (-not $DiffCheckPassed) { $Warnings.Add('git diff --check detectó problemas.') }
if ($Warnings.Count -eq 0) { $Warnings.Add('No se detectaron advertencias estructurales.') }

$DocumentPath = [IO.Path]::GetFullPath((Join-Path $Repository $DocumentRelativePath))
$RepositoryPrefix = $Repository + [IO.Path]::DirectorySeparatorChar

if (-not $DocumentPath.StartsWith($RepositoryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'El documento debe quedar dentro del repositorio.'
}

if (-not (Test-Path -LiteralPath $DocumentPath -PathType Leaf)) {
    throw "No existe el documento: $DocumentPath"
}

$DocumentText = Get-Content -LiteralPath $DocumentPath -Raw
$WarningLines = ($Warnings | ForEach-Object { '- ' + $_ }) -join "`n"

$CurrentBody = @"
| Campo | Valor |
|---|---|
| Fecha | $(ConvertTo-MarkdownCell $Timestamp) |
| Repositorio | $(ConvertTo-MarkdownCell $Root) |
| Origin | $(ConvertTo-MarkdownCell $OriginUrl) |
| Rama | $Branch |
| HEAD | $Head |
| origin/main | $OriginMain |
| Divergencia | ahead=$Ahead; behind=$Behind |
| RELEASE_READINESS | **$ReleaseReadiness** |
| Unstaged | $($Unstaged.Count) |
| Staged | $($Staged.Count) |
| Untracked | $($Untracked.Count) |
| diff --check | $(if ($DiffCheckPassed) { 'PASS' } else { 'FAIL' }) |
| Docker | $(ConvertTo-MarkdownCell $DockerState) |
| Docker service | $(ConvertTo-MarkdownCell $DockerServiceState) |
| Evidencia CI | $(ConvertTo-MarkdownCell $CiEvidence) |
| Próxima acción | $(ConvertTo-MarkdownCell $AutomaticNextAction) |

### Advertencias

$WarningLines

### git status --short

~~~text
$($Status -join "`n")
~~~

### Cambios tracked sin stage

~~~text
$($TrackedNameStatus -join "`n")
~~~

### Resumen del diff

~~~text
$($DiffStat -join "`n")
~~~

### Cambios staged

~~~text
$($CachedNameStatus -join "`n")
~~~

### Archivos untracked

~~~text
$($Untracked -join "`n")
~~~

### git diff --check

~~~text
$($DiffCheck.Output -join "`n")
$($CachedDiffCheck.Output -join "`n")
~~~

### Demo protegida: consulta read-only

~~~text
$($ProtectedDemo -join "`n")
~~~
"@

$EventsBody = Read-MarkedSection -Text $DocumentText -StartMarker $EventsStart -EndMarker $EventsEnd

if (-not [string]::IsNullOrWhiteSpace($Event)) {
    $EventRow = @(
        '|',
        (ConvertTo-MarkdownCell $Timestamp),
        (ConvertTo-MarkdownCell $EventStatus),
        (ConvertTo-MarkdownCell $Event),
        (ConvertTo-MarkdownCell $CommandText),
        (ConvertTo-MarkdownCell $Result),
        (ConvertTo-MarkdownCell $NextAction),
        '|'
    ) -join ' | '

    $EventsBody = $EventsBody.TrimEnd() + "`n" + $EventRow
}

$HistoryBody = Read-MarkedSection -Text $DocumentText -StartMarker $HistoryStart -EndMarker $HistoryEnd
$DockerHistory = if ($DockerReady) { 'AVAILABLE' } else { 'BLOCKED' }
$HistoryRow = "| $Timestamp | $HeadShort | $Branch | $($Unstaged.Count) | $($Staged.Count) | $($Untracked.Count) | $DockerHistory | $ReleaseReadiness |"
$HistoryBody = $HistoryBody.TrimEnd() + "`n" + $HistoryRow

$DocumentText = Replace-MarkedSection -Text $DocumentText -StartMarker $CurrentStart -EndMarker $CurrentEnd -Body $CurrentBody
$DocumentText = Replace-MarkedSection -Text $DocumentText -StartMarker $EventsStart -EndMarker $EventsEnd -Body $EventsBody
$DocumentText = Replace-MarkedSection -Text $DocumentText -StartMarker $HistoryStart -EndMarker $HistoryEnd -Body $HistoryBody
Write-Utf8NoBomAtomic -Path $DocumentPath -Content $DocumentText

Write-Host "Documento actualizado: $DocumentPath"
Write-Host "HEAD=$Head"
Write-Host "origin/main=$OriginMain"
Write-Host "RELEASE_READINESS=$ReleaseReadiness"
Write-Host 'No se ejecutaron tests, Docker, staging, commit ni push.'
