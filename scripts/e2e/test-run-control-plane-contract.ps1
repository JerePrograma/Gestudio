[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$runnerPath = Join-Path $PSScriptRoot 'run-control-plane.ps1'
$specPath = Join-Path $repoRoot 'frontend\e2e\control-plane.spec.ts'

function Assert-Contains {
    param(
        [Parameter(Mandatory)][string] $Source,
        [Parameter(Mandatory)][string] $Marker,
        [Parameter(Mandatory)][string] $Failure
    )
    if ($Source.IndexOf($Marker, [StringComparison]::Ordinal) -lt 0) { throw $Failure }
}

function Assert-Ordered {
    param(
        [Parameter(Mandatory)][string] $Source,
        [Parameter(Mandatory)][string] $First,
        [Parameter(Mandatory)][string] $Second,
        [Parameter(Mandatory)][string] $Failure
    )
    $firstIndex = $Source.IndexOf($First, [StringComparison]::Ordinal)
    $secondIndex = $Source.IndexOf($Second, [StringComparison]::Ordinal)
    if ($firstIndex -lt 0 -or $secondIndex -lt 0 -or $firstIndex -ge $secondIndex) {
        throw $Failure
    }
}

foreach ($path in @($runnerPath, $specPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Falta archivo requerido por el contrato E2E: $path"
    }
}

$tokens = $null
$parseErrors = $null
[void][Management.Automation.Language.Parser]::ParseFile(
    $runnerPath,
    [ref]$tokens,
    [ref]$parseErrors)
if ($parseErrors.Count -ne 0) {
    throw 'run-control-plane.ps1 no supera el parseo AST.'
}

$runner = [IO.File]::ReadAllText($runnerPath)
$spec = [IO.File]::ReadAllText($specPath)

foreach ($requirement in @(
    @("GetEnvironmentVariable('DOCKER_HOST', 'Process')", 'Falta rechazo explicito de DOCKER_HOST.'),
    @("'context', 'show'", 'Falta resolver el contexto Docker activo.'),
    @("'context', 'inspect', '--format', '{{json .Endpoints.docker.Host}}'", 'Falta inspeccionar el endpoint Docker.'),
    @("^npipe://", 'Falta permitir exclusivamente named pipe local en Windows.'),
    @('unix:///var/run/docker.sock', 'Falta permitir exclusivamente el socket Docker local en Unix.'),
    @("'--context', `$context, 'info', '--format', '{{.OSType}}'", 'Falta inspeccionar el OSType del daemon fijado.'),
    @("`$osType.Trim() -cne 'linux'", 'Falta exigir un daemon Linux.'),
    @("SetEnvironmentVariable('DOCKER_CONTEXT', `$dockerContext, 'Process')", 'Falta fijar el contexto validado durante el run.'),
    @("Get-DockerProjectSnapshot -ProjectName 'gestudio-remote-demo'", 'Falta snapshot del demo protegido.'),
    @('Get-DockerProjectSnapshot -ProjectName $project', 'Falta snapshot del proyecto E2E aleatorio.'),
    @('{{.Id}}|{{.Image}}|{{.State.Status}}', 'Falta identidad y estado exactos de contenedores.'),
    @('{{.Name}}|{{.CreatedAt}}|{{.Driver}}|{{.Mountpoint}}|{{.Scope}}', 'Falta identidad exacta de volumenes.'),
    @('{{json .Containers}}', 'Falta estado exacto de conexiones de red.'),
    @('$projectBefore.Containers.Count -ne 0', 'Falta preflight de contenedores preexistentes.'),
    @('$projectBefore.Volumes.Count -ne 0', 'Falta preflight de volumenes preexistentes.'),
    @('$projectBefore.Networks.Count -ne 0', 'Falta preflight de redes preexistentes.'),
    @('$playwrightOutput = Join-Path $runRoot ''playwright-output''', 'El output Playwright no pertenece al temporal privado del run.'),
    @('GESTUDIO_E2E_OUTPUT_DIR = $playwrightOutput', 'El runner no entrega a Playwright el output privado del run.'),
    @('[Security.AccessControl.AccessControlSections]::Access', 'La ACL temporal no limita la lectura a la DACL.'),
    @('[IO.FileSystemAclExtensions]::GetAccessControl', 'La ACL temporal no usa lectura de acceso sin privilegios de SACL.'),
    @('[IO.FileSystemAclExtensions]::SetAccessControl', 'La ACL temporal no persiste la DACL restringida.'),
    @('Test-DockerProjectSnapshotInvariant -Before $projectBefore -After $projectAfter', 'Falta invariancia post-cleanup del proyecto E2E.'),
    @('Test-DockerProjectSnapshotInvariant -Before $protectedDemoBefore -After $protectedDemoAfter', 'Falta invariancia post-cleanup del demo protegido.'),
    @('protectedDemoInvariant = $protectedDemoInvariant', 'Falta resultado sanitizado de invariancia del demo.'),
    @('composeProjectInvariant = $projectInvariant', 'Falta resultado sanitizado de invariancia del proyecto E2E.'),
    @("`$_ -cne 'DO'", 'La salida fresh no elimina exclusivamente el command tag DO conocido.'),
    @('$freshRows.Count -ne 1', 'La salida fresh no exige una unica fila de estado.'),
    @('Estado actual: $freshState', 'El fallo fresh no conserva evidencia sanitizada para diagnostico.')
)) {
    Assert-Contains -Source $runner -Marker $requirement[0] -Failure $requirement[1]
}

if ($runner -notmatch '(?s)\$residual\s*=\s*@\(\s*@\(') {
    throw 'El inventario residual debe conservar semantica de array con cero o un recurso.'
}
if ($runner.IndexOf('.SetOwner(', [StringComparison]::Ordinal) -ge 0) {
    throw 'La ACL temporal no debe exigir privilegios de cambio de owner.'
}

Assert-Ordered -Source $runner `
    -First '$dockerContext = Assert-LocalDockerTarget' `
    -Second '$protectedDemoBefore = Get-DockerProjectSnapshot' `
    -Failure 'El snapshot protegido debe ocurrir despues del preflight Docker local.'
Assert-Ordered -Source $runner `
    -First '$protectedDemoBefore = Get-DockerProjectSnapshot' `
    -Second "[void](Invoke-Compose -Arguments @('up'" `
    -Failure 'El snapshot protegido debe ocurrir antes de Compose up.'
Assert-Ordered -Source $runner `
    -First '$projectBefore = Get-DockerProjectSnapshot' `
    -Second "[void](Invoke-Compose -Arguments @('up'" `
    -Failure 'El preflight del proyecto aleatorio debe ocurrir antes de Compose up.'
Assert-Ordered -Source $runner `
    -First '$protectedDemoBefore = Get-DockerProjectSnapshot' `
    -Second '[IO.Directory]::CreateDirectory($runRoot)' `
    -Failure 'El snapshot protegido debe ocurrir antes de crear recursos temporales del run.'

$cleanupIndex = $runner.LastIndexOf('            Remove-LabeledResources', [StringComparison]::Ordinal)
$projectAfterIndex = $runner.LastIndexOf(
    '$projectAfter = Get-DockerProjectSnapshot',
    [StringComparison]::Ordinal)
$protectedAfterIndex = $runner.LastIndexOf(
    '$protectedDemoAfter = Get-DockerProjectSnapshot',
    [StringComparison]::Ordinal)
if ($cleanupIndex -lt 0 -or $projectAfterIndex -le $cleanupIndex -or
    $protectedAfterIndex -le $projectAfterIndex) {
    throw 'Las invariancias Docker deben comprobarse despues del cleanup etiquetado.'
}
if ($runner.IndexOf("function Remove-PlaywrightOutput", [StringComparison]::Ordinal) -ge 0 -or
    $runner.IndexOf("frontendRoot 'test-results\\e2e'", [StringComparison]::Ordinal) -ge 0) {
    throw 'El runner conserva cleanup de un output Playwright compartido fuera del temporal privado.'
}
if ($runner.IndexOf("if (`$Kind -in @('volume', 'network'))", [StringComparison]::Ordinal) -lt 0 -or
    $runner.IndexOf('{{index .Labels "com.docker.compose.project"}}', [StringComparison]::Ordinal) -lt 0 -or
    $runner.IndexOf('{{index .Config.Labels "com.docker.compose.project"}}', [StringComparison]::Ordinal) -lt 0) {
    throw 'El cleanup no selecciona el contrato de labels correcto por tipo de recurso.'
}
foreach ($forbidden in @("'system', 'prune'", "'volume', 'prune'", "'network', 'prune'")) {
    if ($runner.IndexOf($forbidden, [StringComparison]::Ordinal) -ge 0) {
        throw 'El runner contiene un prune Docker fuera del scope exacto.'
    }
}

foreach ($requirement in @(
    @('type SensitiveAuditValues = Set<string>', 'Falta el Set de secretos emitidos.'),
    @('const containsSensitiveAuditMaterial =', 'Falta el scanner recursivo de auditoria.'),
    @('sensitiveAuditKeyPattern.test(key)', 'Falta inspeccion recursiva de claves.'),
    @('value.includes(secret)', 'Falta inspeccion de secretos conocidos dentro de valores.'),
    @('sensitiveValues.has(String(value))', 'Falta inspeccion de valores primitivos no string.'),
    @('Array.isArray(value)', 'Falta recursion sobre arrays.'),
    @('Object.entries(value).some', 'Falta recursion sobre objetos.'),
    @('bearerValuePattern.test(value)', 'Falta detectar credenciales Bearer.'),
    @('jwtValuePattern.test(value)', 'Falta detectar JWT por forma.'),
    @('recoveryValuePattern.test(value)', 'Falta detectar recovery codes por forma.'),
    @('otpValuePattern.test(value)', 'Falta detectar OTP por forma.'),
    @('otpauthValuePattern.test(value)', 'Falta detectar URIs otpauth.'),
    @('rememberSensitiveValue(sensitiveValues, await totp.next())', 'Falta registrar codigos TOTP emitidos.'),
    @('await rememberSessionCookies(', 'Falta registrar cookies refresh emitidas.'),
    @('await rememberStepUpProof(await proofPromise, sensitiveValues)', 'Falta registrar proofs step-up emitidos.'),
    @('activationToken: rememberSensitiveValue(', 'Falta registrar tokens de activacion emitidos.'),
    @('/platform/activate#token=${encodeURIComponent(activationToken)}', 'El token de activacion no usa un fragmento local.'),
    @('url.search === "" && url.hash === ""', 'Falta comprobar el saneamiento completo de la URL de activacion.'),
    @('containsSensitiveAuditMaterial(event, sensitiveValues)', 'Falta escanear el evento completo.'),
    @('containsSensitiveAuditMaterial(detail, sensitiveValues)', 'Falta escanear metadata JSON parseada.'),
    @('body.content.length !== counts.success + counts.denied', 'Falta impedir eventos fuera del conjunto auditado.'),
    @('assertSensitiveAuditScannerContract(sensitiveValues)', 'Falta caracterizacion ejecutable del scanner.')
)) {
    Assert-Contains -Source $spec -Marker $requirement[0] -Failure $requirement[1]
}
foreach ($forbiddenInterpolation in @('${secret}', '${knownSecret}')) {
    if ($spec.IndexOf($forbiddenInterpolation, [StringComparison]::Ordinal) -ge 0) {
        throw 'Una falla del scanner podria interpolar un secreto.'
    }
}
if ($spec.IndexOf('/platform/activate?token=', [StringComparison]::Ordinal) -ge 0) {
    throw 'El spec E2E aun coloca el token de activacion en el query string.'
}

Write-Host 'Contrato estatico control-plane E2E: PASS'
